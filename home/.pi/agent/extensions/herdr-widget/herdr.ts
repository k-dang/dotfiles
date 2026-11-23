import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, realpath, rename, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { MOD } from "./definition.mjs";

const appHome = () => resolve(process.env.HERDR_APP_HOME || join(homedir(), ".config", "herdr-app"));
const missing = (error: unknown) => (error as NodeJS.ErrnoException).code === "ENOENT";

async function cli<T>(pi: ExtensionAPI, bin: string, args: string[], timeout = 8000): Promise<T> {
  const result = await pi.exec(bin, args, { timeout, maxBuffer: 4 * 1024 * 1024 });
  if (result.code !== 0) {
    let error: string | undefined;
    try { error = JSON.parse(result.stdout).error; } catch { /* Not every CLI error uses JSON. */ }
    throw new Error(error ?? (result.stderr.trim() || result.stdout.trim() || `${bin} exited ${result.code}`));
  }
  return JSON.parse(result.stdout) as T;
}

export interface MainPane { pane: string; terminal: string; pid: number }

export async function findMain(pi: ExtensionAPI, cwd: string): Promise<MainPane> {
  const terminal = process.env.HC_TERMINAL_ID;
  if (!terminal || !/^t[0-9a-z]+$/.test(terminal)) throw new Error("Run this from the Main Pi terminal inside local Herdr.");
  const [app, core] = await Promise.all([
    cli<{ spaces: Array<{ machine: string | null; id: string; tabs: Array<{ id: string; terminals: Array<{ terminal: string; pane?: string }> }> }> }>(pi, "herdr-app", ["ls"]),
    cli<{ state: string; address: string; cwd: string; labels: Record<string, string>; foreground?: { pid: number } }>(pi, "hc", ["get", terminal, "--json"]),
  ]);
  const matches = app.spaces.filter(s => s.machine === null && s.id === core.labels["herdr.space"])
    .flatMap(s => s.tabs.filter(t => t.id === core.labels["herdr.tab"]).flatMap(t => t.terminals))
    .filter(t => t.terminal === terminal && t.pane);
  if (core.state !== "live" || core.address !== terminal || matches.length !== 1 || !matches[0]?.pane) {
    throw new Error("Could not identify your Main pane without guessing from focus.");
  }
  if (await realpath(core.cwd) !== await realpath(cwd)) throw new Error("Main's terminal is in a different directory from this Pi session.");
  return { pane: matches[0].pane, terminal, pid: core.foreground?.pid ?? 0 };
}

async function atomicWrite(file: string, body: string) {
  const temp = `${file}.${randomUUID()}.tmp`;
  await writeFile(temp, body, { flag: "wx", mode: 0o600 });
  try { await rename(temp, file); }
  finally { await rm(temp, { force: true }); }
}

export async function installMod(pi: ExtensionAPI, source: string) {
  const home = appHome();
  const destination = join(home, "mods", MOD);
  const marker = ".pi-widget-managed";
  const files = ["main.js", "mod.json"];
  const bodies = await Promise.all(files.map(file => readFile(join(source, file), "utf8")));
  const matches = await Promise.all(files.map(async (file, i) =>
    (await readFile(join(destination, file), "utf8").catch(error => { if (!missing(error)) throw error; })) === bodies[i]));
  if (matches.every(Boolean)) return;

  const stage = join(home, `.widget-check-${randomUUID()}`);
  await mkdir(stage);
  try {
    await Promise.all(files.map((file, i) => writeFile(join(stage, file), bodies[i])));
    await writeFile(join(stage, marker), "Managed by the Pi /widget extension.\n");
    const check = await pi.exec("herdr-app", ["check", stage], { timeout: 20_000 });
    if (check.code !== 0) throw new Error(`Herdr mod check failed: ${check.stderr.trim() || check.stdout.trim()}`);
    try { await rename(stage, destination); }
    catch (error) {
      if (!(await readFile(join(destination, marker), "utf8").catch(() => undefined))) throw error;
      await Promise.all(files.map((file, i) => atomicWrite(join(destination, file), bodies[i])));
    }
  } finally { await rm(stage, { recursive: true, force: true }); }
}

export interface WidgetSpec {
  root: string;
  name: string;
  sample: boolean;
  revision: string;
  main: MainPane;
  sdk: string;
  agentDir: string;
  node: string;
  worker: string;
  refreshSeconds: number;
  action: { kind: string; file?: string };
}

interface OpenWidget { pane: string; sample: boolean; revision: string; pid: number; runtime: string }
export const runtimeKey = (spec: WidgetSpec) => JSON.stringify([spec.sdk, spec.agentDir, spec.node, spec.worker]);

export class WidgetPanes {
  private readonly file: string;
  constructor(private readonly pi: ExtensionAPI, private readonly main: MainPane, root: string) {
    const id = createHash("sha256").update(JSON.stringify([root, main.pane])).digest("hex");
    this.file = join(appHome(), "data", MOD, `${id}.json`);
  }

  async entries(): Promise<Record<string, OpenWidget>> {
    return JSON.parse(await readFile(this.file, "utf8").catch(error => { if (!missing(error)) throw error; return "{}"; }));
  }

  private async save(entries: Record<string, OpenWidget>) {
    await mkdir(dirname(this.file), { recursive: true, mode: 0o700 });
    await atomicWrite(this.file, JSON.stringify(entries));
  }

  async focus(pane: string) {
    try { await cli(this.pi, "herdr-app", ["do", "pane.focus", "--pane", pane]); return true; }
    catch (error) { if ((error as Error).message === "no such pane") return false; throw error; }
  }

  private async closePane(pane: string) {
    try { await cli(this.pi, "herdr-app", ["do", "pane.close", "--pane", pane]); return true; }
    catch (error) { if ((error as Error).message === `no pane ${JSON.stringify(pane)}`) return false; throw error; }
  }

  async close(name: string) {
    const entries = await this.entries();
    if (!Object.hasOwn(entries, name)) return false;
    const closed = await this.closePane(entries[name].pane);
    delete entries[name];
    await this.save(entries);
    return closed;
  }

  async open(name: string, props: WidgetSpec) {
    const entries = await this.entries();
    if (Object.hasOwn(entries, name)) {
      await this.closePane(entries[name].pane);
      delete entries[name];
    }
    const split = async (pane: string, direction: string) => {
      const args = ["do", "pane.split", JSON.stringify({ pane, direction, mod: MOD, props })];
      for (let retries = 5;; retries--) {
        try { return await cli<{ pane: string }>(this.pi, "herdr-app", args); }
        catch (error) {
          // Herdr may still be discovering the mod we just installed.
          if (!retries || (error as Error).message !== `no mod ${JSON.stringify(MOD)} in mods/`) throw error;
          await delay(350);
        }
      }
    };
    let opened: { pane: string } | undefined;
    for (const [id, entry] of Object.entries(entries).reverse()) {
      try { opened = await split(entry.pane, "down"); break; }
      catch (error) {
        if ((error as Error).message !== `no pane ${JSON.stringify(entry.pane)}`) throw error;
        delete entries[id];
      }
    }
    opened ??= await split(this.main.pane, "right");
    entries[name] = { pane: opened.pane, sample: props.sample, revision: props.revision, pid: this.main.pid, runtime: runtimeKey(props) };
    try { await this.save(entries); }
    catch (error) { await this.closePane(opened.pane); throw error; }
  }
}
