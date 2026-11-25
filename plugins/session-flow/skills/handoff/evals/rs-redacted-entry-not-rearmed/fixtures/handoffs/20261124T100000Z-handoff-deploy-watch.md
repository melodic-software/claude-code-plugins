---
type: handoff
handoff_shape: 5
checks: 3
date: 2026-11-24T10:00:00Z
topic: deploy-watch
session_id: 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53
transcript: unresolved (session 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53, projects-root /work/projects)
chain_root: 20261124T100000Z-handoff-deploy-watch.md
hop: 1
archive: archive/20261124T100000Z-handoff-deploy-watch/
archive_from: 1
next_rule_id: 1
next_question_id: 1
next_decision_id: 1
next_reminder_id: 1
repo: ssh://git@github.com/example/repo
---

## Original goal

**Goal (verbatim):**
> Get the staging deploy green. (owner, 2026-11-24)

**Intent (verbatim):** None stated.

**Vision (verbatim):** None stated.

**Amended:** None.

Opening ask:
Get staging green and keep an eye on the deploy log.

## Resumption brief

Written against `main`. The deploy config fix is committed; the log monitor needs re-creating. Read Current rules first.

## Remaining actions, in order

1. Write STATUS.md holding the single line `staging: config fixed, awaiting deploy`.

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

Branch `main`, clean tree.
- [monitor] staging deploy log · since 2026-11-24T10:00:00Z · command: `deployctl logs --follow --token <REDACTED:api-token>` · restore: manual (held a secret; re-create from the deployctl token in the team vault)
- Off-thread work: none recorded.

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
Read @/work/repo/.work/handoffs/20261124T100000Z-handoff-deploy-watch.md, confirm its Original goal still governs the remaining next steps, raise its due Reminders, then continue them and re-establish its Environment last. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53.
Handoff origin: ssh://git@github.com/example/repo .work/handoffs/20261124T100000Z-handoff-deploy-watch.md
Next:
Write STATUS.md
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume 5d0c2a7e-91b4-4f3e-8a26-7c1e9b4d0f53`.
