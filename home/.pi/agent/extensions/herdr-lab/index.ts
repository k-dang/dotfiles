import { open } from "node:fs/promises";
import { resolve } from "node:path";
import { getAgentDir, type ExtensionAPI, type ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { agentFiles, loadAgentSpec, parseTestCommand } from "./agent-spec.ts";
import { createJudge } from "./agent-test.ts";
import { authorTest } from "./author-test.ts";
import { describeChecks, doctor } from "./runtime.ts";
import { runLab } from "./runner.ts";
import { parseScenario, smoke } from "./scenario.ts";

const HELP = `Usage: /lab [doctor | run <smoke | file PATH | DESCRIPTION> | test NAME [OPTIONS] | new NAME [OPTIONS] | stop | --help]

Examples:
  /lab doctor                         Check Herdr, hc, Pi, and Git without opening a window.
  /lab run smoke                      Run the local typing and completion smoke test.
  /lab run file scenarios.json        Replay a JSON scenario (paths may contain spaces).
  /lab run Type /lab- and capture the completion menu
                                      Draft steps using the current model; review before running.
  /lab test reviewer                 Test a saved Job against agents/reviewer/expectations.md.
  /lab new reviewer                  Draft expectations, ask for approval, write the Job, and test it.
  /lab stop                           Cancel this Pi session's run and clean up the lab.
  /lab --help                         Print this guide. Bare /lab also shows examples.

Scenario example: {"steps":[{"send":"/lab-probe hello"},{"expect":"Lab probe received: hello"},{"keys":["escape"]},{"shot":true}]}
The guest inherits the launching Pi's model. In a scenario file, set "model": "provider/model-id" to pin another and "extensions": ["installed:herdr-split"] to approve loading /split. Repo-relative extension paths use committed HEAD. Only approve code you trust.
Use panes: 2 and pane: 2 on a step to drive a second Pi pane. Don't type secrets: reports retain input and screenshots. A description is sent to your current model; lab panes do not make model requests by default.

Test/new options: --agent-model provider/id, --tester-model provider/id, --behind (Windows desktop). The agent defaults to Haiku; the tester defaults to your current model. Named tests run Pi model turns in a private lab; reports stay in agents/NAME/reports/. Outside Windows, named tests run in a detached core without a window.

Every run checks prerequisites, starts a private Herdr core and Pi profile over a copy of HEAD, then saves evidence before cleanup.`;

const HINTS = [
	{ value: "doctor", description: "Check Herdr app, CLI, hc, Pi, and Git without launching" },
	{ value: "run", description: "Use smoke, file PATH, or a plain-English description" },
	{ value: "test", description: "Test a saved agent against its Markdown expectations" },
	{ value: "new", description: "Create and test a saved agent" },
	{ value: "stop", description: "Cancel this session's run and clean up the lab" },
	{ value: "--help", description: "Print usage and examples here without launching" },
];
const RUN_HINTS = [
	{ value: "run smoke", description: "Run the local typing and completion test" },
	{ value: "run file", description: "Add a path to a JSON scenario" },
];

const DRAFT_PROMPT = `Translate the user's description into a Herdr lab scenario. Return only JSON with panes (1 or 2) and steps (1 to 30). Each step has an optional pane number, default 1, and exactly one action:
- "send": a single line that Pi will receive and submit with Enter. Use local Pi commands only, not shell commands, file writes, install, login, or model prompts. "/lab-probe TEXT" displays "Lab probe received: TEXT" without a model turn.
- "keys": an array of individual hc keys, e.g. ["/","l","a","b","-"], ["escape","ctrl+u"], ["enter"]. Use "space" for the space key.
- "expect": literal visible screen text, up to 300 characters. Match resulting output, not echoed input. The /lab- completion includes "Echo text locally".
- "shot": true, to capture the entire window at that point. Normally wait for a visible result with expect before shot.
Do not set modelTurns, model, or extensions. The lab is a fresh Pi, with no project or daily extensions, shell execution, or tools. The only added command is /lab-probe. Do not invent input steps or output the app cannot provide. Return null if the description cannot be run using these actions.`;

async function loadScenario(path: string) {
	const file = await open(path, "r");
	try {
		if (!(await file.stat()).isFile()) throw new Error("Expected a regular JSON scenario file.");
		const buffer = Buffer.alloc(64 * 1024 + 1);
		let length = 0;
		while (length < buffer.length) {
			const { bytesRead } = await file.read(buffer, length, buffer.length - length);
			if (!bytesRead) break;
			length += bytesRead;
		}
		if (length === buffer.length) throw new Error("Scenario files are limited to 64 KiB.");
		return parseScenario(buffer.toString("utf8", 0, length));
	} finally {
		await file.close();
	}
}

async function draftScenario(description: string, ctx: ExtensionCommandContext, signal: AbortSignal) {
	if (!ctx.model) throw new Error("Select a Pi model to draft a scenario, or use /lab run file PATH.");
	if (description.length > 2_000) throw new Error("Describe the scenario in at most 2,000 characters, or use a file.");
	const response = await ctx.modelRegistry.complete(ctx.model, {
		systemPrompt: DRAFT_PROMPT,
		messages: [{ role: "user", content: [{ type: "text", text: description }], timestamp: Date.now() }],
	}, { signal: AbortSignal.any([signal, AbortSignal.timeout(60_000)]), maxTokens: 4096, cacheRetention: "none" });
	signal.throwIfAborted();
	if (response.stopReason !== "stop") throw new Error("Pi could not finish drafting the scenario. Try again or use a JSON file.");
	const text = response.content.flatMap(block => block.type === "text" ? [block.text] : []).join("").trim();
	const json = text.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i)?.[1] ?? text;
	if (json === "null") throw new Error("The description doesn't fit the lab's send, keys, expect, or shot steps.");
	const scenario = parseScenario(json);
	if (scenario.modelTurns || scenario.model || scenario.extensions?.length) {
		throw new Error("Drafts cannot enable model turns, pin a model, or load extensions. Use a trusted JSON file for those options.");
	}
	ctx.ui.notify(`Review the proposed lab steps:\n${JSON.stringify(scenario, null, 2)}`, "info");
	if (await ctx.ui.confirm("Run the proposed lab scenario?", "Run only the steps printed above. Decline to leave the lab closed.", { signal })) return scenario;
}

