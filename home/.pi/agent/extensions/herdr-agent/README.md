# `/agent` for Pi and Herdr

Run `/reload` in Pi after syncing this extension. From the local Herdr pane you want to use as **Main**:

- `/agent critic` opens a built-in agent in a Pi pane to the right.
- `/agent reviewer` opens a saved job.
- `/agent check Check the proposal for unsupported assumptions` starts an inline job.
- `/agent --model anthropic/claude-haiku-5-5 reviewer` picks a model by ID.
- `/agent --pick-model reviewer` opens the model picker. Use ↑/↓, Enter, or Esc. Support also has Pi’s own `/model` command.
- `/agent` lists built-in and saved agents and `/agent --help` shows the full guide. Pi suggests names and options as you type.

The default is `anthropic/claude-haiku-5-5`. The support process uses the same Pi executable and working directory, but starts fresh with read-only file tools and no other extensions, MCP, or project context. Pick a Pi model available without a provider extension. This feature targets local Herdr panes, not remote machines.

## Built-in agents

Names aren't case sensitive.

| Agent | Job |
| --- | --- |
| `critic` | Challenges each request and Main’s reply: missing information, what else the change touches, and whether it should be smaller steps. |
| `notes` | Keeps decisions, open questions and next steps. |
| `research` | Checks claims against the project’s files and cites paths. It has no web access and says when a claim needs outside facts. |
| `historian` | Answers questions about Main’s earlier conversation. It doesn’t follow Main. When you ask it something, it searches Main’s saved session with its only tool, `historian`: prompt and reply text on the active branch, including originals before compaction, but not tool output or thinking. The support model sees the excerpts it reads. Main must have a saved session (not `--no-session`). |

A saved job with the same name replaces the built-in job. Historian keeps its history tool either way.

## Saved jobs

Add `agents/<name>/agent.md` in Main’s working directory, or `~/.pi/agent/agents/<name>/agent.md` for a personal job. The project copy wins. Only the body of `## Job` is sent; metadata, the title, and other sections are ignored. Supplying an inline job overrides the saved job.

## Follow and send

Opening a pane is a Pi extension command, not a prompt to Main. Except for Historian, support receives **new** Main prompt text and completed reply text from that Pi session. It does not receive earlier history, attachments, thinking, tool results, or other agents’ messages. The selected support model can see the relayed text. Give support only conversations you want that model to see.

Support numbers its finished findings within its own pane. Use `/agent send main #2` there, or `/agent send main` to choose a finding with the arrow keys. Nothing is sent back unless you choose it. Sending puts the finding in a local, session-scoped queue. Pi’s prompt-start hook attaches it as separate context to the next new prompt you submit while Main is idle. It never starts a turn, interrupts a reply, or types into Main’s draft. A finding is removed from the queue once Pi adds it to a run. Switching Main to a different Pi session does not carry over the feed or pending findings.

The live feed and queued findings use files under your OS temp directory (`pi-herdr-agent/`). If you want to remove old relay data, clear that directory when no linked panes are running. Findings that have already been attached are part of your Main Pi session history.

## Tests

```sh
node --test home/.pi/agent/extensions/herdr-agent/test/agent.test.mjs
```
