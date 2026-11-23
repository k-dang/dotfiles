import { createHash } from "node:crypto";
import { lstat, open, realpath } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { stripVTControlCharacters } from "node:util";

export const DATA_LIMIT = 64 * 1024;
export const THINKING = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];
export const MOD = "pi-project-widget";
const missing = (error) => error.code === "ENOENT";
const reserved = /^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(?:\.|$)/i;

export function widgetName(name) {
  if (typeof name !== "string" || !/^[a-z0-9][a-z0-9-]{0,39}$/.test(name) || reserved.test(name)) {
    throw new Error("Use a widget name of 1–40 lowercase letters, digits, or hyphens, starting with a letter or digit.");
  }
  return name;
}

export function modelParts(value) {
  const match = typeof value === "string" && /^([\w.-]+)\/(\S+)$/.exec(value);
  if (!match) throw new Error("Use a fully qualified Pi model: provider/model-id.");
  return [match[1], match[2]];
}

function pathParts(value) {
  const parts = typeof value === "string" ? value.split(/[\\/]/) : [];
  if (!parts.length || parts.some((part) => !part || reserved.test(part) || /[:*?"<>|\p{Cc}]|[. ]$/u.test(part))) {
    throw new Error("Use a project-relative file path without '..'.");
  }
  return parts;
}

// Resolve through the real parent, and don't follow a link at the final component.
export async function projectFile(root, value, allowNew = false) {
  const parts = pathParts(value);
  const path = join(root, ...parts);
  const parent = await realpath(dirname(path));
  const rel = relative(await realpath(root), parent);
  if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) throw new Error("The file is outside this project.");
  const target = resolve(parent, parts.at(-1));
  const info = await lstat(target).catch((error) => {
    if (allowNew && missing(error)) return null;
    throw error;
  });
  if (info && !info.isFile()) throw new Error("Use a regular file, not a link or directory.");
  return target;
}

export function parseSource(text) {
  if (text.startsWith("file:")) return { file: pathParts(text.slice(5).trim()).join("/") };
  let argv;
  try { argv = JSON.parse(text); } catch { /* Report the expected format below. */ }
  if (!Array.isArray(argv) || !argv.length || argv.length > 64 || argv.some((arg) => typeof arg !== "string" || arg.length > 2048 || arg.includes("\0")) || !argv[0].trim()) {
    throw new Error('Use file:relative/path or a JSON command array like ["git","--no-optional-locks","status","--short"].');
  }
  return { argv };
}

export function parseAction(text) {
  if (text === "view" || text === "send") return { kind: text };
  if (text.startsWith("append:")) {
    const file = pathParts(text.slice(7).trim()).join("/");
    if (!/\.(md|txt)$/i.test(file)) throw new Error("Append accepts project-relative .md or .txt files only.");
    return { kind: "append", file };
  }
  throw new Error("Use view, send, or append:notes.md.");
}

export function parseRefresh(text) {
  if (text === "manual") return 0;
  const seconds = Number(text);
  if (!/^\d+$/.test(text) || seconds < 15 || seconds > 86400) throw new Error("Use manual or an interval of 15–86400 seconds.");
  return seconds;
}

export function sourceText(source) {
  return source.file ? `file:${source.file}` : JSON.stringify(source.argv);
}

export function actionText(action) {
  return action.kind === "append" ? `append:${action.file}` : action.kind;
}

export function parseSettings(text) {
  const raw = JSON.parse(text);
  if (raw?.version !== 1) throw new Error("Expected widget settings version 1.");
  modelParts(raw.model);
  if (!THINKING.includes(raw.thinking)) throw new Error("Invalid thinking level.");
  return {
    version: 1,
    source: parseSource(sourceText(raw.source)),
    model: raw.model,
    thinking: raw.thinking,
    action: parseAction(actionText(raw.action)),
    refreshSeconds: parseRefresh(raw.refreshSeconds === 0 ? "manual" : String(raw.refreshSeconds)),
  };
}

export async function loadDefinition(root, name) {
  const dir = `widgets/${widgetName(name)}`;
  const [settings, instructions] = await Promise.all(["settings.json", "instructions.md"].map(async (file) => {
    const path = await projectFile(root, `${dir}/${file}`);
    return boundedText(path, 16 * 1024);
  }));
  if (!instructions.trim()) throw new Error("instructions.md is empty.");
  const revision = createHash("sha256").update(JSON.stringify([settings, instructions])).digest("hex");
  return { settings: parseSettings(settings), instructions, revision };
}

export async function boundedText(path, limit = DATA_LIMIT) {
  const file = await open(path, "r");
  try {
    const buffer = Buffer.alloc(limit + 1);
    let offset = 0;
    while (offset <= limit) {
      const { bytesRead } = await file.read(buffer, offset, buffer.length - offset, null);
      if (!bytesRead) return buffer.subarray(0, offset).toString("utf8");
      offset += bytesRead;
    }
    throw new Error(`File exceeds the ${limit / 1024} KiB limit.`);
  } finally {
    await file.close();
  }
}

export function samplePath(name) {
  return `widgets/${widgetName(name)}/sample.txt`;
}

export function cleanText(value) {
  return stripVTControlCharacters(value).replace(/[^\S\n\t]+/gu, " ").replace(/[^\P{Cc}\n\t]/gu, "").trim();
}

export function parseItems(text) {
  const json = text.trim().replace(/^```(?:json)?\s*\n([\s\S]*?)\n```$/i, "$1");
  const result = JSON.parse(json);
  if (!Array.isArray(result?.items) || result.items.length > 20) throw new Error("The model did not return a list of up to 20 items.");
  return result.items.map((item) => {
    if (typeof item?.title !== "string" || typeof item.detail !== "string") throw new Error("The model returned an invalid item.");
    const title = cleanText(item.title).replace(/\s+/gu, " ");
    const detail = cleanText(item.detail);
    if (!title || !detail || title.length > 160 || detail.length > 3000) throw new Error("A model item is empty or exceeds its length limit.");
    return { title, detail };
  });
}
