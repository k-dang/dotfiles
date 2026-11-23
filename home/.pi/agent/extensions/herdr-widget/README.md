# Pi project widgets

Run `/reload` in Pi after installing this extension under `~/.pi/agent/extensions/herdr-widget/`. Then run `/widget new review` in the Pi pane you want to use as **Main**. `/widget help` prints the guide and bare `/widget` lists the current project's saved widgets. Creation saves the definition but does not run it.

```text
/widget new review
/widget open review
/widget open review --sample
/widget close review
```

Opening needs the local **Herdr desktop app** with mod panes and the Node/npm build of **Pi**. The extension installs its managed `pi-project-widget` mod on first open. The panel is a native GPUI pane: it uses Herdr's theme, click and keyboard focus, split resizing, and saved tab layout, without a web server or a second Pi terminal. Additional widgets stack below the first one. Drag the split divider to give Main more room if desired.

## Define a widget

Describe what you want in prose. The wizard offers a suggested answer for each unspecified setting, including a small model from your configured models when possible, its lowest supported thinking level, and manual refresh. To skip questions, give explicit fields on their own lines. For example:

```text
Show likely follow-up work from the local working tree.
source: ["git","--no-optional-locks","status","--short"]
judge: List modified files that warrant review. Only use the status output; don't infer code changes.
action: view
refresh: manual
```

Other optional fields are `model: provider/model-id` and `thinking: off`. The widget's model must be available to standalone Pi using its built-in catalog or `models.json` and its normal credentials; models supplied only by another extension or a virtual router won't work. The foreground model and thinking level are not changed.

Definitions are `widgets/<name>/settings.json` and `widgets/<name>/instructions.md` under the Git root (or Pi's working directory outside Git). Edit them and reopen to approve the new definition. The worker checks the approved definition before running either a refresh or an action.

## Collect and replay

- For a file, use `file:path/to/input.txt` relative to the project root.
- For a command or script, use a JSON argv array, e.g. `["node","scripts/collect.mjs"]`. Use an executable or explicit interpreter; a shell, alias, pipeline, or Windows `.cmd` shim isn't run implicitly. Stdout is the collected data. For MCP, the script or CLI must make a specific, read-only MCP call and print its result. It does not ask Main or a model to select or run a tool.
- For repeatable input, create `widgets/<name>/sample.txt` and open with `--sample`. Every refresh in that pane rereads the file instead of running the live collector. To switch back, open without `--sample`. Identical input does not guarantee identical model output.

Open shows the source, provider/model, refresh cadence, and action before approval. Only approve collectors you trust to be read-only: they're ordinary local programs, not sandboxed. The collector or sample is limited to 64 KiB of UTF-8 text, passed to the configured model as data in a tool-free request. Do not include secrets you don't want that provider to receive. Scheduled refresh can keep running while the panel is hidden as long as Herdr is open. `manual` still runs once on open; `R` or the **Refresh** button runs another gather and judge immediately (queues one rerun if already busy).

## Use items

Click the panel to focus it. Use **↑/↓** or click a row to select it, **D** for details, **Enter** to view or review the selected action, and **R** to refresh. A `view` widget has no side effects. A `send` widget offers to submit the selected suggestion to the original idle Main Pi process. An `append:notes.md` widget offers to append to a fixed project-relative `.md` or `.txt` file whose parent already exists. Both require **Y** or the confirmation button; **Esc** cancels. Refresh and keyboard navigation never apply actions. If Main is restarted, reopen the widget from Main before sending.

Creation, opening, refresh, listing, and help are local command/UI operations; only a confirmed **Send to Main** can start a Main turn. Close the panel with `/widget close <name>` or Herdr's normal pane controls; the definition stays on disk.

## Verification

From this directory, `node --test test/widget.test.mjs` checks the worker with a stub Pi runtime. For a mod check, copy only `mod/main.js` and `mod/mod.json` to a temporary directory and run `herdr-app check <temp-dir>` (Herdr generates editor files in the checked directory).
