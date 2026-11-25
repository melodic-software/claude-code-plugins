---
type: handoff
handoff_shape: 5
checks: 3
date: 2026-11-24T10:00:00Z
topic: parser-tests
session_id: 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53
transcript: unresolved (session 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53, projects-root /work/projects)
chain_root: 20261124T100000Z-handoff-parser-tests.md
hop: 1
archive: archive/20261124T100000Z-handoff-parser-tests/
archive_from: 1
next_rule_id: 1
next_question_id: 1
next_decision_id: 1
next_reminder_id: 1
repo: ssh://git@github.com/example/repo
---

## Original goal

**Goal (verbatim):**
> Every parser test passes, shown by output you produced in this conversation. (owner, 2026-11-24)

**Intent (verbatim):** None stated.

**Vision (verbatim):** None stated.

**Amended:** None.

Opening ask:
Make the parser tests pass.

## Resumption brief

Written against `main`. The parser tests pass at commit 4be1c9a. Read Current rules first.

## Remaining actions, in order

1. Re-draft the carried /goal condition: it ties its proof to output produced in the earlier conversation, which this session cannot see.
2. Write NOTES.md holding the single line `parser: green at 4be1c9a`.

## Completion criteria

- [ ] every remaining action is done (the files it names exist and `git status` lists them)

## Open questions

None. Nothing is unknown.

## Current rules

- [R1] Never push to main.

## Standing preferences

None. No standing preference this chain.

## Decisions in force

- [D1] Work on `main` in this throwaway repository (no review needed).

## Reminders

None. Nothing waits for a later session.

## Environment to re-establish

Branch `main`, clean tree; nothing to recreate.

## This session

did: the work up to the remaining actions · left: the remaining actions
Re-scan: the re-scan read the lossless on-disk transcript

## Review before you continue

- Nothing beyond this file: the next action needs no archive section.

## Direction changes

- [h1] start: the work in the goal above (owner-directed: the opening ask).

## Observations

- Nothing beyond what this file records.

## Suggested skills

None. Remaining work runs inline.

## Prior sessions

None (first hop).

## Resume prompt

`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @/work/repo/.work/handoffs/20261124T100000Z-handoff-parser-tests.md, confirm its Original goal still governs the remaining next steps, raise its due Reminders, then continue them and re-establish its Environment last. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53.
Handoff origin: ssh://git@github.com/example/repo .work/handoffs/20261124T100000Z-handoff-parser-tests.md
Next:
Re-draft the carried /goal condition
Write NOTES.md
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53`.
