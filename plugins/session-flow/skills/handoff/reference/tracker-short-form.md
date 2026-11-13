# Tracker short form

A third path beside the engine's full save-point and prompt-only paths, for `/session-flow:handoff`
only. When a tracker item already holds the state the next session needs (for example a
`/planning:wayfind` map item, or the decision item being worked), the resume is two lines and
carries no session state, because the item is the save-point.

## When it applies

Every condition holds, each checked this turn:

- The item was read this turn, and every finding, decision and remaining action from this session
  is on it (in its body or a comment). A finding that is not yet on the tracker means the full
  handoff file, as the engine's "Choosing the path" sets out.
- The command that resumes the work takes the item's URL, in a form its skill documents (for
  example `/planning:wayfind work <map URL> <item URL>`).
- No uncommitted edits, no worktree claim held by this session, no off-thread work still running
  ("Settle in-flight work before writing"), no side effect the item does not record, and no active
  `/goal` or surviving `/loop` to carry over. Each of those is session state the item cannot hold.

Any condition that fails, or any doubt, takes the engine's path choice instead. An explicit `file`
or `prompt` argument also overrides this form.

## The two lines

The response ends with exactly these two lines, nothing after them:

```text
/clear, then run:
<command, with the item's full URL>
```

For example, `/planning:wayfind work https://example.com/org/repo/issues/40
https://example.com/org/repo/issues/42` as the one command on the second line. Each URL is a full
URL, never a bare number. No handoff file is written, and no position panel,
goal quote, session id, `Next:` headlines or rails are emitted.

## What still applies

- The redaction pass runs over the two lines.
- `wip_commit` is not applied (reason: tracker short form); with no uncommitted edits there is
  nothing to commit.
- The hard rule holds: after the two lines, execution stops.
- No file is written and no session id is carried, so this form leaves the same gap in the session
  chain `/session-flow:retro` walks as the prompt-only path. When that chain matters more than
  brevity, pass `file`; a session that also matches a full-file routing row takes the full file.
- An event after the two lines that adds a finding the item lacks ends this form's eligibility:
  write the full handoff.

Tick, in place of the path checklists: item read this turn and holding this session's state; each
condition above checked; redaction pass over the two lines; `wip_commit: not applied (tracker short
form)`; the two lines as the response's final text.
