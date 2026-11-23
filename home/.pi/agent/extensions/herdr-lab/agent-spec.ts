import { lstat, mkdir, mkdtemp, open, rename, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { DEFAULT_MODEL, jobSection, parseOpen } from "../herdr-agent/command.ts";

export type Pane = "Main" | "Agent";
export type Action = { kind: "Do"; pane: Pane; text: string };
export type Check = { kind: "Expect" | "Never" | "See" | "Absent"; pane?: Pane; text: string };
export interface Expectation { title: string; actions: Action[]; checks: Check[] }
export interface TestSpec { before: Action[]; expectations: Expectation[] }

export function parseTestCommand(args: string) {
	const [mode, name, ...tokens] = args.split(/\s+/);
	if ((mode !== "new" && mode !== "test") || !name || name.startsWith("-")) throw new Error("Use /lab test <name> or /lab new <name>.");
	parseOpen(name);
	// Windows treats these as devices even when they have a file extension.
	if (/^(?:con|prn|aux|nul|com[0-9]|lpt[0-9])$/i.test(name)) throw new Error("Choose a name that is not a reserved device name.");
	const flags = new Map<string, string>();
	let behind = false;
	for (let i = 0; i < tokens.length; i++) {
		const separator = tokens[i].indexOf("=");
		const flag = separator < 0 ? tokens[i] : tokens[i].slice(0, separator);
		const inline = separator < 0 ? undefined : tokens[i].slice(separator + 1);
		if (flag === "--behind" && inline === undefined && !behind) { behind = true; continue; }
		if ((flag !== "--agent-model" && flag !== "--tester-model") || flags.has(flag)) throw new Error(`Unknown or repeated lab option: ${tokens[i]}.`);
		const model = inline ?? tokens[++i];
		if (!model || !/^[\w.][\w.-]*\/[a-z\d][\w.:/@+-]*$/i.test(model)) throw new Error(`${flag} needs a full provider/model-id.`);
		flags.set(flag, model);
	}
	return { mode, name, behind, agentModel: flags.get("--agent-model") ?? DEFAULT_MODEL, testerModel: flags.get("--tester-model") };
}

export function parseExpectations(markdown: string): TestSpec {
	const before: Action[] = [];
	const expectations: Expectation[] = [];
	let section: Expectation | "before" | undefined;
	let sawBefore = false;
	for (const [i, raw] of markdown.replace(/^\uFEFF/, "").split(/\r?\n/).entries()) {
		const line = raw.trim();
		if (!line) continue;
		const heading = /^(#{1,3})\s+(.+?)\s*#*$/.exec(line);
		if (heading) {
			const title = heading[2].trim();
			if (/^before$/i.test(title)) {
				if (sawBefore || expectations.length) throw new Error("Put a single Before section ahead of the expectations.");
				section = "before";
				sawBefore = true;
			} else if (heading[1] === "#" || /^expectations$/i.test(title)) {
				section = undefined;
			} else {
				section = { title: title.replace(/^expectation:\s*/i, "") || `Expectation ${expectations.length + 1}`, actions: [], checks: [] };
				expectations.push(section);
			}
			continue;
		}
		const directive = /^(?:[-*]\s+)?(Do|Expect|Never|See|Absent)(?:\s+\[(Main|Agent)\])?:\s*(\S.*)$/.exec(line);
		if (!directive || !section || directive[3].length > 2_000 || /[\p{Cc}]/u.test(directive[3])) {
			throw new Error(`expectations.md:${i + 1}: Expected a heading or a Do:, Expect:, Never:, See:, or Absent: line.`);
		}
		const [, kind, target, text] = directive;
		const pane = target as Pane | undefined;
		if (section === "before") {
			if (kind !== "Do" || pane === "Agent") throw new Error(`expectations.md:${i + 1}: Before can only type Do lines into Main.`);
			before.push({ kind, pane: "Main", text });
		} else if (kind === "Do") {
			if (section.checks.length) throw new Error(`expectations.md:${i + 1}: Put Do lines before checks in each expectation.`);
			section.actions.push({ kind, pane: pane ?? "Main", text });
		} else {
			section.checks.push({ kind: kind as Check["kind"], pane, text });
		}
	}
	if (!expectations.length || expectations.some(item => !item.checks.length)) throw new Error("Give each expectation a heading and at least one Expect, Never, See, or Absent check.");
	return { before, expectations };
}

async function statIfPresent(path: string) {
	return lstat(path).catch(error => {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	});
}

async function regularDirectory(path: string, create: boolean) {
	if (create) await mkdir(path, { mode: 0o700 }).catch(error => {
		if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
	});
	if (!(await lstat(path)).isDirectory()) throw new Error(`Expected a real directory, not a link: ${path}`);
	return path;
}

async function readMarkdown(path: string) {
	const stat = await statIfPresent(path);
	if (!stat) return undefined;
	if (!stat.isFile()) throw new Error(`Expected a regular file, not a link: ${path}`);
	const file = await open(path, "r");
	try {
		const buffer = Buffer.alloc(64 * 1024 + 1);
		let length = 0;
		while (length < buffer.length) {
			const { bytesRead } = await file.read(buffer, length, buffer.length - length);
			if (!bytesRead) break;
			length += bytesRead;
		}
		if (length === buffer.length) throw new Error(`Lab Markdown files are limited to 64 KiB: ${path}`);
		return buffer.toString("utf8", 0, length);
	} finally { await file.close(); }
}

export async function agentFiles(cwd: string, name: string, create: boolean) {
	const directory = await regularDirectory(join(await regularDirectory(join(cwd, "agents"), create), name), create);
	const expectations = join(directory, "expectations.md");
	const agent = join(directory, "agent.md");
	return {
		expectations, agent,
		readExpectations: () => readMarkdown(expectations),
		writeExpectations: (markdown: string) => writeFile(expectations, markdown, { flag: "wx", mode: 0o600 }),
		readAgent: () => readMarkdown(agent),
		writeAgent: async (markdown: string, overwrite: boolean) => {
			if (!overwrite) return writeFile(agent, markdown, { flag: "wx", mode: 0o600 });
			const temporary = await mkdtemp(join(directory, ".lab-job-"));
			try {
				const next = join(temporary, "job.txt");
				await writeFile(next, markdown, { flag: "wx", mode: 0o600 });
				// Rename replaces the entry instead of writing through a link.
				await rename(next, agent);
			} finally { await rm(temporary, { recursive: true, force: true }); }
		},
		reports: () => regularDirectory(join(directory, "reports"), true),
	};
}

export async function loadAgentSpec(files: Awaited<ReturnType<typeof agentFiles>>) {
	const [expectations, agent] = await Promise.all([files.readExpectations(), files.readAgent()]);
	if (expectations === undefined) throw new Error(`Missing ${files.expectations}. Start with /lab new.`);
	const job = agent === undefined ? undefined : jobSection(agent);
	if (!job) throw new Error(`Expected a non-empty ## Job section in ${files.agent}.`);
	return { spec: parseExpectations(expectations), job };
}

// Drop from Git's temporary index before materializing HEAD, not from the final copy.
export const PRIVATE_PATHS = ["agent.md", "expectations.md", "reports", "reports/**"].map(path => `:(glob,icase)**/agents/*/${path}`);
