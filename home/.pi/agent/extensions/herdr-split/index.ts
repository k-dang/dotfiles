import { randomUUID } from "node:crypto";
import { realpath, writeFile } from "node:fs/promises";
import { isAbsolute, join } from "node:path";
import { stripVTControlCharacters } from "node:util";

import {
	CURRENT_SESSION_VERSION,
	SessionManager,
	type ExtensionAPI,
	type SessionEntry,
	type SessionHeader,
} from "@earendil-works/pi-coding-agent";

const HELP_OPTION = "--help";
const USAGE = `Usage: /split [${HELP_OPTION}]`;
const HELP = `${USAGE}

Examples:
  /split         Pick a user or assistant message (Esc cancels).
  /split --help  Print this guide here without splitting.

The new Pi pane opens to the right in the same working directory. It copies the active conversation through the selected message, inclusive. The new agent gets a notice to leave earlier work alone, expect concurrent file changes, and wait for your next request.

Neither pane starts a model turn, and the original session is untouched. Both panes still share the same files. Splitting requires a saved session in a local Herdr pane; /split never guesses which pane to use.`;

const NOTICE = "This conversation was split from another conversation that is still running. " +
	"Treat all earlier messages as background only; do not continue their work. " +
	"Expect the other conversation to change files in this same working directory. " +
	"Check the current files before acting, and do not overwrite or revert concurrent changes. " +
	"Act only on what I ask you next in this pane.";

interface HerdrSpaces {
	spaces: Array<{
		id: string;
		machine: string | null;
		tabs: Array<{ id: string; terminals: Array<{ terminal: string; pane?: string | null }> }>;
	}>;
}

interface CoreTerminal {
	address: string;
	state: string;
	cwd: string;
	labels: Record<string, string>;
}

async function cli<T>(pi: ExtensionAPI, command: string, args: string[]): Promise<T> {
	const result = await pi.exec(command, args, { timeout: 10_000, maxBuffer: 4 * 1024 * 1024 });
	if (result.code !== 0) {
		throw new Error(`${command}: ${result.stderr.trim() || result.stdout.trim() || `exit ${result.code}`}`);
	}
	return JSON.parse(result.stdout) as T;
}

async function sourcePane(pi: ExtensionAPI, terminalId: string, cwd: string): Promise<string> {
	const [app, terminal] = await Promise.all([
		cli<HerdrSpaces>(pi, "herdr-app", ["ls"]),
		cli<CoreTerminal>(pi, "hc", ["get", terminalId, "--json"]),
	]);
	if (terminal.address !== terminalId || terminal.state !== "live") {
		throw new Error("The current terminal is not live in herdr-core.");
	}

	// Terminal IDs are core-local. Match the owning space and tab as well, not the focused pane.
	const matches = app.spaces
		.filter((space) => space.machine === null && space.id === terminal.labels["herdr.space"])
		.flatMap((space) => space.tabs)
		.filter((tab) => tab.id === terminal.labels["herdr.tab"])
		.flatMap((tab) => tab.terminals)
		.filter((item) => item.terminal === terminalId && item.pane);
	const pane = matches[0]?.pane;
	if (matches.length !== 1 || !pane) {
		throw new Error("Could not identify exactly one local Herdr pane for this Pi terminal.");
	}
	if (!terminal.cwd || !isAbsolute(terminal.cwd) || await realpath(terminal.cwd) !== await realpath(cwd)) {
		throw new Error("Herdr would inherit a different working directory than this Pi session.");
	}
	return pane;
}

function messageChoices(branch: SessionEntry[]): Array<{ label: string; end: number }> {
	const choices: Array<{ label: string; end: number }> = [];
	for (const [index, entry] of branch.entries()) {
		if (entry.type !== "message" || (entry.message.role !== "user" && entry.message.role !== "assistant")) continue;
		const { role, content } = entry.message;
		const text = typeof content === "string" ? content : content.map((block) => block.type === "text" ? block.text : "").join(" ");
		const preview = stripVTControlCharacters(text).replace(/[\s\p{Cc}]+/gu, " ").trim();
		choices.push({
			label: `${choices.length + 1}. ${role}: ${preview.length > 110 ? `${preview.slice(0, 110)}…` : preview || "(no text)"}`,
			end: index + 1,
		});
	}
	return choices.reverse();
}

async function writeBranch(cwd: string, dir: string, source: string, entries: SessionEntry[]): Promise<string> {
	const header: SessionHeader = {
		type: "session",
		version: CURRENT_SESSION_VERSION,
		id: randomUUID(),
		timestamp: new Date().toISOString(),
		cwd,
		parentSession: source,
	};
	// Extension state can resume work (e.g. an active /goal). Keep these IDs for
	// parent links and compaction boundaries, but don't restore the state in the copy.
	const history: SessionEntry[] = entries.map((entry) => entry.type === "custom"
		? { ...entry, customType: "herdr-split.history", data: undefined }
		: entry);
	const branch = SessionManager.inMemory(cwd, undefined, [header, ...history]);
	branch.appendCustomMessageEntry("herdr-split", NOTICE, true);
	const file = join(dir, `${header.timestamp.replace(/[:.]/g, "-")}_${header.id}.jsonl`);
	// No writable manager ever opens the source. Save the notice before starting the child.
	await writeFile(file, [header, ...branch.getEntries()].map((entry) => JSON.stringify(entry) + "\n").join(""), {
		flag: "wx",
		mode: 0o600,
	});
	return file;
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("split", {
		description: "Pick a message to branch in Herdr; /split --help shows examples",
		getArgumentCompletions: (prefix) => {
			const partial = prefix.trimStart();
			// Keep bare /split and a fully typed --help ready to submit with Enter.
			return partial && partial !== HELP_OPTION && HELP_OPTION.startsWith(partial)
				? [{ value: HELP_OPTION, label: HELP_OPTION, description: "Print usage and examples here without splitting" }]
				: null;
		},
		handler: async (args, ctx) => {
			const option = args.trim();
			if (option === HELP_OPTION) {
				ctx.ui.notify(HELP, "info");
				return;
			}
			let file: string | undefined;
			try {
				if (option) throw new Error(`${USAGE}. Run /split --help for examples.`);
				const terminalId = process.env.HC_TERMINAL_ID;
				if (ctx.mode !== "tui" || !terminalId || !/^t[0-9a-z]+$/.test(terminalId)) {
					throw new Error("Run /split in the Pi terminal you want to branch inside Herdr.");
				}
				const source = ctx.sessionManager.getSessionFile();
				if (!source) throw new Error("This Pi session is not being saved.");
				const branch = ctx.sessionManager.getBranch();
				const choices = messageChoices(branch);
				if (!choices.length) throw new Error("There are no messages to branch from yet.");
				const picked = await ctx.ui.select("Copy conversation through which message?", choices.map(({ label }) => label));
				const choice = choices.find(({ label }) => label === picked);
				if (!choice) return;

				const pane = await sourcePane(pi, terminalId, ctx.cwd);
				file = await writeBranch(ctx.cwd, ctx.sessionManager.getSessionDir(), source, branch.slice(0, choice.end));
				await cli(pi, "herdr-app", ["do", "pane.split", JSON.stringify({
					pane,
					direction: "right",
					argv: ["pi", "--session", file],
				})]);
			} catch (error) {
				const reason = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`/split: ${reason}${file ? `\nThe branch is saved at ${file}.` : ""}`, "error");
			}
		},
	});
}
