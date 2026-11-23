import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { registerHooks } from "node:module";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { parseExpectations, parseTestCommand } from "../agent-spec.ts";
import { evaluate, exerciseAgent } from "../agent-test.ts";
import { stageExtensions } from "../guest-extensions.ts";
import { runLab, snapshot } from "../runner.ts";
import { doctor, isolatedEnv } from "../runtime.ts";
import { parseScenario, smoke } from "../scenario.ts";

// Mock the SDK/profile and the command's runner, not the live integration test's runner.
const callRunner = Symbol.for("lab.test.runLab");
const entryUrl = new URL("../index.ts", import.meta.url).href;
registerHooks({
	resolve(specifier, context, next) {
		if (specifier === "@earendil-works/pi-coding-agent") {
			return { url: "data:text/javascript,export function getAgentDir(){return 'test-agent'}", shortCircuit: true };
		}
		if (specifier === "./runner.ts" && context.parentURL === entryUrl) {
			return { url: "data:text/javascript,export const runLab=(args)=>globalThis[Symbol.for('lab.test.runLab')](args)", shortCircuit: true };
		}
		return next(specifier, context);
	},
});
const { default: lab } = await import("../index.ts");

function setup(overrides = {}) {
	let command;
	let shutdown;
	const finished = Promise.withResolvers();
	const notices = [];
	const ctx = {
		mode: "tui", cwd: process.cwd(), ...overrides,
		ui: {
			notify: (message) => notices.push(message),
			setStatus: (_key, text) => { if (text === undefined) finished.resolve(); },
			...overrides.ui,
		},
	};
	lab({
		on(event, handler) { assert.equal(event, "session_shutdown"); shutdown = handler; },
		registerCommand(name, registration) { assert.equal(name, "lab"); command = registration; },
	});
	return { command, notices, finished: finished.promise, invoke: (args) => command.handler(args, ctx), shutdown };
}

test("bare /lab and --help show usage; typing suggests subcommands", async () => {
	const { command, notices, invoke } = setup();
	globalThis[callRunner] = () => assert.fail("help must not start the runner");
	assert.match(command.description, /\/lab --help/);
	assert.deepEqual(command.getArgumentCompletions(" --h").map(item => item.value), ["--help"]);
	assert.deepEqual(command.getArgumentCompletions("do").map(item => item.value), ["doctor"]);
	assert.deepEqual(command.getArgumentCompletions("run ").map(item => item.value), ["run smoke", "run file"]);
	for (const prefix of ["--help", "--bad", "doctor", "run Type a command"]) {
		assert.equal(command.getArgumentCompletions(prefix), null);
	}
	await invoke("");
	await invoke(" --help ");
	assert.equal(notices[0], notices[1]);
	assert.match(notices[0], /^Usage: \/lab .*\n\nExamples:/);
	for (const example of ["/lab doctor", "/lab run smoke", "/lab run file scenarios.json", "/lab stop", "/lab --help"]) {
		assert.ok(notices[0].includes(example));
	}
	await invoke("--bad");
	await invoke("stop");
	assert.match(notices[2], /Run \/lab --help for usage/);
	assert.match(notices[3], /No run is active/);
});

test("loads a file with spaces and stop signals the active job without opening another", async (t) => {
	const cwd = await mkdtemp(join(tmpdir(), "pi-lab-command-"));
	t.after(() => rm(cwd, { recursive: true, force: true }));
	await writeFile(join(cwd, "my scenario.json"), '{"steps":[{"send":"/lab-probe one"}]}');
	const started = Promise.withResolvers();
	let calls = 0;
	globalThis[callRunner] = async ({ scenario, signal }) => {
		calls++;
		started.resolve(scenario);
		if (!signal.aborted) await new Promise(resolve => signal.addEventListener("abort", resolve, { once: true }));
		return { ok: false, cancelled: true, cleanupOk: true, report: "test-report.md" };
	};
	const { invoke, notices, finished } = setup({ cwd });
	await invoke("run file my scenario.json");
	assert.deepEqual((await started.promise).steps, [{ send: "/lab-probe one", pane: 1 }]);
	await invoke("run smoke");
	await invoke("stop");
	await finished;
	assert.equal(calls, 1);
	assert.ok(notices.includes("/lab: Stopped and cleaned up. Report: test-report.md"));
});

