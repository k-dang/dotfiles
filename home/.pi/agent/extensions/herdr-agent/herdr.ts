import { realpath } from "node:fs/promises";
import { isAbsolute } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

interface HerdrSpaces {
	spaces: Array<{
		id: string;
		machine: string | null;
		tabs: Array<{ id: string; terminals: Array<{ terminal: string; pane: string | null }> }>;
	}>;
}

interface CoreTerminal {
	address: string;
	cwd: string;
	state: string;
	labels: Record<string, string>;
}

async function cli<T>(pi: ExtensionAPI, command: string, args: string[]): Promise<T> {
	const result = await pi.exec(command, args, { timeout: 10_000, maxBuffer: 4 * 1024 * 1024 });
	if (result.code !== 0) throw new Error(`${command}: ${result.stderr.trim() || result.stdout.trim() || `exit ${result.code}`}`);
	const response = JSON.parse(result.stdout);
	if (response.error) throw new Error(`${command}: ${response.error}`);
	return response as T;
}

export function currentTerminal() {
	const id = process.env.HC_TERMINAL_ID;
	return id && /^t[0-9a-z]+$/.test(id) ? id : undefined;
}

export async function paneFor(pi: ExtensionAPI, terminal: string, cwd: string, appBin = "herdr-app", coreBin = "hc") {
	const [app, core] = await Promise.all([
		cli<HerdrSpaces>(pi, appBin, ["ls"]),
		cli<CoreTerminal>(pi, coreBin, ["get", terminal, "--json"]),
	]);
	if (core.address !== terminal || core.state !== "live") throw new Error("Main is not a live herdr-core terminal.");

	// Do not infer Main from window focus. A different pane can gain focus during the picker.
	const panes = app.spaces.filter((space) => space.machine === null && space.id === core.labels["herdr.space"])
		.flatMap((space) => space.tabs.filter((tab) => tab.id === core.labels["herdr.tab"]))
		.flatMap((tab) => tab.terminals.filter((item) => item.terminal === terminal && item.pane));
	if (panes.length !== 1 || !panes[0].pane) throw new Error("Could not locate Main in a local Herdr pane.");
	if (!core.cwd || !isAbsolute(core.cwd) || await realpath(core.cwd) !== await realpath(cwd)) {
		throw new Error("Herdr would start the support pane in a different directory from Main.");
	}
	return panes[0].pane;
}

export async function splitRight(pi: ExtensionAPI, pane: string, argv: string[], appBin = "herdr-app") {
	await cli(pi, appBin, ["do", "pane.split", JSON.stringify({ pane, direction: "right", argv })]);
}

export async function startDetached(pi: ExtensionAPI, coreBin: string, cwd: string, argv: string[]) {
	await cli(pi, coreBin, ["run", "--bg", "--json", "--no-parent", "--no-notify", "--cwd", cwd, "--name", "lab-agent", "--", ...argv]);
}
