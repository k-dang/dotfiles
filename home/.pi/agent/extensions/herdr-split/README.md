# `/split` for Pi in Herdr

Run `/split` in the Pi pane you want to branch, choose a user or assistant message, and press Enter. The new pane opens to the right in the same working directory. It gets the active conversation up to and including the selected message; nothing after it is copied. Esc cancels.

Run `/split --help` to print the guide in the current Pi pane, without splitting or sending a message to the model. Pi's command menu points to the help example, and typing `/split -` suggests `--help` with a short description. There are no other arguments; choose the branch point in the picker.

`/split` is a local Pi command, not a prompt. It leaves the original conversation and its session file alone, even while it is working. The new session gets a model-visible notice to leave the earlier work alone and wait for your next request. The notice does not start a model turn. Live extension state such as an active `/goal` isn't carried over. Both panes still share the same files; this does not create a Git worktree.

Install the `herdr-split/` folder under `~/.pi/agent/extensions/`. In an already-open Pi, run `/reload` once the current turn has finished, or use a fresh Pi instance. Confirm `/split` appears in slash-command autocomplete before submitting it. This extension uses the Pi 1.6 SDK and the local `herdr-app`, `hc`, and `pi` commands. It refuses if it cannot match the originating terminal to exactly one local Herdr pane with the same working directory; it never falls back to the focused pane.

To run the tests, set `PI_SDK` to the installed `@earendil-works/pi-coding-agent/dist/index.js` and run `node --test test/split.test.mjs` from this directory (Node 22.19+).
