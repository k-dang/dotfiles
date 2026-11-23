import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { registerHooks } from "node:module";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

const sdk = pathToFileURL(resolve(process.env.PI_SDK)).href;
registerHooks({
	resolve(specifier, context, next) {
		return next(specifier === "@earendil-works/pi-coding-agent" ? sdk : specifier, context);
	},
});
const { SessionManager } = await import(sdk);
const { default: split } = await import("../index.ts");

async function setup(t) {
	const cwd = await mkdtemp(join(tmpdir(), "pi-split-"));
	const dir = join(cwd, "sessions with spaces");
	const oldTerminal = process.env.HC_TERMINAL_ID;
	process.env.HC_TERMINAL_ID = "t1";
	t.after(async () => {
		if (oldTerminal === undefined) delete process.env.HC_TERMINAL_ID;
		else process.env.HC_TERMINAL_ID = oldTerminal;
		await rm(cwd, { recursive: true, force: true });
	});
	const main = SessionManager.create(cwd, dir);
	const append = (content) => main.appendMessage({ role: "user", content, timestamp: Date.now() });
	const root = append("Root");
	append("Inactive branch");
	main.branch(root);
	const state = main.appendCustomEntry("goal-state", { goal: { status: "active" } });
	const selected = append("Pick this message");
	const latest = append("Later active message");
	const spaces = [{ id: "space-main", machine: null, tabs: [{ id: "tab-main", terminals: [
		{ terminal: "t2", pane: "pane-other" }, { terminal: "t1", pane: "pane-main" },
	] }] }];
	const core = { address: "t1", state: "live", cwd, labels: { "herdr.space": "space-main", "herdr.tab": "tab-main" } };
	const calls = [];
	const notices = [];
	let command;
	split({
		registerCommand(name, registration) {
			assert.equal(name, "split");
			command = registration;
		},
		async exec(command, args) {
			calls.push([command, args]);
			const stdout = JSON.stringify(command === "hc" ? core : args[0] === "ls" ? { spaces } : { pane: "pane-branch", terminal: "t3" });
			return { code: 0, stdout, stderr: "" };
		},
	});
	const invoke = (pick = (items) => items[1], args = "") => command.handler(args, {
		mode: "tui", cwd, sessionManager: main,
		ui: { select: async (_title, items) => pick(items), notify: (message) => notices.push(message) },
	});
	return { cwd, dir, main, root, state, selected, latest, spaces, core, calls, notices, invoke, command };
}

test("--help displays examples locally, without Herdr or a session change", async (t) => {
	const { dir, main, calls, notices, invoke } = await setup(t);
	delete process.env.HC_TERMINAL_ID;
	const source = main.getSessionFile();
	const before = await readFile(source, "utf8");
	await invoke(() => assert.fail("help must not open the picker"), " --help ");
	assert.deepEqual(calls, []);
	assert.equal(notices.length, 1);
	assert.match(notices[0], /^Usage: \/split \[--help\]/);
	assert.match(notices[0], /Examples:\n +\/split +Pick.*\n +\/split --help +Print/);
	assert.match(notices[0], /Neither pane starts a model turn/);
	assert.deepEqual(await readdir(dir), [basename(source)]);
	assert.equal(await readFile(source, "utf8"), before);
});

test("autocomplete shows the help example and only completes a partial --help", async (t) => {
	const { command } = await setup(t);
	assert.match(command.description, /\/split --help/);
	for (const prefix of ["-", "--h", " --hel"]) {
		assert.deepEqual(command.getArgumentCompletions(prefix), [
			{ value: "--help", label: "--help", description: "Print usage and examples here without splitting" },
		]);
	}
	for (const prefix of ["", "--help", "--help ", "--unknown"]) {
		assert.equal(command.getArgumentCompletions(prefix), null);
	}
});

test("invalid arguments point to --help without splitting", async (t) => {
	const { dir, calls, notices, invoke } = await setup(t);
	await invoke(() => assert.fail("invalid arguments must not open the picker"), "--unknown");
	assert.deepEqual(calls, []);
	assert.match(notices[0], /Run \/split --help for examples/);
	assert.equal((await readdir(dir)).length, 1);
});

test("picks a message on the active path, writes the notice only to the copy, and targets Main's pane", async (t) => {
	const { cwd, main, root, state, selected, latest, calls, notices, invoke } = await setup(t);
	const source = main.getSessionFile();
	const before = await readFile(source, "utf8");
	await invoke((items) => {
		assert.deepEqual(items, ["3. user: Later active message", "2. user: Pick this message", "1. user: Root"]);
		return items[1];
	});
	assert.deepEqual(notices, []);
	const [app, [verb, command, payload]] = calls.at(-1);
	assert.deepEqual([app, verb, command], ["herdr-app", "do", "pane.split"]);
	const { pane, direction, argv } = JSON.parse(payload);
	assert.equal(pane, "pane-main");
	assert.equal(direction, "right");
	assert.deepEqual(argv.slice(0, 2), ["pi", "--session"]);
	const branch = SessionManager.open(argv[2]);
	assert.equal(branch.getCwd(), cwd);
	assert.equal(branch.getHeader().parentSession, source);
	assert.notEqual(branch.getSessionId(), main.getSessionId());
	assert.deepEqual(branch.getBranch().slice(0, -1).map(({ id }) => id), [root, state, selected]);
	assert.equal(branch.getEntry(state).customType, "herdr-split.history");
	assert.equal(branch.getEntry(state).data, undefined);
	const notice = branch.buildSessionContext().messages.at(-1);
	assert.equal(notice.role, "custom");
	assert.match(notice.content, /still running.*do not continue.*change files.*only on what I ask you next/);
	assert.equal(main.getSessionFile(), source);
	assert.equal(main.getLeafId(), latest);
	assert.equal(await readFile(source, "utf8"), before);
});

test("cancelling does not contact Herdr or create a branch", async (t) => {
	const { dir, calls, notices, invoke } = await setup(t);
	await invoke(() => undefined);
	assert.deepEqual(calls, []);
	assert.deepEqual(notices, []);
	assert.equal((await readdir(dir)).length, 1);
});

for (const scenario of ["wrong core labels", "ambiguous pane", "remote pane", "different working directory"]) {
	test(`refuses ${scenario} without writing or splitting`, async (t) => {
		const { cwd, dir, spaces, core, calls, notices, invoke } = await setup(t);
		if (scenario === "wrong core labels") core.labels["herdr.tab"] = "another-tab";
		if (scenario === "ambiguous pane") spaces[0].tabs[0].terminals.push({ terminal: "t1", pane: "duplicate" });
		if (scenario === "remote pane") spaces[0].machine = "remote";
		if (scenario === "different working directory") {
			core.cwd = join(cwd, "elsewhere");
			await mkdir(core.cwd);
		}
		await invoke();
		assert.equal(calls.length, 2);
		assert.match(notices[0], /^\/split: .* (local Herdr pane|working directory)/);
		assert.equal((await readdir(dir)).length, 1);
	});
}
