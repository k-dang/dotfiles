import { spawn, type ChildProcess } from "node:child_process";
import { constants } from "node:fs";
import { access, appendFile, chmod, copyFile, cp, mkdir, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { stripVTControlCharacters } from "node:util";
import { fileURLToPath } from "node:url";
import type { LabLaunch } from "../herdr-agent/index.ts";
import { PRIVATE_PATHS } from "./agent-spec.ts";
import { exerciseAgent, type AgentTest, type Screens } from "./agent-test.ts";
import { positionBehind } from "./behind.ts";
import { stageExtensions } from "./guest-extensions.ts";
import { MODEL_MISMATCH, READY } from "./guest-fixture.mjs";
import { cli, describeChecks, doctor, isolatedEnv, privateScope, windows } from "./runtime.ts";
import type { Scenario } from "./scenario.ts";

async function until<T>(description: string, check: () => Promise<T | false>, timeout = 20_000, signal?: AbortSignal): Promise<T> {
	const deadline = Date.now() + timeout;
	let error: unknown;
	do {
		signal?.throwIfAborted();
		try {
			const result = await check();
			if (result !== false) return result;
		} catch (e) {
			signal?.throwIfAborted();
			error = e;
		}
		await delay(150, undefined, { signal });
	} while (Date.now() < deadline);
	throw new Error(`Timed out waiting for ${description}${error instanceof Error ? `: ${error.message}` : ""}.`);
}

export async function snapshot(git: string, cwd: string, root: string, env: NodeJS.ProcessEnv, signal?: AbortSignal) {
	const source = cli(git, cwd, env, signal);
	const repo = (await source(["rev-parse", "--show-toplevel"])).trim();
	const head = (await source(["rev-parse", "--verify", "HEAD^{commit}"])).trim();
	const objects = (await source(["rev-parse", "--path-format=absolute", "--git-path", "objects"])).trim();
	const work = join(root, "project");
	await mkdir(work);
	// A new repo uses neither the source index nor its hooks, filters, or remotes.
	// Read the source object database only for checkout. Symlinks become inert files.
	const checkout = cli(git, work, { ...env, GIT_ALTERNATE_OBJECT_DIRECTORIES: JSON.stringify(objects.replaceAll("\\", "/")) }, signal);
	await checkout(["init", "--quiet", "--template=", "--object-format", head.length === 64 ? "sha256" : "sha1"]);
	await checkout(["read-tree", head]);
	await checkout(["rm", "--cached", "-qrf", "--ignore-unmatch", "--", ...PRIVATE_PATHS]);
	await checkout(["-c", "core.symlinks=false", "checkout-index", "--all"]);
	await rm(join(work, ".git"), { recursive: true });
	const subdir = join(work, relative(await realpath(repo), await realpath(cwd)));
	return { work, cwd: await realpath(subdir).catch(() => work), head };
}

async function copyOptional(src: string, dest: string) {
	try {
		await copyFile(src, dest, constants.COPYFILE_EXCL);
		await chmod(dest, 0o600);
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	}
}

function clean(text: string) {
	return stripVTControlCharacters(text).replace(/\r\n/g, "\n").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
}

function collapsed(text: string) {
	return text.replace(/\s+/g, " ").trim();
}

function hasExited(pid: number) {
	try {
		process.kill(pid, 0);
		return false;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ESRCH") return true;
		throw error;
	}
}

type LabRun = {
	cwd: string; agentDir: string; defaultModel?: string; piEntry?: string; signal?: AbortSignal;
	onStep?: (step: number, total: number) => void;
} & ({ scenario: Scenario; test?: never } | { test: AgentTest; scenario?: never });

export async function runLab({ cwd, agentDir, scenario: replay, test, defaultModel, piEntry, signal, onStep }: LabRun) {
	const scenario: Scenario = replay ?? { panes: 1, modelTurns: true, steps: [] };
	const appMode = !test ? "required" : windows ? "optional" : "off";
	const { checks, programs } = await doctor({ cwd, piEntry, signal, appMode, split: !!test });
	signal?.throwIfAborted();
	const namedReportDir = test && await mkdtemp(join(test.reports, `${new Date().toISOString().slice(0, 10)}-`));
	if (!programs) {
		const detail = describeChecks(checks);
		if (!namedReportDir) throw new Error(`Preflight failed. No lab was started.\n${detail}`);
		const report = join(namedReportDir, "report.md");
		await writeFile(report, `# Herdr Lab · ${test.name}\n\n**Preflight failed.** No lab was started.\n\n${detail.split("\n").map(line => `    ${line}`).join("\n")}\n`, { mode: 0o600 });
		return { ok: false, cancelled: false, cleanupOk: true, report };
	}
	const { root, name, env } = await privateScope("hlab-");
	const title = `Herdr Lab ${name.slice("herdr-lab-".length)}`;
	const model = scenario.model ?? defaultModel;
	const guestEnv: Record<string, string> = {
		HERDR_LAB_MODEL: model ?? "",
		HERDR_LAB_MODEL_TURNS: scenario.modelTurns ? "1" : "0",
	};
	const appHome = env.HERDR_APP_HOME!;
	const profile = env.PI_CODING_AGENT_DIR!;
	const appBin = programs.app && join(root, `herdr-app${windows ? ".exe" : ""}`);
	const coreBin = join(env.HC_INSTALL_DIR!, `herdr-core${windows ? ".exe" : ""}`);
	const appControl = appBin ? cli(appBin, root, env) : undefined;
	const coreControl = cli(coreBin, root, env);
	const app = appBin ? cli(appBin, root, env, signal) : undefined;
	const hc = cli(coreBin, root, env, signal);
	const space = `${name}-space`;
	const tab = `${name}-tab`;
	const panes: string[] = [];
	const evidence = [`# ${title}${test ? ` · ${test.name}` : ""}`, "", "Verdicts use only visible terminal text (`hc read --lines 0`). PNGs, if present, are for visual review."];
	const cleanup: string[] = [];
	let report = "";
	let reportDir = "";
	let window: ChildProcess | undefined;
	let coreAttempted = false;
	let exiting: Promise<void> | undefined;
	let corePid: number | undefined;
	let ok = false;
	let cancelled = false;
	let shotCount = 0;
	let stepNumber = 0;

	const readPane = async (terminal: string) => clean(await hc(["read", terminal, "--lines", "0"]));
	const activity = async (role: "main" | "agent") => JSON.parse(await readFile(join(root, `${role}-activity.json`), "utf8")) as { state: string; terminal?: string };
	const attached = async (terminal: string) => {
		if (!app) return true;
		const { spaces } = JSON.parse(await app(["ls"], 2_000));
		return spaces.some((s: { id: string; machine: string | null; tabs: Array<{ id: string; terminals: Array<{ terminal: string; pane?: string }> }> }) =>
			s.id === space && s.machine === null && s.tabs.some(t => t.id === tab && t.terminals.some(p => p.terminal === terminal && p.pane)));
	};
	const quiet = async (): Promise<Screens> => {
		let stableSince = 0;
		let previous = "";
		const outcome = await until("the lab panes to become idle and their screens to stop changing", async () => {
			const states = await Promise.all(panes.map((_, index) => activity(index ? "agent" : "main")));
			const stopped = states.findIndex((state, index) => state.terminal !== panes[index] || state.state === "closed" || state.state === "model-mismatch");
			if (stopped >= 0) return { error: `${stopped ? "Agent" : "Main"} pane could not continue (${states[stopped].state}).` };
			if (states.some(state => state.state !== "idle")) { stableSince = 0; return false; }
			const [Main, Agent = ""] = await Promise.all(panes.map(readPane));
			const screens = { Main, Agent };
			const current = JSON.stringify(screens);
			if (!stableSince || current !== previous) { stableSince = Date.now(); previous = current; }
			// /agent polls Main's feed every 750 ms, even after Main goes idle.
			return Date.now() - stableSince >= 1_600 ? { screens } : false;
		}, 90_000, signal);
		if (outcome.error) throw new Error(outcome.error);
		return outcome.screens!;
	};
	const observation = (label: string, text: string) => evidence.push(`\n**${label}**\n\n${text.replace(/\n$/, "").split("\n").map(line => `    ${line}`).join("\n")}\n`);
	const shot = async (terminal?: string, finalEvidence = false) => {
		if (!app || !appControl || !window || window.exitCode !== null) throw new Error("Lab window is not running.");
		if (terminal) {
			await app(["do", "pane.focus", JSON.stringify({ terminal })]);
			observation(`Pane ${panes.indexOf(terminal) + 1} at capture`, await readPane(terminal));
		}
		const file = `window-${++shotCount}.png`;
		const capture = ["shot", join(reportDir, file)];
		if (finalEvidence) await appControl(capture, 2_000);
		else await until("a lab window frame", () => app(capture, 2_000), 5_000, signal);
		await access(join(reportDir, file));
		evidence.push(`![Lab window ${shotCount}](${file})`);
	};

	try {
		reportDir = namedReportDir ?? await mkdtemp(join(tmpdir(), `${name}-report-`));
		report = join(reportDir, "report.md");
		await Promise.all([appHome, profile, env.HOME!, env.APPDATA!, env.LOCALAPPDATA!, env.XDG_RUNTIME_DIR!, env.HC_INSTALL_DIR!].map(path => mkdir(path, { mode: 0o700 })));
		evidence.push(`\nScratch: \`${root}\``);
		const project = await snapshot(programs.git, cwd, root, env, signal);
		evidence.push(`\nSnapshot: \`${project.head}\` (HEAD, no local edits or private agent test files).`);
		if (test) {
			evidence.push(`\nAgent model: \`${test.agentModel}\`. Tester model: ${test.testerModel ? `\`${test.testerModel}\`` : "not needed"}.`);
			evidence.push(app ? "\nDesktop lab." : "\nDetached core session; desktop layout and screenshots are unavailable.");
		}
		evidence.push(`\nRequested model: ${model ? `\`${model}\` (${scenario.model ? "scenario override" : "launching Pi"})` : "Pi automatic selection"}.`);
		const sources = test ? ["installed:herdr-agent"] : scenario.extensions ?? [];
		if (sources.length) evidence.push(`\nExplicit extension sources:\n\n    ${JSON.stringify(sources)}`);
		// Named tests use the sibling /agent extension distributed with /lab.
		const extensionProfile = test ? fileURLToPath(new URL("../../", import.meta.url)) : agentDir;
		const extensions = await stageExtensions(sources, { project: project.work, agentDir: extensionProfile, scratch: root });
		signal?.throwIfAborted();
		await Promise.all(["auth.json", "models.json", "models-store.json"].map(file => copyOptional(join(agentDir, file), join(profile, file))));
		signal?.throwIfAborted();
		await Promise.all([appBin && copyFile(programs.app!, appBin), copyFile(programs.core, coreBin)]);
		if (windows) {
			await cp(join(dirname(programs.core), "conpty"), join(dirname(coreBin), "conpty"), { recursive: true });
		}
		signal?.throwIfAborted();
		const fixture = join(root, "lab-probe.mjs");
		const preload = join(root, "pi-env.cjs");
		if (test) {
			const launch: LabLaunch = { root, name: test.name, model: test.agentModel, jobFile: join(root, "job.txt"), coreBin, appBin, preload, fixture };
			await writeFile(launch.jobFile, test.job, { flag: "wx", mode: 0o600 });
			guestEnv.HERDR_LAB_AGENT = JSON.stringify(launch);
		}
		Object.assign(env, guestEnv);
		const titleMod = join(appHome, "mods", "lab-title");
		if (app) await mkdir(titleMod, { recursive: true });
		await Promise.all([
			copyFile(fileURLToPath(new URL("./guest-fixture.mjs", import.meta.url)), fixture),
			// Windows refreshes a terminal's environment from the account registry.
			// Reassert the private profile before Pi's configuration is loaded.
			writeFile(preload, `Object.assign(process.env, ${JSON.stringify({
				...isolatedEnv({}, root, name), ...guestEnv,
			})});`),
		]);
		if (app) {
			await Promise.all([
				writeFile(join(appHome, "settings.json"), JSON.stringify({ core: coreBin, telemetry: false, sounds: { enabled: false } })),
				writeFile(join(appHome, "shared.json"), JSON.stringify({ "frame.welcomed": "lab" })),
				writeFile(join(titleMod, "mod.json"), JSON.stringify({ place: "bottom", size: 22 })),
				writeFile(join(titleMod, "main.js"), `import { View, div } from "gpui-kit";\nimport { checking, setWindowTitle, theme } from "herdr";\nexport default class extends View { init() { if (!checking()) setWindowTitle(${JSON.stringify(title)}); } render() { return div().px(8).text_size(12).text_color(theme().muted).child(${JSON.stringify(title)}); } }`),
			]);
			await app(["check", titleMod]);
		}
		signal?.throwIfAborted();
		coreAttempted = true;
		// Let server start settle before stop can race it, even on cancellation.
		const started = JSON.parse(await coreControl(["server", "start", "--json"], 30_000));
		if (!Number.isSafeInteger(started.pid) || started.pid <= 0) throw new Error("Lab core did not report a PID.");
		corePid = started.pid;
		signal?.throwIfAborted();
		if (app && appBin) {
			const sendBehind = windows && test?.behind ? await positionBehind(root, signal) : undefined;
			window = spawn(appBin, [], { cwd: root, env, stdio: "ignore" });
			exiting = new Promise(resolve => window!.once("close", () => resolve()));
			await new Promise<void>((resolve, reject) => window!.once("spawn", resolve).on("error", reject));
			await until("the isolated window", () => app(["status"], 2_000), 20_000, signal);
			if (sendBehind) await until("the lab window to move behind the active window", () => sendBehind(window!.pid!), 8_000, signal);
			// Personal mods don't dock into a shipped layout, even in a private app home.
			await app(["do", "layout.clone", JSON.stringify({ name: "main", as: "lab" })]);
		}

		for (let n = 1; n <= scenario.panes; n++) {
			const terminal = JSON.parse(await hc(["run", "--bg", "--json", "--no-parent", "--no-notify", "--cwd", project.cwd,
				...(app ? ["--label", `herdr.space=${space}`, "--label", `herdr.tab=${tab}`] : []), "--name", test ? "lab-main" : `lab-pane-${n}`, "--",
				process.execPath, "--require", preload, programs.piEntry, "--offline", "--no-extensions", "--no-mcp", "--no-skills", "--no-prompt-templates",
				"--no-themes", "--no-context-files", "--no-approve", "--no-tools", "--session-dir", env.PI_CODING_AGENT_SESSION_DIR!,
				...(model ? ["--model", model] : []), ...[fixture, ...extensions].flatMap(path => ["-e", path])])).address;
			if (typeof terminal !== "string" || !/^t[0-9a-z]+$/.test(terminal)) throw new Error("Expected a local lab pane address.");
			panes.push(terminal);
			if (app) await until(`pane ${n} to appear in the lab window`, () => attached(terminal), 20_000, signal);
			const startup = await until(`pane ${n} to show the Pi ready message`, async () => {
				const screen = await readPane(terminal);
				return (screen.includes(READY) || screen.includes(MODEL_MISMATCH)) && screen;
			}, 20_000, signal);
			if (startup.includes(MODEL_MISMATCH)) {
				observation(`Pane ${n} startup`, startup);
				throw new Error(`Guest Pi did not select ${model}. Check that it is available to the isolated Pi profile, or pin an available model in a scenario file.`);
			}
		}
		if (app) {
			await app(["do", "space.rename", JSON.stringify({ id: space, name: title })]);
			await app(["do", "tab.rename", JSON.stringify({ id: tab, name: "Pi lab" })]);
		}
		if (test) {
			ok = await exerciseAgent(test, {
				quiet, onStep, observe: observation, record: text => evidence.push(text),
				send: async ({ pane, text }) => { await hc(["send", panes[pane === "Agent" ? 1 : 0], "--", text]); },
				openAgent: async () => {
					await hc(["send", panes[0], "--", "/agent --lab-job"]);
					const support = await until("/agent to start the support pane beside Main", async () => {
						const { terminal } = await activity("agent");
						return terminal && /^t[0-9a-z]+$/.test(terminal) && terminal !== panes[0] && await attached(terminal) && terminal;
					}, 25_000, signal);
					panes.push(support);
				},
			}, signal);
			if (app) await shot().catch(error => {
				signal?.throwIfAborted();
				evidence.push(`\nWindow screenshot unavailable: ${clean(String(error))}`);
			});
		} else {
			for (const step of scenario.steps) {
				signal?.throwIfAborted();
				const n = step.pane ?? 1;
				const terminal = panes[n - 1];
				evidence.push(`\n### Step ${++stepNumber} · Pane ${n}\n\n    ${JSON.stringify(step)}\n`);
				onStep?.(stepNumber, scenario.steps.length);
				if ("send" in step) await hc(["send", terminal, "--", step.send]);
				else if ("keys" in step) await hc(["keys", terminal, ...step.keys]);
				else if ("expect" in step) {
					let seen = "";
					try {
						await until(`pane ${n} to show ${JSON.stringify(step.expect)}`, async () => {
							seen = await readPane(terminal);
							return collapsed(seen).includes(collapsed(step.expect));
						}, 10_000, signal);
						evidence.push("Matched in the visible pane.");
					} finally {
						observation("Visible pane text", seen);
					}
				} else await shot(terminal);
			}
			const last = scenario.steps.at(-1)!;
			if (!("shot" in last)) await shot(panes[(last.pane ?? 1) - 1]);
			evidence.push("\n**Replay completed.** All requested text checks matched. Visual review is separate.");
			ok = true;
		}
	} catch (error) {
		ok = false;
		cancelled = !!signal?.aborted;
		evidence.push(`\n**Run stopped:** ${cancelled ? "Cancelled; no remaining steps were sent." : clean(error instanceof Error ? error.message : String(error))}`);
		const last = panes[(scenario.steps[stepNumber - 1]?.pane ?? 1) - 1] ?? panes[0];
		for (const [i, terminal] of (test ? panes : last ? [last] : []).entries()) {
			const read = await coreControl(["read", terminal, "--lines", "0"], 2_000).catch(() => "");
			if (read) observation(test ? `Last visible text — ${i ? "Agent" : "Main"}` : "Last visible pane text", clean(read));
		}
		if (window && reportDir) await shot(undefined, true).catch(() => evidence.push("No additional window frame was available."));
	} finally {
		try {
			if (report) await writeFile(report, `${evidence.join("\n")}\n`, { mode: 0o600 });
		} finally {
			if (window && exiting && appControl) {
				await appControl(["do", "window.close"], 3_000).catch(() => {});
				if (!await Promise.race([exiting.then(() => true), delay(3_000, false)])) {
					window.kill();
					if (!await Promise.race([exiting.then(() => true), delay(3_000, false)])) cleanup.push("Lab window did not exit.");
				}
			}
			if (coreAttempted) {
				try {
					// A normal stop ends programs and holders, not just the listener.
					await coreControl(["server", "stop", "--json"], 35_000);
					const pid = corePid;
					if (pid) await until("the lab core process to exit", async () => hasExited(pid), 5_000);
				} catch (error) { cleanup.push(`Could not confirm the lab core stopped: ${String(error)}`); }
			}
			try {
				await rm(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
			} catch (error) { cleanup.push(`Could not delete scratch directory ${root}: ${String(error)}`); }
			if (report) await appendFile(report, `\n## Cleanup\n\n${cleanup.length ? cleanup.map(line => `- ${line}`).join("\n") : "Lab window closed, lab core stopped, and scratch directory removed (where started)."}\n`);
		}
	}
	if (!report) throw new Error(evidence.at(-1));
	return { ok: ok && !cleanup.length, cancelled, cleanupOk: !cleanup.length, report };
}
