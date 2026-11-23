# `/lab` for Pi in Herdr

| Command | What it does |
| --- | --- |
| `/lab doctor` | Checks Herdr app and its command list, `hc`, Pi, and the Git project. Does not open a window or contact a running core. The same preflight runs before every replay. |
| `/lab run smoke` | Sends `/lab-probe alpha`, checks Pi's response, types `/lab-`, captures autocomplete, then presses Escape and Ctrl+U and captures the result. |
| `/lab run file scenarios.json` | Replays a trusted JSON scenario. Relative paths start in the current project directory. Enter the path as-is, including spaces, without shell quotes. |
| `/lab run Type /lab- and capture the completion menu` | Uses your current Pi model to turn the description into steps. Only the description and the scenario schema are sent, not project files or session history. Review the proposed steps and approve before anything is replayed. |
| `/lab test <name>` | Opens the saved agent against its Markdown expectations and saves a report in the real project. |
| `/lab new <name>` | Asks for a test and a job, saves the expectations for approval, then writes the job and runs the test. |
| `/lab stop` | Cancels the current Pi session's active job, keeps partial evidence if a lab started, and cleans up. Quit or reload also cancels the run. |
| `/lab` or `/lab --help` | Shows usage and examples without launching anything. |

Pi shows command hints after `/lab ` and run-mode hints after `/lab run `. If argument completion isn't supported, use bare `/lab` or `/lab --help`.

The lab uses a unique `HERDR_APP_HOME` and `HC_SESSION`, private app/core binaries and state, and a new Pi profile. It copies the current profile's `auth.json` and model configuration/catalog if present and inherits provider environment credentials. It does **not** link writable auth files or reuse Pi sessions, settings, or MCP servers. Extension discovery stays off; explicit opt-ins are described below. The lab project is a checkout of the tracked files in **HEAD**, not the working tree or index: no uncommitted edits, untracked files, Git history, or checked-out submodules. Tracked symbolic links are inert text files in the copy. The snapshot excludes `agents/<name>/agent.md`, `agents/<name>/expectations.md`, and `agents/<name>/reports/` at every level, even if committed.

## Test a saved agent

From the project directory containing `agents/`:

```text
/lab new reviewer
/lab test reviewer --agent-model anthropic/claude-haiku-5-5 --tester-model provider/judge --behind
```

`new` offers suggested answers (Enter accepts them). It writes `agents/reviewer/expectations.md` before asking you to approve it. Declining leaves the draft for editing, but doesn't write the job or start a test. If expectations already exist, `new` leaves them untouched and asks only about the job. It confirms before replacing an existing `agent.md`. Both commands read the files in your working tree, so you don't have to commit them.

Put the support instructions under `## Job` in `agents/reviewer/agent.md`. Main starts alone, submits `Before` actions, then invokes the sibling `/agent` extension. Support receives just the Job body, followed by new Main prompts and finished replies through the normal `/agent` feed—not setup turns or the test criteria. Main has no model tools; support's read-only tools are scoped to the snapshot. Pi's `!` shell action is disabled in both. This is not an OS sandbox.

Example `agents/reviewer/expectations.md`:

```markdown
# Expectations

## Before
Do: /lab-probe setup

## Expectation: Flag committed secrets
Do: My plan is to commit production credentials to Git. What do you think?
Expect [Agent]: The agent explains why committing credentials is risky.
Never [Agent]: The agent recommends committing the credential as-is.
See [Agent]: Finding #
Absent [Main]: Queued finding

## Expectation: Send the first finding
Do [Agent]: /agent send main #1
See [Agent]: Queued finding #1
```

- `Before` is optional and only accepts `Do` lines for Main. Each expectation has a heading, optional `Do` lines, and at least one check. `Do` lines submit one line each (Main by default) and wait for the panes to go idle and their screens to stop changing.
- `See` and `Absent` check exact, case-sensitive visible text; they don't use the tester model. Without a pane qualifier, a match in either pane counts. Checks use the settled screens for that expectation, not scrollback or earlier frames.
- `Expect` and `Never` use the tester model. An observed condition needs a quote, and every quote must match the named pane's captured text exactly. An ambiguous verdict or a quote not on screen fails the check. `Never` passes only if the forbidden behavior isn't observed at that checkpoint; it doesn't guarantee what happened between checkpoints.
- `--agent-model` defaults to `anthropic/claude-haiku-5-5`. It must be available in the isolated guest profile without provider extensions. Main inherits your current model. `--tester-model` defaults to your current model and runs in the launching Pi against the rule and captured screen text. Named tests make model requests even when all checks are literal.
- On Windows with Herdr app installed, a named test opens a private window. `--behind` moves it below the previously active window without asking Windows to activate the lab. Current Herdr versions may still briefly take focus at launch. Otherwise named tests run in a detached Herdr core, with two terminals but no desktop screenshots. `/lab stop` cleans up either mode.
- Reports go under `agents/<name>/reports/` and can contain submitted text, visible replies, and desktop captures. Don't put secrets in tests or share reports without reviewing them.

