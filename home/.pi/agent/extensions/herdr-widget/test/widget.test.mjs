import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";
import test from "node:test";
import { boundedText, loadDefinition, parseItems, parseSettings, projectFile, widgetName } from "../definition.mjs";
import { runWidget } from "../worker.mjs";

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "pi-widget-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const dir = join(root, "widgets", "triage");
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, "settings.json"), JSON.stringify({ version: 1, model: "test/fast", thinking: "low", refreshSeconds: 0,
    action: { kind: "append", file: "chosen.md" }, source: { argv: [process.execPath, "-e", "console.log('live data')"] } }));
  await writeFile(join(dir, "instructions.md"), "Find things to review.");
  await writeFile(join(dir, "sample.txt"), "saved sample\n");
  const sdk = join(root, "fake-model.mjs");
  await writeFile(sdk, `import assert from 'node:assert/strict';
    export class ModelRuntime {
      static async create() { return new ModelRuntime(); }
      getPhysicalModel(provider, id) { assert.deepEqual([provider, id], ['test', 'fast']); return {}; }
      async settleCredentialWrites() {}
      async completeSimple(_model, context, options) {
        assert.equal(context.tools, undefined);
        assert.equal(context.messages.length, 1);
        assert.match(context.systemPrompt, /Find things to review/);
        assert.equal(options.reasoning, 'low');
        const { data } = JSON.parse(context.messages[0].content[0].text);
        return { stopReason: 'stop', content: [{ type: 'text', text: JSON.stringify({ items: [{ title: 'Review', detail: data, destination: 'not-chosen.md' }] }) }] };
      }
    }
  `);
  const { revision } = await loadDefinition(root, "triage");
  return { root, name: "triage", dir, sdk, revision, agentDir: root, sample: false };
}

test("live refresh runs the collector and sends only its output to a tool-free judgment", async t => {
  const spec = await fixture(t);
  assert.deepEqual(await runWidget("refresh", spec), { items: [{ title: "Review", detail: "live data" }] });
  await assert.rejects(readFile(join(spec.root, "chosen.md")), { code: "ENOENT" });
});

test("every sample refresh bypasses the live source; append happens separately to a fixed file", async t => {
  const spec = await fixture(t);
  const definition = join(spec.dir, "settings.json");
  const settings = parseSettings(await readFile(definition, "utf8"));
  await writeFile(definition, JSON.stringify({ ...settings, source: { argv: ["nonexistent-live-command"] } }));
  spec.revision = (await loadDefinition(spec.root, spec.name)).revision;
  spec.sample = true;
  const one = await runWidget("refresh", spec);
  assert.deepEqual(await runWidget("refresh", spec), one);
  assert.equal(one.items[0].detail, "saved sample");
  await assert.rejects(readFile(join(spec.root, "chosen.md")), { code: "ENOENT" });
  await runWidget("action", spec, one.items[0]);
  assert.match(await readFile(join(spec.root, "chosen.md"), "utf8"), /Review\nsaved sample/);
  await assert.rejects(readFile(join(spec.root, "not-chosen.md")), { code: "ENOENT" });
  await writeFile(join(spec.dir, "sample.txt"), "updated sample\n");
  assert.equal((await runWidget("refresh", spec)).items[0].detail, "updated sample");
});

test("definition edits stop both scheduled work and item actions until reopened", async t => {
  const spec = await fixture(t);
  await writeFile(join(spec.dir, "instructions.md"), "different criteria");
  await assert.rejects(runWidget("refresh", spec), /definition changed/);
  await assert.rejects(runWidget("action", spec, { title: "Test", detail: "No" }), /definition changed/);
});

test("path traversal, escaping links, oversized input, and invalid model items are rejected", async t => {
  const spec = await fixture(t);
  await assert.rejects(projectFile(spec.root, "../target.md", true), /project-relative/);
  const link = join(spec.root, "outside");
  await symlink(tmpdir(), link, process.platform === "win32" ? "junction" : "dir");
  await assert.rejects(projectFile(spec.root, "outside/target.md", true), /outside this project/);
  const file = join(spec.root, "large.txt");
  await writeFile(file, "a".repeat(9));
  await assert.rejects(boundedText(file, 8), /exceeds/);
  assert.throws(() => widgetName("../other"));
  assert.throws(() => parseItems('{"items":[{"title":"no detail"}]}'), /invalid item/);
});