test("a description uses only the description and never replays a declined draft", async () => {
	const description = "Send /lab-probe hi and check the echo";
	const mocked = { steps: [{ send: "/lab-probe hi" }, { expect: "Lab probe received: hi" }] };
	globalThis[callRunner] = () => assert.fail("declined scenarios must not start");
	const { invoke, notices, finished } = setup({
		model: { id: "fake-model" },
		modelRegistry: { async complete(_model, prompt) {
			assert.equal(prompt.messages.length, 1);
			assert.equal(prompt.messages[0].content[0].text, description);
			return { stopReason: "stop", content: [{ type: "text", text: JSON.stringify(mocked) }] };
		} },
		ui: { confirm: async () => false },
	});
	await invoke(`run ${description}`);
	await finished;
	assert.ok(notices.some(message => message.startsWith("Review the proposed lab steps:")));
	assert.ok(notices.some(message => message.includes("Draft declined. No lab started.")));
});

test("file opt-in requires approval and passes the source list plus the launching model", async (t) => {
	const cwd = await mkdtemp(join(tmpdir(), "pi-lab-opt-in-"));
	t.after(() => rm(cwd, { recursive: true, force: true }));
	await writeFile(join(cwd, "scenario.json"), '{"model":"test/pinned","extensions":["installed:herdr-split"],"steps":[{"send":"/split --help"}]}');
	let approval = false;
	let args;
	globalThis[callRunner] = async (input) => {
		assert.ok(approval);
		args = input;
		return { ok: true, cancelled: false, cleanupOk: true, report: "test-report.md" };
	};
	const confirm = async (title, message) => {
		assert.match(title, /trusted Pi extensions/);
		assert.match(message, /installed:herdr-split/);
		return approval;
	};
	const declined = setup({ cwd, ui: { confirm } });
	await declined.invoke("run file scenario.json");
	await declined.finished;
	assert.equal(args, undefined);
	assert.ok(declined.notices.some(message => message.includes("Extension loading declined")));

	approval = true;
	const accepted = setup({ cwd, model: { provider: "test", id: "inherited" }, ui: { confirm } });
	await accepted.invoke("run file scenario.json");
	await accepted.finished;
	assert.equal(args.defaultModel, "test/inherited");
	assert.equal(args.scenario.model, "test/pinned");
	assert.deepEqual(args.scenario.extensions, ["installed:herdr-split"]);
	assert.equal(args.scenario.modelTurns, false);
});

test("named tests load only the Job, choose the requested judge, and use real project reports", async (t) => {
	const cwd = await mkdtemp(join(tmpdir(), "pi-lab-named-"));
	t.after(() => rm(cwd, { recursive: true, force: true }));
	const folder = join(cwd, "agents", "checker");
	await mkdir(folder, { recursive: true });
	await writeFile(join(folder, "expectations.md"), "# Expectations\n## Response\nExpect [Agent]: a greeting\n");
	await writeFile(join(folder, "agent.md"), "# Not the job\n## Job\nSay hello.\nThen wait.\n## Hidden\nOther material.");
	const judgeModel = { provider: "demo", id: "judge" };
	let judged = false;
	globalThis[callRunner] = async ({ test }) => {
		assert.equal(test.job, "Say hello.\nThen wait.");
		assert.equal(test.name, "checker");
		assert.equal(test.behind, true);
		assert.equal(test.agentModel, "demo/fast");
		assert.equal(test.testerModel, "demo/judge");
		assert.equal(test.reports, join(folder, "reports"));
		await access(test.reports);
		assert.equal((await evaluate(test.spec.expectations[0].checks[0], { Main: "private Main", Agent: "Hello" }, test.judge)).ok, true);
		return { ok: true, cleanupOk: true, report: join(test.reports, "test.md") };
	};
	const { invoke, finished, notices } = setup({ cwd, modelRegistry: {
		getAvailable: () => [judgeModel],
		async complete(model, request) {
			assert.equal(model, judgeModel);
			assert.deepEqual(JSON.parse(request.messages[0].content[0].text), { kind: "Expect", condition: "a greeting", screens: { Agent: "Hello" } });
			judged = true;
			return { stopReason: "stop", content: [{ type: "text", text: '{"status":"observed","quotes":[{"pane":"Agent","text":"Hello"}]}' }] };
		},
	} });
	await invoke("test checker --behind --agent-model demo/fast --tester-model=demo/judge");
	await finished;
	assert.ok(judged, notices.join("\n"));
	assert.match(notices.at(-1), /Checks passed/);
});

