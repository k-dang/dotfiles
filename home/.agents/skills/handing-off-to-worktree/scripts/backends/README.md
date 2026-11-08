# Backends

A backend starts one agent session in an existing worktree. `handoff.sh` creates the worktree and branch; the backend only opens the session.

## Contract

```
backends/<name>.sh --worktree DIR --name NAME --task-file FILE -- <agent argv...>
```

- Start `<agent argv...>` with `DIR` as its working directory.
- Send the contents of `FILE` as the agent's first message, verbatim.
- Label the session `NAME` wherever the tool shows sessions.
- Print one line on stdout: the session address the user (or another agent) can read or reattach to. Everything else goes to stderr.
- Exit nonzero, with the tool's error on stderr, if the session did not start.

Select it with `--backend <name>` or `HANDOFF_BACKEND=<name>`. The script must be executable.

## Shipped

- `herdr-app.sh`: `herdr-app do space.new`; the address is the space's terminal (`hc read <address>` shows its screen). Works from any terminal while the Herdr app runs.

## Adding one

Copy `herdr-app.sh`, replace the one command that opens the session, and keep the output contract. Then add a line under Shipped.
