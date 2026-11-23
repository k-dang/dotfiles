import { strict as assert } from "node:assert";
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { completions, isHistorian, jobSection, parseOpen, PRESETS, savedJob, savedNames } from "../command.ts";
import { historyRecords, searchHistory } from "../history.ts";
import { Mailbox } from "../mailbox.ts";

function temporary(t) {
	const dir = mkdtempSync(join(tmpdir(), "pi-agent-test-"));
	t.after(() => rmSync(dir, { recursive: true, force: true }));
	return dir;
}

test("keeps inline job text and separates launch flags from the job", () => {
	assert.deepEqual(parseOpen("--model anthropic/haiku review Look at \"a b.ts\"\nThen report"), {
		name: "review", model: "anthropic/haiku", pick: false, job: "Look at \"a b.ts\"\nThen report",
	});
	assert.equal(parseOpen("review --pick-model").pick, true);
	assert.equal(parseOpen("review -- --custom-option").job, "--custom-option");
	assert.equal(parseOpen("review Report --model in the docs").job, "Report --model in the docs");
	assert.throws(() => parseOpen("../other"), /name/);
	assert.throws(() => parseOpen("review --model haiku --pick-model"), /only one/);
});

test("a saved job excludes unrelated sections and headings inside fences", (t) => {
	const dir = temporary(t);
	const project = join(dir, "project");
	const global = join(dir, "global");
	for (const root of [project, global]) mkdirSync(join(root, "review"), { recursive: true });
	const text = "# Agent\r\nignored\r\n```md\r\n## Job\r\n```\r\n## Job\r\nCheck the changes.\r\n### Evidence\r\n```md\r\n## Not a heading\r\n```\r\n## Notes\r\nprivate";
	writeFileSync(join(project, "review", "agent.md"), text);
	writeFileSync(join(global, "review", "agent.md"), "## Job\nGlobal fallback");
	assert.equal(savedJob([project, global], "review"), "Check the changes.\n### Evidence\n```md\n## Not a heading\n```");
	assert.deepEqual(savedNames([project, global]), ["review"]);
	assert.equal(savedJob([global], "review"), "Global fallback");
	assert.equal(jobSection("# No job"), undefined);
	assert.deepEqual(completions("rev", ["review"], false).map(({ value }) => value), ["review"]);
	assert.deepEqual(completions("send", [], true).map(({ value }) => value), ["send main"]);
});

test("built-in agents open without a saved job, by any case, and a saved job replaces one", (t) => {
	const root = temporary(t);
	assert.deepEqual(Object.keys(PRESETS), ["critic", "notes", "research", "historian"]);
	assert.equal(savedJob([root], "Critic"), PRESETS.critic.job);
	assert.equal(savedJob([root], "NOTES"), PRESETS.notes.job);
	assert.throws(() => savedJob([root], "unknown"), /No saved agent/);
	mkdirSync(join(root, "critic"));
	writeFileSync(join(root, "critic", "agent.md"), "## Job\nProject critic");
	assert.equal(savedJob([root], "critic"), "Project critic");
	assert.deepEqual(savedNames([root]), ["critic"]);
	assert.ok(isHistorian("Historian") && !isHistorian("notes"));
	assert.deepEqual(completions("r", [], false).map(({ value }) => value), ["research"]);
	assert.match(completions("n", [], false)[0].description, /^Built-in/);
	assert.deepEqual(completions("c", ["critic"], false).map(({ value, description }) => [value, description]), [["critic", "Open saved job"]]);
});

test("a Historian link is not a follower, so it never turns on Main's feed", (t) => {
	const main = new Mailbox(join(temporary(t), "main"));
	const file = main.link("historian", "answer", "C:/sessions/main.jsonl");
	Mailbox.attach(file);
	assert.equal(JSON.parse(readFileSync(file, "utf8")).history, "C:/sessions/main.jsonl");
	assert.equal(main.hasFollowers, false);
	Mailbox.attach(main.link("critic", "review"));
	assert.equal(main.hasFollowers, true);
});