test("new writes a draft before approval, and reuses existing expectations byte for byte", async (t) => {
	const cwd = await mkdtemp(join(tmpdir(), "pi-lab-author-"));
	t.after(() => rm(cwd, { recursive: true, force: true }));
	const folder = join(cwd, "agents", "checker");
	const expectations = join(folder, "expectations.md");
	const job = join(folder, "agent.md");
	let written;
	let calls = 0;
	globalThis[callRunner] = async () => { calls++; return { ok: true, cleanupOk: true, report: "test.md" }; };
	const model = { provider: "demo", id: "judge" };
	const declined = setup({ cwd, model, ui: {
		input: async (_question, suggestion) => { assert.ok(suggestion); return ""; },
		confirm: async () => {
			written = await readFile(expectations);
			assert.match(written.toString(), /Expect \[Agent\]:/);
			await assert.rejects(access(job), { code: "ENOENT" });
			return false;
		},
	} });
	await declined.invoke("new checker");
	await declined.finished;
	assert.equal(calls, 0);
	assert.ok(written, declined.notices.join("\n"));
	const kept = setup({ cwd, model, ui: {
		input: async (question, suggestion) => { assert.match(question, /agent's job/); assert.ok(suggestion); return "Stay helpful."; },
		confirm: async () => assert.fail("pre-existing expectations should not need approval again"),
	} });
	await kept.invoke("new checker");
	await kept.finished;
	assert.equal(calls, 1, kept.notices.join("\n"));
	assert.deepEqual(await readFile(expectations), written);
	assert.equal(await readFile(job, "utf8"), "# checker\n\n## Job\n\nStay helpful.\n");
});

test("new waits for approval before creating agent.md and running", async (t) => {
	const cwd = await mkdtemp(join(tmpdir(), "pi-lab-approve-"));
	t.after(() => rm(cwd, { recursive: true, force: true }));
	const approval = Promise.withResolvers();
	const prompted = Promise.withResolvers();
	const job = join(cwd, "agents", "new-agent", "agent.md");
	let ran = false;
	globalThis[callRunner] = async () => { ran = true; await access(job); return { ok: true, cleanupOk: true, report: "test.md" }; };
	const session = setup({ cwd, model: { provider: "demo", id: "judge" }, ui: {
		input: async () => "",
		confirm: () => { prompted.resolve(); return approval.promise; },
	} });
	await session.invoke("new new-agent");
	await prompted.promise;
	await assert.rejects(access(job), { code: "ENOENT" });
	assert.equal(ran, false);
	approval.resolve(true);
	await session.finished;
	assert.equal(ran, true, session.notices.join("\n"));
});

test("Markdown keeps Before separate and does not treat checks or fenced examples as input", () => {
	const spec = parseExpectations("# Expectations\r\n## Before\r\n- Do: setup\r\n## Expectations\r\n### First\r\nDo [Agent]: /agent send main #1\r\nSee [Main]: ready\r\nNever: leakage\r\n### Second\r\nAbsent: hidden\r\n");
	assert.deepEqual(spec.before, [{ kind: "Do", pane: "Main", text: "setup" }]);
	assert.deepEqual(spec.expectations.map(item => item.title), ["First", "Second"]);
	assert.deepEqual(spec.expectations[0].actions, [{ kind: "Do", pane: "Agent", text: "/agent send main #1" }]);
	assert.deepEqual(spec.expectations[0].checks.map(item => [item.kind, item.pane]), [["See", "Main"], ["Never", undefined]]);
	for (const bad of ["## Before\nSee: setup", "## Before\nDo [Agent]: setup", "## First\nSee: ready\nDo: too late", "## First\n```\nDo: no\n```", "## First\nDo: no checks"]) {
		assert.throws(() => parseExpectations(bad));
	}
	assert.match(parseTestCommand("test checker").agentModel, /haiku/);
	for (const bad of ["test ../checker", "test nul", "test checker --agent-model bare", "test checker --behind=false", "test checker --behind --behind"]) assert.throws(() => parseTestCommand(bad));
});

test("literal checks bypass the judge; semantic checks reject missing and wrong-pane quotes", async () => {
	const screens = { Main: "main text", Agent: "seen text\non screen" };
	const noJudge = () => assert.fail("literal checks must not call a model");
	const check = (kind, text, pane) => ({ kind, text, pane });
	assert.equal((await evaluate(check("See", "seen text"), screens, noJudge)).ok, true);
	assert.equal((await evaluate(check("Absent", "seen text", "Main"), screens, noJudge)).ok, true);
	assert.equal((await evaluate(check("Absent", "seen text"), screens, noJudge)).ok, false);
	const judged = (status, quotes) => async () => JSON.stringify({ status, quotes });
	const quote = (pane, text) => ({ pane, text });
	assert.equal((await evaluate(check("Expect", "ok"), screens, judged("observed", [quote("Agent", "seen text\non screen")]))).ok, true);
	for (const quotes of [[], [quote("Main", "seen text")], [quote("Agent", "seen text on screen")], [quote("Agent", "seen text"), quote("Main", "made-up")]]) {
		assert.match((await evaluate(check("Expect", "ok"), screens, judged("observed", quotes))).detail, /Rejected/);
	}
	assert.equal((await evaluate(check("Never", "bad"), screens, judged("not_observed", []))).ok, true);
	assert.equal((await evaluate(check("Never", "bad"), screens, judged("not_observed", [quote("Agent", "not on screen")]))).ok, false);
	assert.equal((await evaluate(check("Never", "bad"), screens, judged("unclear", []))).ok, false);
});

test("the driver sends only Do lines in order and finishes Before before opening the agent", async () => {
	const timeline = [];
	const spec = parseExpectations("## Before\nDo: setup\n## First\nDo: ask\nDo [Agent]: /agent send main #1\nSee: ok\n## Second\nAbsent: bad\n");
	const ok = await exerciseAgent({ spec }, {
		send: async ({ pane, text }) => timeline.push(`${pane}: ${text}`),
		openAgent: async () => timeline.push("open"),
		quiet: async () => { timeline.push("quiet"); return { Main: "ready", Agent: "ok" }; },
		record: () => {}, observe: () => {},
	});
	assert.ok(ok);
	assert.deepEqual(timeline, ["Main: setup", "quiet", "open", "quiet", "Main: ask", "quiet", "Agent: /agent send main #1", "quiet", "quiet"]);
});

test("HEAD snapshot omits committed agent specs and reports, even below the repo root", async (t) => {
	const root = await mkdtemp(join(tmpdir(), "pi-lab-snapshot-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const repo = join(root, "repo");
	const scratch = join(root, "scratch");
	await Promise.all([repo, scratch].map(path => mkdir(path)));
	for (const base of [repo, join(repo, "nested")]) {
		const agent = join(base, "agents", "test");
		await mkdir(join(agent, "reports", "run"), { recursive: true });
		await writeFile(join(agent, "agent.md"), "private job");
		await writeFile(join(agent, "Expectations.md"), "private checks");
		await writeFile(join(agent, "reports", "run", "report.md"), "private result");
		await writeFile(join(agent, "other.md"), "public material");
	}
	for (const args of [["init", "--quiet"], ["add", "."], ["-c", "user.name=Lab Test", "-c", "user.email=lab@example.invalid", "commit", "-qm", "fixture"]]) {
		execFileSync("git", args, { cwd: repo });
	}
	const { work } = await snapshot("git", join(repo, "nested"), scratch, isolatedEnv(process.env, scratch, "unit"));
	for (const base of [work, join(work, "nested")]) {
		const agent = join(base, "agents", "test");
		for (const privatePath of ["agent.md", "Expectations.md", "reports"]) await assert.rejects(access(join(agent, privatePath)), { code: "ENOENT" });
		assert.equal(await readFile(join(agent, "other.md"), "utf8"), "public material");
	}
});

test("trusted installed extensions are copied, and repo-relative entries stay in the snapshot", async (t) => {
	const root = await mkdtemp(join(tmpdir(), "pi-lab-extensions-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const agentDir = join(root, "profile");
	const project = join(root, "snapshot");
	const scratch = join(root, "lab");
	const installed = join(agentDir, "extensions", "herdr-split", "index.ts");
	const fromSnapshot = join(project, "ext", "probe.mjs");
	await Promise.all([installed, fromSnapshot].map(file => mkdir(dirname(file), { recursive: true })));
	await writeFile(installed, "installed code");
	await writeFile(fromSnapshot, "snapshot code");
	const [one, two] = await stageExtensions(["installed:herdr-split", "ext/probe.mjs"], { project, agentDir, scratch });
	assert.equal(one, join(scratch, "extensions", "1", "herdr-split", "index.ts"));
	assert.equal(await readFile(one, "utf8"), "installed code");
	await writeFile(one, "modified lab copy");
	assert.equal(await readFile(installed, "utf8"), "installed code");
	assert.equal(await readFile(two, "utf8"), "snapshot code");
	await assert.rejects(stageExtensions(["ext/untracked.ts"], { project, agentDir, scratch }), /committed HEAD snapshot/);
	await assert.rejects(stageExtensions(["../profile"], { project, agentDir, scratch }), /repo-relative path/);
});

test("only admits explicit actions, model IDs, extension sources, and valid local pane numbers", () => {
	assert.deepEqual(parseScenario('{"panes":2,"steps":[{"send":"/lab-probe hi","pane":2},{"shot":true}]}'), {
		panes: 2, modelTurns: false, steps: [{ send: "/lab-probe hi", pane: 2 }, { shot: true, pane: 1 }],
	});
	assert.equal(parseScenario('{"model":"openrouter/a/b:free","steps":[{"shot":true}]}').model, "openrouter/a/b:free");
	for (const config of [
		{ model: "auto" }, { model: "--option/provider" }, { extensions: ["installed:../daily"] },
		{ extensions: ["C:\\daily\\extension.ts"] }, { extensions: ["/daily/extension.ts"] },
		{ extensions: ["abc.ts", "abc.ts"] }, { extensions: ["abc/../escape.ts"] },
	]) assert.throws(() => parseScenario(JSON.stringify({ ...config, steps: [{ shot: true }] })));
	for (const bad of [
		{}, { panes: null, steps: [{ shot: true }] }, { steps: [{ shot: true, pane: 2 }] },
		{ steps: [{ send: "x", keys: ["enter"] }] }, { steps: [{ keys: ["--help"] }] },
		{ steps: [{ send: "first\nsecond" }] }, { steps: [{ exec: "anything" }] },
	]) assert.throws(() => parseScenario(JSON.stringify(bad)));
});

test("daily sockets, app, profile, Git overrides, and parent IDs cannot route lab commands", () => {
	const root = resolve("scratch");
	const name = "herdr-lab-test";
	const env = isolatedEnv({
		HC_SESSION: "daily", HC_SOCKET: "daily-pipe", hc_terminal_id: "t1", HC_TERMINAL_SOCKET: "daily-holder", HC_SCOPE: "daily",
		HERDR_APP_HOME: "daily-app", HERDR_APP_ID: "daily", PI_CODING_AGENT_DIR: "daily-profile", PI_PACKAGE_DIR: "daily-package",
		PI_CODING_AGENT_SESSION_DIR: "daily-sessions", GIT_DIR: "daily-git", SSH_CONNECTION: "remote", HOME: "daily-home",
		OPENAI_API_KEY: "test-env-auth",
	}, root, name);
	assert.equal(env.HC_SESSION, name);
	assert.equal(env.HERDR_APP_ID, name);
	for (const [key, dir] of Object.entries({ HERDR_APP_HOME: "app", PI_CODING_AGENT_DIR: "pi", XDG_STATE_HOME: "state", HOME: "home" })) {
		assert.equal(env[key], join(root, dir));
	}
	for (const key of ["HC_SOCKET", "hc_terminal_id", "HC_TERMINAL_SOCKET", "HC_SCOPE", "PI_PACKAGE_DIR", "GIT_DIR", "SSH_CONNECTION"]) {
		assert.equal(env[key], undefined);
	}
	assert.equal(env.OPENAI_API_KEY, "test-env-auth");
});

test("live doctor checks required commands without starting a lab", { skip: !process.env.PI_LAB_CLI }, async () => {
	const result = await doctor({ cwd: process.cwd(), piEntry: resolve(process.env.PI_LAB_CLI) });
	assert.ok(result.programs, JSON.stringify(result.checks));
	assert.deepEqual(result.checks.map(c => c.name), ["Herdr app", "Herdr app CLI", "Herdr core CLI", "Pi CLI", "Git project"]);
	assert.ok(result.checks.every(c => c.ok));
});

test("live Herdr: routes input to two real panes, captures evidence, and removes scratch", {
	skip: !process.env.PI_LAB_CLI, timeout: 120_000,
}, async () => {
	const result = await runLab({
		cwd: process.cwd(),
		agentDir: process.env.PI_LAB_AUTH_DIR ?? join(homedir(), ".pi", "agent"),
		piEntry: resolve(process.env.PI_LAB_CLI),
		defaultModel: process.env.PI_LAB_TEST_MODEL,
		scenario: { ...smoke, panes: 2, steps: [...smoke.steps,
			{ send: "/lab-probe beta", pane: 2 }, { expect: "Lab probe received: beta", pane: 2 }, { shot: true, pane: 2 },
		] },
	});
	console.log(`Lab evidence: ${result.report}`);
	const report = await readFile(result.report, "utf8");
	assert.equal(result.ok, true, report);
	if (process.env.PI_LAB_TEST_MODEL) assert.ok(report.includes(`Requested model: \`${process.env.PI_LAB_TEST_MODEL}\` (launching Pi)`));
	assert.match(report, /Lab probe received: alpha/);
	assert.match(report, /Lab probe received: beta/);
	assert.match(report, /scratch directory removed/);
	await access(join(dirname(result.report), "window-1.png"));
	await access(join(dirname(result.report), "window-2.png"));
	await assert.rejects(access(report.match(/^Scratch: `(.+)`$/m)[1]), { code: "ENOENT" });
});

test("live Herdr: stop interrupts an expectation, keeps partial evidence, and removes scratch", {
	skip: !process.env.PI_LAB_CLI, timeout: 120_000,
}, async () => {
	const stop = new AbortController();
	const result = await runLab({
		cwd: process.cwd(),
		agentDir: process.env.PI_LAB_AUTH_DIR ?? join(homedir(), ".pi", "agent"),
		piEntry: resolve(process.env.PI_LAB_CLI),
		signal: stop.signal,
		onStep: (step) => { if (step === 3) setTimeout(() => stop.abort(), 200); },
		scenario: { panes: 1, modelTurns: false, steps: [
			{ send: "/lab-probe before stop" }, { expect: "Lab probe received: before stop" },
			{ expect: "a sentinel that cannot appear" }, { send: "/lab-probe must not send" },
		] },
	});
	console.log(`Stopped lab evidence: ${result.report}`);
	const report = await readFile(result.report, "utf8");
	assert.equal(result.cancelled, true, report);
	assert.equal(result.cleanupOk, true, report);
	assert.match(report, /Lab probe received: before stop/);
	assert.match(report, /Cancelled; no remaining steps were sent/);
	assert.doesNotMatch(report, /must not send/);
	await access(join(dirname(result.report), "window-1.png"));
	await assert.rejects(access(report.match(/^Scratch: `(.+)`$/m)[1]), { code: "ENOENT" });
});

test("live Herdr: /agent only receives the Job and new Main turns; local test reports are retained", {
	skip: !process.env.PI_LAB_CLI, timeout: 150_000,
}, async (t) => {
	const root = await mkdtemp(join(tmpdir(), "pi-lab-live-agent-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const cwd = join(root, "repo");
	const profile = join(root, "profile");
	const agent = join(cwd, "agents", "checker");
	const reports = join(agent, "reports");
	await Promise.all([reports, profile].map(path => mkdir(path, { recursive: true })));
	const job = "JOB-IN-ISOLATION\nReply in a single short line.";
	await writeFile(join(agent, "agent.md"), `# PRIVATE-METADATA\n\n## Job\n\n${job}\n`);
	await writeFile(join(agent, "expectations.md"), "## Hook\nSee: PRIVATE-EXPECTATION\n");
	await writeFile(join(reports, "old.md"), "PRIVATE-REPORT");
	await writeFile(join(cwd, "README.md"), "lab smoke fixture");
	for (const args of [["init", "--quiet"], ["add", "."], ["-c", "user.name=Lab Test", "-c", "user.email=lab@example.invalid", "commit", "-qm", "fixture"]]) {
		execFileSync("git", args, { cwd });
	}
	const requests = [];
	const server = createServer(async (req, res) => {
		let body = "";
		for await (const chunk of req) body += chunk;
		const input = JSON.parse(body);
		requests.push(input);
		const message = input.model === "fast" ? "Support mock finding" : "Main mock reply";
		res.writeHead(200, { "Content-Type": "text/event-stream" });
		for (const choice of [{ delta: { role: "assistant", content: message }, finish_reason: null }, { delta: {}, finish_reason: "stop" }]) {
			res.write(`data: ${JSON.stringify({ id: "lab-mock", object: "chat.completion.chunk", created: 1, model: input.model, choices: [{ index: 0, ...choice }] })}\n\n`);
		}
		res.end("data: [DONE]\n\n");
	});
	await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
	t.after(() => { server.closeAllConnections(); server.close(); });
	const mockModel = id => ({ id, name: id, input: ["text"], contextWindow: 8192, maxTokens: 1024, reasoning: false });
	await writeFile(join(profile, "models.json"), JSON.stringify({ providers: { "lab-mock": {
		baseUrl: `http://127.0.0.1:${server.address().port}/v1`, api: "openai-completions", apiKey: "lab-test-not-a-secret",
		models: [mockModel("fast"), mockModel("main")],
	} } }));
	const result = await runLab({
		cwd, agentDir: profile, piEntry: resolve(process.env.PI_LAB_CLI), defaultModel: "lab-mock/main",
		test: { name: "checker", job, reports, agentModel: "lab-mock/fast", behind: process.platform === "win32", spec: parseExpectations(
			"## Before\nDo: MAIN-BEFORE-ONLY\n## First\nDo: MAIN-NEW-PROMPT\nSee [Main]: Main mock reply\nSee [Agent]: Support mock finding\nAbsent [Agent]: MAIN-BEFORE-ONLY\n## Send\nDo [Agent]: /agent send main #1\nSee [Agent]: Queued finding #1\n",
		) },
	});
	const report = await readFile(result.report, "utf8");
	assert.ok(result.report.startsWith(reports), result.report);
	assert.equal(result.ok, true, report);
	assert.equal(requests[0]?.model, "main");
	const support = requests.filter(request => request.model === "fast");
	assert.ok(support.length >= 2);
	assert.match(JSON.stringify(support[0].messages), /JOB-IN-ISOLATION/);
	assert.match(JSON.stringify(support.at(-1).messages), /MAIN-NEW-PROMPT/);
	assert.doesNotMatch(JSON.stringify(support), /MAIN-BEFORE-ONLY|PRIVATE-(?:METADATA|EXPECTATION|REPORT)/);
});

test("live Herdr: selects the pinned model and loads the opt-in /split extension", {
	skip: !process.env.PI_LAB_CLI || !process.env.PI_LAB_TEST_MODEL || !process.env.PI_LAB_TEST_SPLIT, timeout: 120_000,
}, async () => {
	const model = process.env.PI_LAB_TEST_MODEL;
	const result = await runLab({
		cwd: process.cwd(),
		agentDir: process.env.PI_LAB_AUTH_DIR ?? join(homedir(), ".pi", "agent"),
		piEntry: resolve(process.env.PI_LAB_CLI),
		defaultModel: "invalid-provider/should-not-be-selected",
		scenario: { panes: 1, modelTurns: false, model, extensions: [`installed:${process.env.PI_LAB_TEST_SPLIT}`], steps: [
			{ send: "/split --help" }, { expect: "Usage: /split [--help]" }, { shot: true },
		] },
	});
	console.log(`Pinned model and /split evidence: ${result.report}`);
	const report = await readFile(result.report, "utf8");
	assert.equal(result.ok, true, report);
	assert.ok(report.includes(`Requested model: \`${model}\` (scenario override)`));
	assert.match(report, /The new Pi pane opens to the right/);
	assert.doesNotMatch(report, /Herdr lab model mismatch/);
	await access(join(dirname(result.report), "window-1.png"));
	await assert.rejects(access(report.match(/^Scratch: `(.+)`$/m)[1]), { code: "ENOENT" });
});