function errorText(error: unknown) {
	return error instanceof Error ? error.message : String(error);
}

export default function (pi: ExtensionAPI) {
	let active: { abort: AbortController; done: Promise<void> } | undefined;

	pi.on("session_shutdown", async () => {
		const job = active;
		job?.abort.abort();
		await job?.done;
	});

	pi.registerCommand("lab", {
		description: "Check, run, or stop an isolated Herdr lab; /lab --help shows examples",
		getArgumentCompletions: (prefix) => {
			const partial = prefix.trimStart().replace(/\s+/g, " ");
			const hints = partial.startsWith("run ") ? RUN_HINTS : HINTS;
			const matches = hints.filter(item => item.value.startsWith(partial) && item.value !== partial);
			return matches.length ? matches.map(item => ({ ...item, label: item.value })) : null;
		},
		handler: async (args, ctx) => {
			const option = args.trim();
			if (!option || option === "--help" || option === "run") {
				ctx.ui.notify(HELP, "info");
				return;
			}
			if (option === "doctor") {
				try {
					const { checks, programs } = await doctor({ cwd: ctx.cwd });
					ctx.ui.notify(`/lab doctor — ${programs ? "preflight passed" : "preflight failed"}; no window or core started.\n${describeChecks(checks)}`, programs ? "info" : "error");
				} catch (error) {
					ctx.ui.notify(`/lab doctor: ${errorText(error)}`, "error");
				}
				return;
			}
			if (option === "stop") {
				if (!active) ctx.ui.notify("/lab: No run is active in this Pi session.", "info");
				else {
					active.abort.abort();
					ctx.ui.notify("/lab: Stopping. Any lab resources will be cleaned up before another run can start.", "info");
				}
				return;
			}
			const named = /^(?:test|new)(?:\s|$)/.test(option);
			const target = option.match(/^run\s+([\s\S]+)$/)?.[1];
			if (!named && (!target || target.startsWith("-") || target === "file")) {
				ctx.ui.notify("/lab: Run /lab --help for usage and examples.", "error");
				return;
			}
			if (active || ctx.mode !== "tui") {
				ctx.ui.notify(active ? "/lab: A run is already active. Use /lab stop to cancel it." : "/lab: Run scenarios in interactive Pi.", "warning");
				return;
			}
			const abort = new AbortController();
			const file = target?.match(/^file\s+([\s\S]+)$/)?.[1].trim();
			const describing = !!target && target !== "smoke" && !file;
			const defaultModel = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined;
			ctx.ui.setStatus("herdr-lab", "Lab active · /lab stop");
			if (!named) ctx.ui.notify(describing ? "/lab: Drafting a scenario with the current model. No input will be sent without approval." : "/lab: Checking prerequisites before starting. Use /lab stop to cancel.", "info");
			// Return to the editor while the job runs, so /lab stop remains available.
			const done = (async () => {
				try {
					const common = {
						cwd: ctx.cwd, agentDir: getAgentDir(), defaultModel, signal: abort.signal,
						onStep: (step: number, total: number) => ctx.ui.setStatus("herdr-lab", `Lab ${step}/${total} · /lab stop`),
					};
					const report = (result: Awaited<ReturnType<typeof runLab>>) => {
						const outcome = !result.cleanupOk ? "Cleanup incomplete" : result.cancelled ? "Stopped and cleaned up" : result.ok ? "Checks passed" : "Run did not pass";
						ctx.ui.notify(`/lab: ${outcome}. Report: ${result.report}`, result.ok || (result.cancelled && result.cleanupOk) ? "info" : "error");
					};
					if (named) {
						const command = parseTestCommand(option);
						const files = await agentFiles(ctx.cwd, command.name, command.mode === "new");
						if (command.mode === "new" && !await authorTest(command.name, files, ctx, abort.signal)) {
							abort.signal.throwIfAborted();
							ctx.ui.notify("/lab: Cancelled. No job was written and no lab started.", "info");
							return;
						}
						const input = await loadAgentSpec(files);
						const judge = createJudge(ctx, command.testerModel, input.spec);
						abort.signal.throwIfAborted();
						ctx.ui.notify(`/lab: Testing ${command.name}. This run makes model requests. Use /lab stop to cancel.`, "info");
						report(await runLab({ ...common, test: { ...command, ...input, ...judge, reports: await files.reports() } }));
						return;
					}
					const scenario = target === "smoke" ? smoke : file ? await loadScenario(resolve(ctx.cwd, file)) : await draftScenario(target!, ctx, abort.signal);
					abort.signal.throwIfAborted();
					if (!scenario) {
						ctx.ui.notify("/lab: Draft declined. No lab started.", "info");
						return;
					}
					if (scenario.extensions?.length) {
						const approved = await ctx.ui.confirm("Load these trusted Pi extensions?", `${scenario.extensions.join("\n")}\n\nExtensions run with your OS permissions, not in a security sandbox.`, { signal: abort.signal });
						abort.signal.throwIfAborted();
						if (!approved) {
							ctx.ui.notify("/lab: Extension loading declined. No lab started.", "info");
							return;
						}
					}
					report(await runLab({ ...common, scenario }));
				} catch (error) {
					const stopped = abort.signal.aborted && error === abort.signal.reason;
					ctx.ui.notify(stopped ? "/lab: Stopped before launching a lab." : `/lab: ${errorText(error)}`, stopped ? "info" : "error");
				}
			})().finally(() => {
				active = undefined;
				ctx.ui.setStatus("herdr-lab", undefined);
			});
			active = { abort, done };
		},
	});
}
