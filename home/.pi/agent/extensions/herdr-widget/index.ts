import { mkdir, readdir, realpath, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { getAgentDir, getPackageDir, type ExtensionAPI, type ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { getSupportedThinkingLevels } from "@earendil-works/pi-ai/models";
import { actionText, loadDefinition, modelParts, parseAction, parseRefresh, parseSource, projectFile, samplePath, sourceText, widgetName } from "./definition.mjs";
import { findMain, installMod, runtimeKey, WidgetPanes, type WidgetSpec } from "./herdr.ts";

const HELP = `Project widgets — a native Herdr panel beside the Pi that opens it (Main).

/widget                       List saved widgets in this project.
/widget new <name>             Describe and save a widget; does not open it.
/widget open <name>            Open or focus a widget with its live source.
/widget open <name> --sample   Use widgets/<name>/sample.txt on every refresh.
/widget close <name>           Close the panel; keep its saved definition.
/widget help                   Show this guide.

Setup: describe the widget in prose. Optionally supply any of these lines to skip questions:
  source: ["git","--no-optional-locks","status","--short"]
  judge: Show files that need review and say why.
  model: provider/model-id
  thinking: off
  action: view
  refresh: manual

Source: file:relative/path or a JSON array [executable, ...args], run from the project root without a shell. To use MCP, point it at a script or CLI that makes a fixed read-only MCP call and prints the result. Approve only trusted, read-only collectors. Output/sample limit: 64 KiB. The gathered text goes to the configured Pi model, never to Main. Use a standalone Pi model (built-in or models.json); extension-only/virtual models are not supported.

Actions: view (details only), send (submit to the original idle Main), or append:notes.md (append to a project-relative .md/.txt file). Send/append need an explicit item selection and confirmation. No model output becomes a command or chooses a file.

Refresh: manual, or 15–86400 seconds (even if the pane isn't visible). Open gathers once. Focus the panel: ↑/↓ select, D details, Enter view/review, Y confirm, Esc cancel, R refresh now. Click controls also work. A refresh during work queues one more. Save your own sample.txt and reopen with --sample to bypass the collector; this fixes the input, not the model's output.

Files: widgets/<name>/settings.json and instructions.md. Edit them and reopen to approve changes. No widget command or refresh creates a Main turn; only a confirmed Send to Main does.`;

const tasks = ["new", "open", "close", "help"];
const fields = ["source", "judge", "model", "thinking", "action", "refresh"] as const;
type Field = typeof fields[number];
const canceled = Symbol("canceled");
const errorMessage = (error: unknown) => error instanceof Error ? error.message : String(error);

async function projectRoot(pi: ExtensionAPI, cwd: string) {
  const git = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd, timeout: 4000 }).catch(() => null);
  return realpath(git?.code === 0 && git.stdout.trim() ? git.stdout.trim() : cwd);
}

function descriptionFields(text: string) {
  const supplied: Partial<Record<Field, string>> = {};
  const description: string[] = [];
  for (const line of text.split(/\r?\n/)) {
    const field = /^\s*(source|judge|model|thinking|action|refresh):\s*(.*)$/i.exec(line);
    if (field) supplied[field[1].toLowerCase() as Field] = field[2].trim();
    else description.push(line);
  }
  return { supplied, description: description.join("\n").trim() };
}

async function answer<T>(ctx: ExtensionCommandContext, question: string, suggestion: string, validate: (text: string) => T, given?: string): Promise<T> {
  let value = given || undefined;
  for (;;) {
    if (value !== undefined) {
      try { return validate(value); }
      catch (error) { ctx.ui.notify(errorMessage(error), "warning"); }
    }
    const use = `Use suggested: ${suggestion.replace(/\s+/gu, " ").slice(0, 180)}`;
    const choice = await ctx.ui.select(question, [use, "Enter a different answer"]);
    if (choice === undefined) throw canceled;
    value = choice === use ? suggestion : await ctx.ui.input(question, suggestion);
    if (value === undefined) throw canceled;
    value = value.trim();
  }
}

function describeModel(ctx: ExtensionCommandContext, text: string) {
  const model = ctx.modelRegistry.find(...modelParts(text) as [string, string]);
  if (!model) throw new Error(`Pi does not know ${text}. Check /model for the provider and ID.`);
  return model;
}

const fastPatterns = [/nano/i, /haiku/i, /flash/i, /mini/i, /\b(?:small|lite)\b/i];
function suggestedModel(ctx: ExtensionCommandContext) {
  const models = ctx.modelRegistry.getAvailable();
  for (const pattern of fastPatterns) {
    const fast = models.find(model => pattern.test(model.id));
    if (fast) return `${fast.provider}/${fast.id}`;
  }
  // A concrete example, not a silent fallback to Main's larger model.
  return "openai/gpt-4.1-mini";
}