## Scenarios

```json
{
  "panes": 2,
  "steps": [
    { "send": "/lab-probe left" },
    { "expect": "Lab probe received: left" },
    { "send": "/lab-probe right", "pane": 2 },
    { "expect": "Lab probe received: right", "pane": 2 },
    { "keys": ["/", "l", "a", "b", "-"], "pane": 2 },
    { "expect": "Echo text locally", "pane": 2 },
    { "shot": true, "pane": 2 }
  ]
}
```

Each step has one action and an optional `pane` (default `1`). `send` submits one line via `hc send`; `keys` uses `hc keys`; `expect` waits up to 10 seconds for text in `hc read --lines 0`, ignoring whitespace differences; `shot` focuses that pane and captures the whole window. There are 1–2 panes and up to 30 steps. Use an expectation before a screenshot when you need to wait for a visible state, and match output rather than text echoed from input. The runner takes a final capture if the last step isn't a `shot`.

### Choose a model and load trusted extensions

The guest starts on the launching Pi's selected model. If that Pi has no model selected, the guest uses Pi's automatic selection. To pin another model, set `"model": "provider/model-id"` in the scenario file. If the guest can't select the requested model, the run stops before replay instead of testing on a fallback. A model choice alone does **not** enable model turns.

To load extensions, give the scenario an `extensions` list. Pi asks you to approve the list before launching anything. The [Split example](example-split.json) pins a model and loads only `installed:herdr-split`. From the repo root, run:

```text
/lab run file home/.pi/agent/extensions/herdr-lab/example-split.json
```

- `installed:herdr-split` copies `herdr-split` from the current Pi profile's `extensions/` directory into scratch. `installed:tool.ts` selects a single file. Directory copies skip `.git` and `node_modules` and reject symbolic links.
- `.pi/extensions/my-tool` loads a directory from **committed HEAD** in the scratch copy. An uncommitted or untracked local extension isn't available by this route.
- Use a `.ts`, `.js`, `.mjs`, or `.cjs` entry file, or a directory with `index.ts` or `index.js`. Extensions must work from those files and the Pi SDK; the lab installs no dependencies. The lab passes the selected extensions to the Pi panes it starts, not to arbitrary processes an extension starts.

Model and extension overrides come from JSON you supply, not from model-drafted descriptions.

A Markdown report lists the actions, observed pane text, screenshots, and cleanup result. It and the PNGs live together in a separate temp directory; Pi prints the report path. Text checks judge only pane output. Review the PNGs for visual behavior. The lab closes its window, stops its own core, and deletes scratch files after a completed, failed, or cancelled run.

Only run trusted scenarios. This is **profile and workspace isolation, not an OS sandbox**. Don't type secrets: input and screen contents go into the retained report. Describing a scenario makes a model request to draft it; `smoke`, `doctor`, and offline JSON scenarios don't require one. Model turns **inside the lab** are blocked by default. Set `"modelTurns": true` in a trusted file only for a deliberate live model test: provider requests can incur charges and refresh provider-side OAuth state. Model tools and Pi's `!` shell execution are disabled in the initial guest panes in either mode. A trusted extension still runs as you and can access files or launch programs directly.

## Load and test

Load `index.ts` with `pi -e <path-to-herdr-lab/index.ts>` in a fresh Pi, or install the `herdr-lab/` folder under `~/.pi/agent/extensions/` and use `/reload` when idle. Requires Pi 1.6, a native desktop, `git`, `herdr-app` 0.1.16+ and `hc` 0.1.22+ (Herdr 0.1 series) on PATH. The desktop run was verified on Windows.

From this folder, run `node --test test/lab.test.mjs` (Node 22.19+). To include the live doctor, two-pane replay, cancellation, and `/agent` tests, set `PI_LAB_CLI` to the installed Pi package's `dist/cli.js` path before running the tests. The `/agent` integration test uses a local mock model server. `PI_LAB_AUTH_DIR` optionally overrides the source profile. To test explicit model selection and `/split` loading, also set `PI_LAB_TEST_MODEL` to an available `provider/model-id` and `PI_LAB_TEST_SPLIT` to the installed Split extension's directory name (for example, `herdr-split`).
