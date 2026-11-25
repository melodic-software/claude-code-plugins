# Steer compaction from a per-session focus file that focus.py alone reads and writes

- Status: accepted
- Date: 2026-11-24
- Related: [ADR 0131](0131-give-every-hook-its-own-on-off-setting-at-the-user-and-repository-layers.md)
  (the on/off setting this hook follows); [session-flow settings](../../plugins/session-flow/reference/config.md)

## Context

A session running a `/goal` or `/loop`, or a `/session-flow:step-away` absence, rides automatic
compaction instead of handing off. The compaction summary can drop what that session must keep:
the goal condition, the handoff file it resumed from, the step-away task file. Claude Code uses a
PreCompact hook's stdout as instructions for the summary, capped at 10,000 characters per hook
([PreCompact output](https://code.claude.com/docs/en/hooks#precompact-output), read 2026-11-24).
Live probes on Claude Code 2.1.331 showed the hook's text survives an automatic compaction, that it
and a manual `/compact` focus both reach the summary, and that a typed `/goal <condition>` reaches
UserPromptSubmit as the raw prompt. Several writers need the same state: the prompt hook on a typed
`/goal`, step-away at launch and return, and the resume step.

## Decision

1. **One file per session, `<plugin data>/focus/<session>.md`**: a fixed lead line saying the
   user's own `/compact` instructions win where they conflict, then up to four sections (Goal,
   Handoff, Task file, Note), each replaced only by its own writer. The Goal line is conditional
   ("if this /goal is still active"), so a goal that ended as met or impossible, which gives no hook
   signal, leaves a harmless line. The file stays under 9,000 characters; an over-long goal is cut
   and says so.
2. **`plugins/session-flow/scripts/focus.py` is the only code that opens `focus/`**: `set`,
   `clear`, `print` and `hook PreCompact|UserPromptSubmit`. Skills call the CLI; the hooks call it
   through `hooks/run-focus-hook.sh`. A format change touches one file.
3. **A PreCompact hook with no matcher prints the file** on manual and automatic compaction, and
   never blocks: it exits 0 always, logs to stderr only, prints nothing with no file.
4. **A UserPromptSubmit hook records a typed `/goal`**: `^/goal\s` followed by an argument replaces
   the Goal section, `clear` and the aliases the goal page lists remove it, and a bare `/goal`
   changes nothing. It never prints, so it adds no context. The node launcher skips it unless the
   payload holds `/goal`, so an ordinary prompt costs one process.
5. **`compact_focus_enabled` (default on) gates every write and every print**, per ADR 0131: the
   user's own value wins, then `docs/conventions/session-flow.yaml`, then the default. The node
   launcher stops a user `false` before bash starts.
6. **`set` sweeps files older than 14 days**, longer than the recurring-task expiry; `print` and
   the PreCompact hook never delete.

## Alternatives considered

- **(a) Each writer edits the file itself.** Three writers would each carry the format and the
  lock; a format change would touch all three. Not chosen.
- **(b) Read the goal from the transcript at PreCompact.** Reads a growing file on every fire, and
  the probe showed the prompt hook already sees a typed `/goal`. Not chosen.
- **(c) A self-handoff before compaction.** Fights an active goal and spends turns near the
  context limit. Not chosen.
- **(d) A mod in place of settings hooks.** A mod costs no process on the steady path, but the
  writer is Python and session-flow's hooks launch through node; a mod would need a second writer
  in JavaScript. Not chosen.
- **(e) One UserPromptSubmit entry for both the `/goal` write and resume context.** One hook would
  serve two settings, which ADR 0131's one-key-per-hook rule forbids. Not chosen.

## Consequences

- Hook stdout steering the summary is observed, not documented as a guarantee; when a release
  changes it, the file becomes advisory.
- A goal cleared by `/clear` leaves its file to the age sweep, since the new session has a new id.
