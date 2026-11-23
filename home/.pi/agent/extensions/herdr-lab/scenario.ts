export type Step =
	| { send: string; pane?: number }
	| { keys: string[]; pane?: number }
	| { expect: string; pane?: number }
	| { shot: true; pane?: number };

export interface Scenario {
	panes: number;
	modelTurns: boolean;
	model?: string;
	extensions?: string[];
	steps: Step[];
}

export const smoke: Scenario = {
	panes: 1,
	modelTurns: false,
	steps: [
		{ send: "/lab-probe alpha" },
		{ expect: "Lab probe received: alpha" },
		{ keys: ["/", "l", "a", "b", "-"] },
		{ expect: "Echo text locally" },
		{ shot: true },
		{ keys: ["escape", "ctrl+u"] },
	],
};

export function parseScenario(json: string): Scenario {
	const value: unknown = JSON.parse(json);
	if (!record(value) || Object.keys(value).some((key) => !["panes", "modelTurns", "model", "extensions", "steps"].includes(key))) {
		throw new Error("Expected a scenario object with steps, and optionally panes, modelTurns, model, and extensions.");
	}
	const panes = "panes" in value ? value.panes : 1;
	const modelTurns = "modelTurns" in value ? value.modelTurns : false;
	const model = value.model;
	if ("model" in value && (!line(model, 240) || !/^[\w.-]+\/[a-z\d][\w.:/@+-]*$/i.test(model) || model.startsWith("-"))) {
		throw new Error('Use a full "provider/model-id" for model.');
	}
	const extensions = value.extensions;
	if ("extensions" in value && (!Array.isArray(extensions) || extensions.length > 8 || !extensions.every(extensionSource) || new Set(extensions).size !== extensions.length)) {
		throw new Error('Use up to eight distinct extension sources: a path relative to the repo root or "installed:NAME".');
	}
	if (typeof panes !== "number" || ![1, 2].includes(panes) || typeof modelTurns !== "boolean" ||
		!Array.isArray(value.steps) || value.steps.length < 1 || value.steps.length > 30) {
		throw new Error("Use 1–2 panes, a boolean modelTurns, and 1–30 steps.");
	}
	const steps = value.steps.map((step: unknown, i): Step => {
		if (record(step)) {
			const pane = "pane" in step ? step.pane : 1;
			const actions = Object.keys(step).filter((key) => key !== "pane");
			if (typeof pane === "number" && Number.isInteger(pane) && pane >= 1 && pane <= panes && actions.length === 1) {
				const [action] = actions;
				if (action === "send" && line(step.send, 2000)) return { send: step.send, pane };
				if (action === "keys" && Array.isArray(step.keys) && step.keys.length >= 1 && step.keys.length <= 50 &&
					step.keys.every((key) => line(key, 40) && !key.startsWith("--"))) return { keys: step.keys, pane };
				if (action === "expect" && line(step.expect, 300)) return { expect: step.expect, pane };
				if (action === "shot" && step.shot === true) return { shot: true, pane };
			}
		}
		throw new Error(`Step ${i + 1}: use one of send, keys, expect, or shot, and an optional pane number.`);
	});
	return { panes, modelTurns, steps, ...(typeof model === "string" ? { model } : {}), ...(Array.isArray(extensions) ? { extensions } : {}) };
}

export function extensionSource(value: unknown): value is string {
	if (!line(value, 240) || value !== value.trim()) return false;
	if (value.startsWith("installed:")) return /^installed:[a-z\d][\w.-]*$/i.test(value);
	return !/[:<>"|?*]/.test(value) && value.split(/[\\/]/).every(part => part && part !== "." && part !== "..");
}

function record(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function line(value: unknown, max: number): value is string {
	return typeof value === "string" && value.length <= max && !!value.trim() && !/[\p{Cc}]/u.test(value);
}
