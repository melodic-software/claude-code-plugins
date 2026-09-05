---
type: handoff
handoff_shape: 2
date: 2026-09-02T10:00:00Z
topic: widget
session_id: bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
transcript: /work/projects/-work-repo/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jsonl
previous_handoff: 20260901T100000Z-handoff-widget.md
chain:
  - 20260901T100000Z-handoff-widget.md
  - 20260902T100000Z-handoff-widget.md
---

## Original goal

**Goal (verbatim, 2026-09-01):**

> Make the widget importer idempotent so a re-run never duplicates rows.

**Amended:** None.

Opening ask: see 20260901T100000Z-handoff-widget.md § Original goal

**Next action serves it by:** the staging migration is the last step before a production re-run is safe.

## Resumption brief

Written 2026-09-02T10:00Z on `feat/widget-importer`; next: the staging migration
(**Remaining actions, in order**). Read **Constraints that must hold** first.

## Completion criteria

Why: a second import run doubles every row.

- [ ] the migration adds a unique index on `(source, external_id)`

## Constraints that must hold

- [h1] UNVERIFIED (predecessor failed validation): The public `WidgetReader` signature is frozen.

## Environment to re-establish

- Branch `feat/widget-importer`; nothing running; no TaskList to recreate.

## Side effects already applied

- [h1] UNVERIFIED (predecessor failed validation): Migration `20260901_add_widget_index` is APPLIED locally; do not re-run.

## File roles in this work

- `tests/test_importer.py` — modified; the re-run case is green.

## Decisions already settled

- [h1] UNVERIFIED (predecessor failed validation): Composite key over content hash → the hash changes on upstream reformatting.

## Approaches tried and abandoned

None. The ground is untrodden.

## Findings that cost effort to discover

- [h1] UNVERIFIED (predecessor failed validation): `updated_at` changes on every fetch, so it is useless as a change marker.

## Remaining actions, in order

1. Run the migration on staging.

## Open questions to investigate

None. Nothing is unknown that the next session must resolve itself.

## Blockers needing an outside decision

None. Nothing waits on a person.

## Suggested skills

None. Remaining work runs inline.

## This session

did: wrote the re-run test · left: the staging migration

## Prior sessions

| date | session id | transcript | did/left | file |
|---|---|---|---|---|
| 2026-09-01T10:00:00Z | aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | /work/projects/-work-repo/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jsonl | did: added the composite key · left: the re-run test | 20260901T100000Z-handoff-widget.md |

## Resume prompt

`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @/work/repo/.work/handoffs/20260902T100000Z-handoff-widget.md, confirm its Original goal still governs the remaining next steps, then continue them. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.
Handoff origin: ssh://git@github.com/example/repo .work/handoffs/20260902T100000Z-handoff-widget.md
Next:
Run the migration on staging
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`.
