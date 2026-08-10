import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Rgb = [number, number, number];

const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";

// Catppuccin Mocha accents: mauve → pink → rosewater → peach → yellow → green → teal → sky → blue → lavender.
const PALETTE: Rgb[] = [
	[203, 166, 247],
	[245, 194, 231],
	[245, 224, 220],
	[250, 179, 135],
	[249, 226, 175],
	[166, 227, 161],
	[148, 226, 213],
	[137, 220, 235],
	[137, 180, 250],
	[180, 190, 254],
];

const TITLE_LINES = [
	"  ██████╗  ██╗ ",
	"  ██╔══██╗ ██║ ",
	"  ██████╔╝ ██║ ",
	"  ██╔═══╝  ██║ ",
	"  ██║      ██║ ",
	"  ╚═╝      ╚═╝ ",
];

function mix(a: number, b: number, t: number) {
	return Math.round(a + (b - a) * t);
}

function sampleGradient(position: number): Rgb {
	const wrapped = ((position % 1) + 1) % 1;
	const scaled = wrapped * PALETTE.length;
	const index = Math.floor(scaled);
	const nextIndex = (index + 1) % PALETTE.length;
	const t = scaled - index;
	const a = PALETTE[index]!;
	const b = PALETTE[nextIndex]!;
	return [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
}

function fg([r, g, b]: Rgb, text: string) {
	return `\x1b[38;2;${r};${g};${b}m${text}${RESET}`;
}

function gradientText(text: string, phase: number) {
	const chars = [...text];
	const span = Math.max(chars.length - 1, 1);
	return chars
		.map((char, index) => (char === " " ? char : fg(sampleGradient(index / span + phase), char)))
		.join("");
}

function center(text: string, width: number) {
	const length = [...text].length;
	if (length >= width) return text;
	return `${" ".repeat(Math.floor((width - length) / 2))}${text}`;
}

function renderHeader(width: number, phase: number, subtitle: string) {
	return [
		"",
		...TITLE_LINES.map((line, row) => gradientText(center(line, width), phase + row * 0.045)),
		`${BOLD}${gradientText(center(subtitle, width), phase + 0.18)}${RESET}`,
		"",
	];
}

export default function (pi: ExtensionAPI) {
	let cwdName = path.basename(process.cwd()) || "session";
	let modelId = "no model selected";
	const phase = 0.08;
	let busy = false;

	function sessionName() {
		return pi.getSessionName?.() || cwdName;
	}

	function terminalTitle() {
		const prefix = busy ? "working · " : "";
		return `${prefix}π · ${sessionName()} · ${cwdName} · ${modelId}`;
	}

	function installHeader(ctx: ExtensionContext) {
		cwdName = path.basename(ctx.cwd) || cwdName;
		modelId = ctx.model?.id ?? modelId;
		ctx.ui.setHeader((_tui) => {
			return {
				render(width: number) {
					const state = busy ? "working" : "ready";
					return renderHeader(width, phase, `${modelId} · ${cwdName} · ${state}`);
				},
				invalidate() {},
			};
		});
		ctx.ui.setTitle(terminalTitle());
	}

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		installHeader(ctx);
	});

	pi.on("model_select", (event, ctx) => {
		modelId = event.model.id;
		if (ctx.hasUI) installHeader(ctx);
	});

	pi.on("agent_start", (_event, ctx) => {
		busy = true;
		if (ctx.hasUI) installHeader(ctx);
	});

	pi.on("agent_end", (_event, ctx) => {
		busy = false;
		if (ctx.hasUI) installHeader(ctx);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		if (ctx.hasUI) {
			ctx.ui.setHeader(undefined);
			ctx.ui.setTitle(`π · ${cwdName}`);
		}
	});

	pi.registerCommand("flow-title", {
		description: "Enable the static Catppuccin Mocha Pi session header/title",
		handler: async (_args, ctx) => {
			installHeader(ctx);
			ctx.ui.notify("Flow title enabled", "info");
		},
	});

	pi.registerCommand("flow-title-builtin", {
		description: "Restore Pi's built-in header for this session",
		handler: async (_args, ctx) => {
			ctx.ui.setHeader(undefined);
			ctx.ui.setTitle(`π · ${cwdName}`);
			ctx.ui.notify("Built-in header restored", "info");
		},
	});
}
