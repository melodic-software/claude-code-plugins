---
type: handoff
date: 2026-09-01T10:00:00Z
topic: legacy
session_id: 11111111-1111-4111-8111-111111111111
---

## Original goal

**Goal (verbatim, 2026-09-01):**

> Make the widget importer idempotent so a re-run never duplicates rows.

**Amended:** None.

**Next action serves it by:** the dedup key is the last piece the importer needs before a re-run is safe.

## Resumption brief

Purpose: finish the importer dedup key. Written 2026-09-01T10:00Z on `feat/widget-importer` at `abc1234`,
clean tree. First concrete action: add the composite key to `importer.py`. Full sequence:
**Remaining actions, in order**. Before changing anything, read **Constraints that must hold**.

## Completion criteria

Why: a second import run currently doubles every row.

- [ ] `pytest tests/test_importer.py` green with the new re-run test
- [ ] the migration adds a unique index on `(source, external_id)`

## Constraints that must hold

- The public `WidgetReader` signature is frozen; two downstream repos compile against it.
- Migrations run forward-only; a down-migration corrupts the tenant partition key.

## Environment to re-establish

- Branch `feat/widget-importer`, clean tree; confirm with `git status --porcelain`.
- No background tasks; no TaskCreate call was made this session.

## Side effects already applied

- Migration `20260901_add_widget_index` is APPLIED to the local database; do not re-run.

## File roles in this work

- `src/importer.py` — still to modify; the composite key is not written yet.
- `tests/test_importer.py` — test that must pass; the re-run case is still missing.

## Decisions already settled

- Composite key `(source, external_id)` rather than a content hash → the hash changes when
  upstream reformats descriptions. Forecloses the hash approach.

## Approaches tried and abandoned

- Deduplicating in memory before the insert → the batch is streamed and never fully in memory.
  Not salvageable without buffering the whole feed.

## Findings that cost effort to discover

- The upstream feed re-emits every row with a new `updated_at` on each fetch, so `updated_at`
  is useless as a change marker. Observed across three fetches in `logs/import.log`.

## Remaining actions, in order

1. Add the composite key to `src/importer.py`.
2. Add the re-run test to `tests/test_importer.py`.
3. Run the migration on staging.

## Open questions to investigate

- Does the reader honor `CancellationToken` on the streaming path? Probe: cancel mid-enumeration.

## Blockers needing an outside decision

None. Nothing waits on a person or an access grant.

## Suggested skills

- `/testing:write` (if installed) for the re-run test.
