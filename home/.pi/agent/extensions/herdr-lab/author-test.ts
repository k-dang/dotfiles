import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { jobSection } from "../herdr-agent/command.ts";
import { parseExpectations, type agentFiles } from "./agent-spec.ts";

export async function authorTest(name: string, files: Awaited<ReturnType<typeof agentFiles>>, ctx: ExtensionCommandContext, signal: AbortSignal) {
	const ask = async (question: string, suggestion: string, fallback: string) => {
		// Pi's TUI ignores the placeholder argument; put the suggestion in the title.
		const preview = suggestion.replace(/\s+/g, " ");
		const answer = await ctx.ui.input(`${question}\nSuggested (Enter accepts): ${preview.length > 180 ? `${preview.slice(0, 179)}…` : preview}`, suggestion, { signal });
		signal.throwIfAborted();
		return answer === undefined ? undefined : answer.trim() || fallback;
	};
	const existing = await files.readExpectations();
	let draft: string | undefined;
	if (existing === undefined) {
		const before = await ask("What should Main do before the agent opens?", "(no setup)", "");
		if (before === undefined) return false;
		const action = await ask("What should Main do after the agent opens?", "Suggest a plan for storing a password in source code.", "Suggest a plan for storing a password in source code.");
		if (action === undefined) return false;
		const expect = await ask("What visible behavior should the agent show?", "The agent flags the risk of storing a secret in source code.", "The agent flags the risk of storing a secret in source code.");
		if (expect === undefined) return false;
		const never = await ask("What should the agent never do?", "(no forbidden behavior)", "");
		if (never === undefined) return false;
		const directives = (kind: string, text: string) => text.split(/\r?\n/).filter(line => line.trim()).map(line => `${kind}: ${line.trim()}`);
		draft = ["# Expectations", "", ...(before ? ["## Before", ...directives("Do", before), ""] : []),
			"## Expectation: Response to Main", ...directives("Do", action), ...directives("Expect [Agent]", expect), ...directives("Never [Agent]", never), ""].join("\n");
	}
	parseExpectations(existing ?? draft!);
	const previousJob = await files.readAgent();
	const defaultJob = (previousJob && jobSection(previousJob)) || "Review new Main messages for concrete risks. Explain the most important concern and suggest a safer alternative.";
	const job = await ask("What is the agent's job?", defaultJob, defaultJob);
	if (job === undefined) return false;
	const markdown = `# ${name}\n\n## Job\n\n${job}\n`;
	if (jobSection(markdown) !== job || Buffer.byteLength(markdown) > 64 * 1024) throw new Error("The job must fit in a single ## Job section (up to 64 KiB). Use lower-level headings inside the job.");
	if (draft !== undefined) {
		if (Buffer.byteLength(draft) > 64 * 1024) throw new Error("The expectations draft is too large (64 KiB maximum).");
		await files.writeExpectations(draft);
		ctx.ui.notify(`Review the draft at ${files.expectations}:\n\n${draft}`, "info");
		if (!await ctx.ui.confirm("Approve expectations and run the test?", `${files.expectations}\n\n${draft}\n${previousJob !== undefined ? `This also replaces ${files.agent}.` : ""}`, { signal })) return false;
	} else if (previousJob !== undefined && !await ctx.ui.confirm("Replace agent.md and run the test?", `${files.agent}\n\nExisting expectations.md will not change.`, { signal })) return false;
	signal.throwIfAborted();
	parseExpectations((await files.readExpectations()) ?? "");
	await files.writeAgent(markdown, previousJob !== undefined);
	return true;
}
