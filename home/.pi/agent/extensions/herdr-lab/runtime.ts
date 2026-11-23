import { execFile } from "node:child_process";
import { randomBytes } from "node:crypto";
import { constants } from "node:fs";
import { access, mkdtemp, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, delimiter, dirname, isAbsolute, join } from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);
export const windows = process.platform === "win32";

export function isolatedEnv(source: NodeJS.ProcessEnv, root: string, name: string): NodeJS.ProcessEnv {
	const env = Object.fromEntries(Object.entries(source).filter(([key]) =>
		!/^(?:HC_|HERDR_|PI_|GIT_|SSH_(?:CLIENT|CONNECTION|TTY)$|NODE_OPTIONS$)/i.test(key)));
	const home = join(root, "home");
	return {
		...env,
		HOME: home,
		USERPROFILE: home,
		APPDATA: join(root, "roaming"),
		LOCALAPPDATA: join(root, "local"),
		XDG_CONFIG_HOME: join(root, "config"),
		XDG_STATE_HOME: join(root, "state"),
		XDG_DATA_HOME: join(root, "data"),
		XDG_CACHE_HOME: join(root, "cache"),
		XDG_RUNTIME_DIR: join(root, "run"),
		HC_SESSION: name,
		HC_INSTALL_DIR: join(root, "bin"),
		HC_LAUNCHD_DIRECT: "1",
		HERDR_APP_HOME: join(root, "app"),
		HERDR_APP_ID: name,
		HERDR_CORE_DIRS: join(root, "bin"),
		HERDR_APP_NO_SOUND: "1",
		HERDR_TELEMETRY: "0",
		HERDR_RELEASES_URL: "http://127.0.0.1:0",
		PI_CODING_AGENT_DIR: join(root, "pi"),
		PI_CODING_AGENT_SESSION_DIR: join(root, "pi", "sessions"),
		PI_OFFLINE: "1",
		PI_TELEMETRY: "0",
		GIT_CONFIG_NOSYSTEM: "1",
		GIT_CONFIG_GLOBAL: windows ? "NUL" : "/dev/null",
	};
}

async function executable(name: string): Promise<string> {
	for (const entry of (process.env.PATH ?? "").split(delimiter)) {
		if (!isAbsolute(entry)) continue;
		const file = join(entry, `${name}${windows ? ".exe" : ""}`);
		try {
			await access(file, constants.X_OK);
			return await realpath(file);
		} catch { /* try the next directory */ }
	}
	throw new Error(`Could not find ${name} on PATH.`);
}

export function cli(file: string, cwd: string, env: NodeJS.ProcessEnv, signal?: AbortSignal) {
	return async (args: string[], timeout = 10_000) => {
		signal?.throwIfAborted();
		try {
			const { stdout } = await exec(file, args, { cwd, env, timeout, signal, maxBuffer: 1024 * 1024, windowsHide: true });
			signal?.throwIfAborted();
			return stdout;
		} catch (error) {
			signal?.throwIfAborted();
			// execFile's message repeats the arguments (which may contain user input).
			const e = error as { code?: number | string; killed?: boolean; stderr?: string };
			throw new Error(`${basename(file)} ${args[0]} failed${e.killed ? " (timed out)" : ` (${e.code ?? "unknown error"})`}${e.stderr?.trim() ? `: ${e.stderr.trim()}` : ""}`);
		}
	};
}

export async function privateScope(prefix: string) {
	// Keep Unix-domain socket paths short; macOS's TMPDIR is often already long.
	const root = await mkdtemp(join(windows ? tmpdir() : "/tmp", prefix));
	const name = `herdr-lab-${randomBytes(6).toString("hex")}`;
	return { root, name, env: isolatedEnv(process.env, root, name) };
}

function requireVersion(version: string, program: string, patch: number) {
	const match = version.match(new RegExp(`^${program} 0\\.1\\.(\\d+)$`));
	if (!match || Number(match[1]) < patch) throw new Error(`Expected ${program} 0.1.${patch}+ in the 0.1 series; found ${version || "no version"}.`);
}

interface Check { name: string; ok: boolean; detail: string }
interface Programs { app?: string; core: string; git: string; piEntry: string }

