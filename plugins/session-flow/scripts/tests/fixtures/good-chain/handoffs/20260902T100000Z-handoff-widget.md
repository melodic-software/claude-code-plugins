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

Purpose: run the staging migration. Written 2026-09-02T10:00Z on `feat/widget-importer` at
`def5678`, clean tree. The re-run test is green; staging is next. Full sequence:
**Remaining actions, in order**. Before changing anything, read **Constraints that must hold**.

## Completion criteria

Why: a second import run currently doubles every row.

- [x] `pytest tests/test_importer.py` green with the new re-run test
- [ ] the migration adds a unique index on `(source, external_id)` (staging pending)

## Constraints that must hold

- [h1] The public `WidgetReader` signature is frozen; two downstream repos compile against it.
- [h2] The staging migration runs only inside the maintenance window; outside it the index
  build locks the table for the whole tenant.

Superseded:
- [h1] Migrations run forward-only; a down-migration corrupts the tenant partition key.

## Environment to re-establish

- Branch `feat/widget-importer`, clean tree; confirm with `git status --porcelain`.
- No background tasks; no TaskCreate call was made this session.

## Side effects already applied

- [h1] Migration `20260901_add_widget_index` is APPLIED to the local database; do not re-run.
- [h2] PR #42 is already open against this branch; push, do not create a second one.

## File roles in this work

- `src/importer.py` — modified; the composite key is in place and green (commit `abc1234`).
- `tests/test_importer.py` — modified; the re-run case is green (commit `def5678`).

## Decisions already settled

- [h1] Composite key `(source, external_id)` rather than a content hash → the hash changes when
  upstream reformats descriptions. Forecloses the hash approach.
- [h2] The re-run test seeds two identical batches rather than mocking the feed → the mock hid
  the duplicate. Forecloses a mocked-feed variant.

## Approaches tried and abandoned

- [h1] Deduplicating in memory before the insert → the batch is streamed and never fully in
  memory. Not salvageable without buffering the whole feed.

## Findings that cost effort to discover

- [h1] The upstream feed re-emits every row with a new `updated_at` on each fetch, so
  `updated_at` is useless as a change marker. Observed across three fetches in `logs/import.log`.
- [h2] The unique index build on staging takes eleven minutes; observed in the staging job log.

## Remaining actions, in order

1. Run the migration on staging inside the maintenance window.
2. Re-run the importer twice on staging and diff the row counts.

## Open questions to investigate

None. The staging window is known and the runbook is written.

## Blockers needing an outside decision

None. Nothing waits on a person or an access grant.

## Suggested skills

- `/testing:run-e2e` (if installed) for the staging double-run.

## This session

did: wrote the re-run test and got it green · left: the staging migration and the double-run check

## Prior sessions

| date | session id | transcript | did/left | file |
|---|---|---|---|---|
| 2026-09-01T10:00:00Z | aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | /work/projects/-work-repo/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jsonl | did: added the composite key to importer.py and ran the local migration · left: the re-run test and the staging migration | 20260901T100000Z-handoff-widget.md |

## Resume prompt

`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @/work/repo/.work/handoffs/20260902T100000Z-handoff-widget.md, confirm its Original goal still governs the remaining next steps, then continue them. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.
Handoff origin: ssh://git@github.com/example/repo .work/handoffs/20260902T100000Z-handoff-widget.md
Next:
Run the migration on staging inside the maintenance window
Re-run the importer twice on staging and diff the row counts
Then: /testing:run-e2e
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`.
