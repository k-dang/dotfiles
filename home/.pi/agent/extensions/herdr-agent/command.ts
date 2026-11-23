import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

export const DEFAULT_MODEL = "anthropic/claude-haiku-5-5";

// Built-in agents. A saved agents/<name>/agent.md with the same name replaces the job.
export const PRESETS: Record<string, { hint: string; job: string }> = {
	critic: {
		hint: "Challenges each request and Main's work on it",
		job: `Act as an adversarial reviewer of each request the user gives Main, and of Main's reply. Check three things: does the prompt give Main enough to finish the whole task without guessing; what else the change touches that the user may not expect (existing data, other pages, other people); and whether the task is too big for one reviewable step, naming the first smaller step if so. Read the actual files before asserting a problem. Never praise or decide a missing answer yourself.`,
	},
	notes: {
		hint: "Keeps decisions, open questions and next steps",
		job: `Keep a concise record of the conversation in Main: what was decided and by whom, what is still open, and the next action. Record something as decided only when someone actually settled it. Never invent an owner or deadline.`,
	},
	research: {
		hint: "Checks claims against the project's files",
		job: `Check claims and answer open questions from Main's conversation with evidence. Read the local files with your tools and cite file paths and line numbers. You have no web access: say when a claim depends on outside facts you could not verify. Separate what you verified from what was merely said.`,
	},
	historian: {
		hint: "Answers questions about Main's history on request",
		job: `Answer the user's questions about what was said and decided earlier in Main's conversation.`,
	},
};

export const isHistorian = (name: string) => name.toLowerCase() === "historian";
export const USAGE = `Main: /agent [--model provider/id | --pick-model] <name> [job]
Support: /agent send main [#number]
Either pane: /agent --help`;
export const HELP = `${USAGE}

Open from the Pi pane you want to be Main (local Herdr only):
  /agent review Look for mistakes and missing tests
  /agent --model ${DEFAULT_MODEL} review Look for mistakes
  /agent --pick-model review
  /agent review                    Open a saved job
  /agent critic                    Open a built-in agent
  /agent                           List agents and usage

Built-in agents (names are not case sensitive):
  critic     Challenges each request and Main's work on it
  notes      Keeps decisions, open questions and next steps
  research   Checks claims against the project's files
  historian  Answers questions about Main's history; it does not follow
             Main but reads Main's saved session when you ask it something

Save a job at agents/<name>/agent.md in Main's working directory, or at
agents/<name>/agent.md inside your Pi config directory. The project wins.
Only text under the top-level “## Job” section is used, up to the next
level-1 or level-2 heading. A saved job with a built-in's name replaces the
built-in job. An inline job overrides both.
Put flags before the job; use -- before a job starting with --.
The default is ${DEFAULT_MODEL} (thinking off). The pickers use ↑/↓,
Enter to choose, Esc to cancel. Use Pi's /model in the support pane to switch later.

Main does not take a turn when you open a support pane. The support model
receives the job and new Main prompt and final-reply text after opening, not
older history, images, tool results, thinking, or another pane's messages.
Support runs with read-only file tools. Treat its findings as suggestions.

In the support pane:
  /agent send main #2              Queue finding #2 for Main
  /agent send main                 Pick a finding with ↑/↓, then Enter

Each finished support reply with a finding gets a number local to that pane.
Only findings you explicitly select are sent. They are attached as separate
context to your next new prompt submitted while Main is idle, not as a new
turn or during a running reply. Sending never types into Main's editor.
Closing support won't clear its sent findings. /new, /fork and /resume to a
different Main session do not carry over that session's feed or finding queue.`;

const NAME = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/;
const FLAGS = ["--help", "--model", "--pick-model"];

