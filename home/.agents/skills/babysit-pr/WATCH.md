# Watch branch

Use this branch only for an explicit watch, monitor, or babysit request.

## Start

1. Run one merge-gate pass before announcing the watch.
2. Save the final snapshot as baseline: head SHA; issue-comment, review, review-comment, and thread IDs plus update times; thread resolution; review decision; and check names/states.
3. Record start, deadline, and a 60-second poll interval unless the user requested another interval.
4. Prefer one isolated async agent for the full watch. It is the only writer. If no async execution exists, keep the watch in the foreground.

Completion: baseline, deadline, poll interval, and sole writer are explicit.

## Poll

At each interval, rerun `scripts/snapshot.py` and compare with baseline. Trigger a merge-gate pass on:

- new or edited feedback
- review/thread state change
- check state transition
- review-decision change
- remote head change

Ignore unchanged records. Do not announce empty polls.

After this skill pushes a new head, replace check baseline with that head's checks; old-head checks are not evidence. Keep all feedback IDs so delayed edits or thread changes remain detectable.

Completion: every changed record since the prior poll is classified or handled, then baseline is updated.

## Deadline

Poll through the deadline. Feedback arriving before it belongs to the watch: finish triage, fixes, validation, push, replies, and final checks even when that work extends past the deadline. Do not begin another idle interval after deadline.

Finish with `WATCH_COMPLETE` and the underlying merge-gate state.

Completion: no pre-deadline event remains unhandled and no watcher remains running.