export function describeChecks(checks: Check[]) {
	return checks.map(({ name, ok, detail }) => `${ok ? "OK" : "FAIL"} ${name}: ${detail}`).join("\n");
}

export async function doctor({ cwd, piEntry = process.argv[1], signal, appMode = "required", split = false }: {
	cwd: string; piEntry?: string; signal?: AbortSignal; appMode?: "required" | "optional" | "off"; split?: boolean;
}): Promise<{ checks: Check[]; programs?: Programs }> {
	signal?.throwIfAborted();
	const { root, env } = await privateScope("hlab-doctor-");
	const checks: Check[] = [];
	const probe = (file: string, args: string[], dir = root) => cli(file, dir, env, signal)(args, 5_000);
	const check = async <T>(name: string, action: () => Promise<{ value: T; detail: string }>) => {
		try {
			signal?.throwIfAborted();
			const { value, detail } = await action();
			checks.push({ name, ok: true, detail });
			return value;
		} catch (error) {
			signal?.throwIfAborted();
			checks.push({ name, ok: false, detail: error instanceof Error ? error.message : String(error) });
			return undefined;
		}
	};
	try {
		// These queries never connect to an app window or to a core.
		const optionalApp = appMode === "optional" ? await executable("herdr-app").catch(() => undefined) : undefined;
		const usingApp = appMode === "required" || !!optionalApp;
		const app = !usingApp ? undefined : await check("Herdr app", async () => {
			const value = optionalApp ?? await executable("herdr-app");
			const version = (await probe(value, ["--version"])).trim();
			requireVersion(version, "herdr-app", 16);
			return { value, detail: `${version} (${value})` };
		});
		if (usingApp) await check("Herdr app CLI", async () => {
			if (!app) throw new Error("Herdr app binary check did not pass.");
			const help = await probe(app, ["--help"]);
			const commands: Array<{ name: string }> = JSON.parse(await probe(app, ["commands"]));
			const missingCli = ["status", "ls", "check", "shot", "do"].filter(command => !new RegExp(`^\\s*herdr-app ${command}\\b`, "m").test(help));
			const missingCommands = ["layout.clone", "space.rename", "tab.rename", "pane.focus", "window.close", ...(split ? ["pane.split"] : [])].filter(command => !commands.some(item => item.name === command));
			const missing = [...missingCli, ...missingCommands];
			if (missing.length) throw new Error(`Missing ${missing.join(", ")}.`);
			return { value: true, detail: "window control, mod check, and screenshot commands available" };
		});
		const core = await check("Herdr core CLI", async () => {
			const value = await executable("hc");
			const version = (await probe(value, ["--version"])).trim();
			requireVersion(version, "hc", 22);
			const help = await probe(value, ["--help"]);
			const missing = ["run", "send", "keys", "read", "server"].filter(command => !new RegExp(`^\\s+${command}\\s`, "m").test(help));
			if (missing.length) throw new Error(`Missing ${missing.join(", ")}.`);
			if (windows) await access(join(dirname(value), "conpty", "conpty.dll"));
			return { value, detail: `${version} (${value})` };
		});
		const pi = await check("Pi CLI", async () => {
			if (!piEntry || !isAbsolute(piEntry)) throw new Error("Could not locate the running Pi CLI.");
			await access(piEntry);
			const piCli = cli(process.execPath, root, env, signal);
			const version = (await piCli([piEntry, "--version"], 20_000)).trim();
			const help = await piCli([piEntry, "--help"], 20_000);
			if (!/^\d+\.\d+\.\d+\S*$/.test(version) || !["--no-extensions", "--no-approve", "--session-dir", "--offline", "--no-tools"].every(flag => help.includes(flag))) {
				throw new Error("Expected the Pi CLI with isolated-launch options (Pi 1.6+).");
			}
			return { value: piEntry, detail: `Pi ${version} (${piEntry})` };
		});
		const git = await check("Git project", async () => {
			const value = await executable("git");
			const version = (await probe(value, ["--version"])).trim();
			await probe(value, ["rev-parse", "--verify", "HEAD^{commit}"], cwd);
			return { value, detail: `${version}; a committed HEAD is available` };
		});
		return { checks, programs: (!usingApp || app) && core && pi && git && checks.every(c => c.ok) ? { app, core, git, piEntry: pi } : undefined };
	} finally {
		await rm(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
	}
}