async function create(ctx: ExtensionCommandContext, root: string, name: string, inline: string) {
  const widgets = join(root, "widgets");
  const dir = join(widgets, name);
  if (await stat(dir).then(() => true, error => { if (error.code === "ENOENT") return false; throw error; })) {
    throw new Error(`Widget ${name} already exists; edit widgets/${name}/ to change it.`);
  }
  const text = inline || await ctx.ui.editor(`Describe ${name} (optional source:, judge:, model:, thinking:, action:, refresh: lines)`);
  if (text === undefined) throw canceled;
  if (!text.trim()) throw new Error("Describe what the widget should show.");
  const { supplied, description } = descriptionFields(text);
  const source = await answer(ctx, "Where does the data come from? Use file:path or a read-only JSON command array.",
    '["git","--no-optional-locks","status","--short"]', parseSource, supplied.source);
  const instructions = await answer(ctx, "What should the model judge or filter for?", description || "Show the highest-priority items and explain the evidence for each.", value => {
    if (!value || Buffer.byteLength(value) >= 16 * 1024) throw new Error("Provide judging instructions under 16 KiB.");
    return value;
  }, supplied.judge);
  const model = await answer(ctx, "Which Pi model? Use provider/model-id. A small, fast model is suggested.",
    suggestedModel(ctx), value => describeModel(ctx, value), supplied.model);
  const levels = getSupportedThinkingLevels(model);
  const thinking = levels.length > 1 ? await answer(ctx, `Thinking level (${levels.join(", ")})?`, levels.includes("off") ? "off" : levels[0], value => {
    if (!levels.some(level => level === value)) throw new Error(`Choose ${levels.join(", ")}.`);
    return value;
  }, supplied.thinking) : levels[0] ?? "off";
  const action = await answer(ctx, "What can you do with each item? view, send (to Main), or append:notes.md.", "view", parseAction, supplied.action);
  const refreshSeconds = await answer(ctx, "How often should it refresh? manual, or seconds (15–86400).", "manual", parseRefresh, supplied.refresh);
  const settings = JSON.stringify({ version: 1, source, model: `${model.provider}/${model.id}`, thinking, action, refreshSeconds }, null, 2) + "\n";
  if (Buffer.byteLength(settings) > 16 * 1024) throw new Error("Settings exceed 16 KiB. Put long collectors in a script and reference the script instead.");
  await mkdir(widgets, { recursive: true });
  if (await realpath(widgets) !== widgets) throw new Error("The widgets directory must not be a link.");
  await mkdir(dir);
  try {
    await writeFile(join(dir, "instructions.md"), `${instructions}\n`, { flag: "wx" });
    await writeFile(join(dir, "settings.json"), settings, { flag: "wx" });
  } catch (error) {
    await rm(dir, { recursive: true, force: true });
    throw error;
  }
  ctx.ui.notify(`Saved widgets/${name}/. Use /widget open ${name} when ready.`, "info");
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("widget", {
    description: "Create, open, or close a native Herdr widget; /widget help for the guide",
    getArgumentCompletions: prefix => {
      if (!prefix || /\s/u.test(prefix)) return null;
      const choices = tasks.filter(task => task !== prefix && task.startsWith(prefix));
      return choices.length ? choices.map(task => ({ value: task, label: task })) : null;
    },
    handler: async (args, ctx) => {
      try {
        const [command, rawName, ...rest] = args.trim() ? args.trim().split(/\s+/u) : [];
        if (command === "help" || command === "--help") { ctx.ui.notify(HELP, "info"); return; }
        if (!tasks.includes(command) && command !== undefined) throw new Error("Use /widget help for usage.");
        const root = await projectRoot(pi, ctx.cwd);
        if (!command) {
          const folders = await readdir(join(root, "widgets"), { withFileTypes: true }).catch(error => {
            if (error.code === "ENOENT") return [];
            throw error;
          });
          const names = (await Promise.all(folders.filter(e => e.isDirectory()).map(async ({ name }) => {
            try { await loadDefinition(root, name); return name; } catch { return null; }
          }))).filter(Boolean).sort();
          ctx.ui.notify(names.length ? `Saved widgets:\n${names.map(name => `  ${name}`).join("\n")}` : "No saved widgets. Try /widget new <name>.", "info");
          return;
        }
        if (ctx.mode !== "tui") throw new Error("This command requires interactive Pi.");
        const name = widgetName(rawName);
        if (command === "new") { await create(ctx, root, name, args.trim().replace(/^new\s+\S+\s*/u, "")); return; }
        const sample = command === "open" && rest.length === 1 && rest[0] === "--sample";
        if (rest.length && !sample) throw new Error("Use /widget open <name> [--sample] or /widget close <name>.");
        const main = await findMain(pi, ctx.cwd);
        const panes = new WidgetPanes(pi, main, root);
        if (command === "close") {
          ctx.ui.notify(await panes.close(name) ? `Closed ${name}.` : `${name} is not open beside this Main.`, "info");
          return;
        }
        const { settings, revision } = await loadDefinition(root, name);
        const sdk = join(getPackageDir(), "dist", "index.js");
        await stat(sdk).catch(() => { throw new Error("The widget worker requires the Node/npm build of Pi with its SDK installed."); });
        const spec: WidgetSpec = {
          root, name, sample, revision, main, sdk, agentDir: getAgentDir(), node: process.execPath,
          worker: join(__dirname, "worker.mjs"), refreshSeconds: settings.refreshSeconds, action: settings.action,
        };
        const mod = join(__dirname, "mod");
        const open = (await panes.entries())[name];
        if (open?.revision === revision && open.sample === sample && open.pid === main.pid && open.runtime === runtimeKey(spec)) {
          await installMod(pi, mod);
          if (await panes.focus(open.pane)) return;
        }
        if (sample) await projectFile(root, samplePath(name));
        const source = sample ? `file:${samplePath(name)} (no collector will run)` : sourceText(settings.source);
        const schedule = settings.refreshSeconds ? `every ${settings.refreshSeconds}s` : "on open and on demand";
        const approved = await ctx.ui.confirm(`Open ${name}?`, `Read ${source}\nSend the gathered text to ${settings.model} (${settings.thinking}), ${schedule}.\nItem action after confirmation: ${actionText(settings.action)}. Only open sources you trust to be read-only.`);
        if (!approved) return;
        await installMod(pi, mod);
        await panes.open(name, spec);
        ctx.ui.notify(`Opened ${name}${sample ? " (sample)" : ""}.`, "info");
      } catch (error) {
        if (error !== canceled) ctx.ui.notify(`/widget: ${errorMessage(error)}`, "error");
      }
    },
  });
}