export function parseOpen(args: string) {
	let rest = args.trim();
	let name: string | undefined;
	let model: string | undefined;
	let pick = false;
	while (rest) {
		const [token] = rest.split(/\s+/, 1);
		const tail = rest.slice(token.length).trimStart();
		if (token === "--model" || token.startsWith("--model=")) {
			if (model || pick) throw new Error("Use only one of --model and --pick-model.");
			model = token === "--model" ? tail.split(/\s+/, 1)[0] : token.slice("--model=".length);
			if (!model || model.startsWith("-")) throw new Error("--model needs a Pi model ID or pattern.");
			rest = token === "--model" ? tail.slice(model.length).trimStart() : tail;
		} else if (token === "--pick-model") {
			if (model || pick) throw new Error("Use only one of --model and --pick-model.");
			pick = true;
			rest = tail;
		} else if (!name) {
			if (!NAME.test(token) || token === "send" || token === "main") {
				throw new Error("Use a name of 1–64 letters, numbers, underscores or hyphens (not ‘main’ or ‘send’).");
			}
			name = token;
			rest = tail;
		} else {
			if (token.startsWith("--") && token !== "--") throw new Error(`Unknown option ${token}. Use -- before literal job text.`);
			if (token === "--") rest = tail;
			break;
		}
	}
	if (!name) throw new Error("An agent name is required. See /agent --help.");
	return { name, model, pick, job: rest };
}

export function jobSection(markdown: string): string | undefined {
	const lines = markdown.split(/\r?\n/);
	let start: number | undefined;
	let fence: RegExp | undefined;
	for (const [i, line] of lines.entries()) {
		if (fence) {
			if (fence.test(line)) fence = undefined;
			continue;
		}
		const opening = /^ {0,3}(`{3,}|~{3,})/.exec(line)?.[1];
		if (opening) {
			fence = new RegExp(`^ {0,3}${opening[0]}{${opening.length},}[ \\t]*$`);
			continue;
		}
		if (start !== undefined && /^ {0,3}#{1,2}(?:\s|$)/.test(line)) return lines.slice(start, i).join("\n").trim();
		if (start === undefined && /^ {0,3}##[ \t]+Job(?:[ \t]+#+)?[ \t]*$/.test(line)) start = i + 1;
	}
	return start === undefined ? undefined : lines.slice(start).join("\n").trim();
}

/** The job for a name: a saved agent.md first, then the built-in. */
export function savedJob(roots: string[], name: string) {
	const job = savedFile(roots, name) ?? PRESETS[name.toLowerCase()]?.job;
	if (!job) throw new Error(`No saved agent ‘${name}’. Supply an inline job or run /agent to list agents.`);
	return job;
}

function savedFile(roots: string[], name: string) {
	for (const root of roots) {
		const file = join(root, name, "agent.md");
		try {
			const job = jobSection(readFileSync(file, "utf8"));
			if (!job) throw new Error(`No non-empty ## Job section in ${file}.`);
			return job;
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
		}
	}
}

export function savedNames(roots: string[]) {
	const names = new Set<string>();
	for (const root of roots) {
		try {
			for (const entry of readdirSync(root, { withFileTypes: true })) {
				if (!entry.isDirectory() || !NAME.test(entry.name) || entry.name === "send" || entry.name === "main") continue;
				try {
					if (!savedFile(roots, entry.name)) continue;
					names.add(entry.name);
				} catch { /* Missing or invalid saved job. */ }
			}
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
		}
	}
	return [...names].sort();
}

export function completions(prefix: string, names: string[], supporting: boolean) {
	const partial = prefix.trimStart();
	const saved = new Set(names.map((name) => name.toLowerCase()));
	const builtins = Object.keys(PRESETS).filter((name) => !saved.has(name));
	const options = supporting ? ["--help", "send main"] : [...FLAGS, ...builtins, ...names];
	return options.filter((value) => value !== partial && value.startsWith(partial)).map((value) => ({
		value, label: value,
		description: value === "--help" ? "Show the full guide" : value === "send main" ? "Choose a finding to send" :
			value === "--model" ? "Use an explicit Pi model" : value === "--pick-model" ? "Choose a Pi model" :
				builtins.includes(value) ? `Built-in · ${PRESETS[value].hint}` : "Open saved job",
	}));
}