test("Historian searches visible speech and summaries, not tool output or thinking", () => {
	const message = (id, role, content) => ({ id, type: "message", message: { role, content } });
	const records = historyRecords([
		message("u1", "user", "Drop the first demo, it is too slow"),
		message("a1", "assistant", [{ type: "thinking", thinking: "secret demo plan" }, { type: "toolCall", name: "bash" }, { type: "text", text: "Dropped the demo." }]),
		message("t1", "toolResult", [{ type: "text", text: "demo tool output" }]),
		{ id: "c1", type: "compaction", summary: "Earlier: the demo was dropped." },
		message("u2", "user", "x".repeat(5000) + " tail"),
	]);
	assert.deepEqual(records.map(({ id, speaker }) => [id, speaker]), [["u1", "User"], ["a1", "Main"], ["c1", "Compaction summary"], ["u2", "User"]]);
	const found = searchHistory(records, { query: "DEMO" });
	assert.equal(found.total, 3);
	assert.deepEqual(found.entries.map(({ id }) => id), ["u1", "a1", "c1"]);
	assert.doesNotMatch(JSON.stringify(found), /secret|tool output/);
	assert.equal(searchHistory(records, {}).entries[0].id, "u2");
	const read = searchHistory(records, { entry: "u2", offset: 4000 });
	assert.equal(read.more, false);
	assert.match(read.text, /tail$/);
	assert.throws(() => searchHistory(records, { entry: "t1" }), /No entry/);
});

test("each support link sees only later complete Main records, in byte order", (t) => {
	const main = new Mailbox(join(temporary(t), "main"));
	assert.equal(main.hasFollowers, false);
	const link = (name) => JSON.parse(readFileSync(main.link(name, "observe"), "utf8"));
	const first = link("first");
	assert.equal(main.hasFollowers, true);
	main.publish({ kind: "prompt", text: "Check π 🐍" });
	const second = link("second");
	appendFileSync(main.transcript, '{"kind":"reply","text":"Don');
	assert.deepEqual(main.read(second.offset), { offset: second.offset, notes: [] });
	appendFileSync(main.transcript, 'e"}\n');
	assert.deepEqual(main.read(first.offset).notes, [
		{ kind: "prompt", text: "Check π 🐍" }, { kind: "reply", text: "Done" },
	]);
	const tail = main.read(second.offset);
	assert.deepEqual(tail.notes, [{ kind: "reply", text: "Done" }]);
	assert.deepEqual(main.read(tail.offset).notes, []);
});

test("closing the last follower stops the feed without clearing sent findings", (t) => {
	const main = new Mailbox(join(temporary(t), "main"));
	const link = main.link("review", "review");
	Mailbox.attach(link);
	assert.equal(main.hasFollowers, true);
	main.enqueue({ name: "review", number: 1, text: "ready" });
	main.publish({ kind: "prompt", text: "old" });
	Mailbox.detach(link);
	assert.equal(main.hasFollowers, false);
	assert.equal(main.pending()[0]?.text, "ready");
	main.link("new", "observe");
	assert.deepEqual(main.read(0).notes, []);
});

test("findings are out-of-band, scoped to Main and acknowledged individually", (t) => {
	const dir = temporary(t);
	const main = new Mailbox(join(dir, "main"));
	const other = new Mailbox(join(dir, "other-session"));
	main.link("review", "review");
	other.link("review", "review");
	main.enqueue({ name: "review", number: 2, text: "first" });
	const [first] = main.pending();
	main.enqueue({ name: "other", number: 2, text: "second" });
	main.acknowledge([first.id]);
	assert.deepEqual(main.pending().map(({ text }) => text), ["second"]);
	assert.deepEqual(other.pending(), []);
	assert.deepEqual(main.read(0).notes, []);
});
