import { realpathSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";

export const READY = "Herdr lab pane ready";
export const MODEL_MISMATCH = "Herdr lab model mismatch";

export default function (pi) {
  const lab = process.env.HERDR_LAB_AGENT && JSON.parse(process.env.HERDR_LAB_AGENT);
  const support = process.argv.some(arg => arg.startsWith("--herdr-agent-link="));
  const role = support ? "agent" : "main";
  let timer;
  let phase;
  let promptOpen = false;
  let initialJobPending = support;
  let modelOk = true;

  function mark(state) {
    if (!lab || state === phase) return;
    writeFileSync(join(lab.root, `${role}-activity.json`), JSON.stringify({ state, terminal: process.env.HC_TERMINAL_ID }), { mode: 0o600 });
    phase = state;
  }

  pi.on("session_start", (_event, ctx) => {
    const wanted = support ? lab?.model : process.env.HERDR_LAB_MODEL;
    const selected = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "(none)";
    modelOk = !wanted || wanted === selected;
    if (!modelOk) {
      mark("model-mismatch");
      ctx.ui.notify(`${MODEL_MISMATCH}: wanted ${wanted}, selected ${selected}`, "error");
      return;
    }
    if (lab) {
      const update = () => mark(ctx.isIdle() && !ctx.hasPendingMessages() && !promptOpen && !initialJobPending ? "idle" : "busy");
      update();
      clearInterval(timer);
      timer = setInterval(update, 100);
      timer.unref();
    }
    ctx.ui.notify(READY, "info");
  });
  pi.on("session_shutdown", () => { clearInterval(timer); mark("closed"); });
  pi.on("agent_settled", () => { initialJobPending = false; });
  pi.on("ui_prompt_start", () => { promptOpen = true; });
  pi.on("ui_prompt_end", () => { promptOpen = false; });
  pi.registerCommand("lab-probe", {
    description: "Echo text locally without a model turn",
    handler: (args, ctx) => ctx.ui.notify(`Lab probe received: ${args}`, "info"),
  });
  pi.on("input", (_event, ctx) => {
    if (modelOk && process.env.HERDR_LAB_MODEL_TURNS === "1") return;
    ctx.ui.notify("Model turns are disabled in this lab pane.", "warning");
    return { action: "handled" };
  });
  pi.on("tool_call", (event, ctx) => {
    if (!support || !lab) return { block: true, reason: "Tools are disabled in the lab Main." };
    // Keep the support agent's normal read-only tools, scoped to the checkout.
    if (["read", "find", "grep", "ls"].includes(event.toolName)) {
      try {
        const path = realpathSync(resolve(ctx.cwd, (event.input.path ?? ".").replace(/^@/, "")));
        const from = relative(realpathSync(join(lab.root, "project")), path);
        if (!isAbsolute(from) && from !== ".." && !from.startsWith(`..${sep}`)) {
          event.input.path = path;
          return;
        }
      } catch { /* Block unresolved paths as well. */ }
    }
    return { block: true, reason: "The lab agent can only read paths in the isolated project." };
  });
  pi.on("user_bash", () => ({ result: { output: "Shell commands are disabled in the lab.", exitCode: 1, cancelled: false, truncated: false } }));
}
