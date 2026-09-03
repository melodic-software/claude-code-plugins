---
type: handoff
handoff_shape: 2
date: 2026-09-01T10:00:00Z
topic: widget
session_id: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
transcript: /work/projects/-work-repo/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jsonl
chain:
  - 20260901T100000Z-handoff-widget.md
---

## Original goal

**Goal (verbatim, 2026-09-01):**

> Make the widget importer idempotent so a re-run never duplicates rows.

**Amended:** None.

Opening ask:
Make the widget importer idempotent. A second run doubles every row today.
Start with the composite key, then the re-run test.

**Next action serves it by:** the re-run test is the observable that proves a second import adds nothing.

## Resumption brief

Purpose: finish the importer dedup work. Written 2026-09-01T10:00Z on `feat/widget-importer` at
`abc1234`, clean tree. The composite key landed; the re-run test is next. Full sequence:
**Remaining actions, in order**. Before changing anything, read **Constraints that must hold**.

## Completion criteria

Why: a second import run currently doubles every row.

- [ ] `pytest tests/test_importer.py` green with the new re-run test
- [ ] the migration adds a unique index on `(source, external_id)`

## Constraints that must hold

- [h1] The public `WidgetReader` signature is frozen; two downstream repos compile against it.
- [h1] Migrations run forward-only; a down-migration corrupts the tenant partition key.

## Environment to re-establish

- Branch `feat/widget-importer`, clean tree; confirm with `git status --porcelain`.
- No background tasks; no TaskCreate call was made this session.

## Side effects already applied

- [h1] Migration `20260901_add_widget_index` is APPLIED to the local database; do not re-run.

## File roles in this work

- `src/importer.py` — modified; the composite key is in place and green (commit `abc1234`).
- `tests/test_importer.py` — test that must pass; the re-run case is still missing.

## Decisions already settled

- [h1] Composite key `(source, external_id)` rather than a content hash → the hash changes when
  upstream reformats descriptions. Forecloses the hash approach.

## Approaches tried and abandoned

- [h1] Deduplicating in memory before the insert → the batch is streamed and never fully in
  memory. Not salvageable without buffering the whole feed.

## Findings that cost effort to discover

- [h1] The upstream feed re-emits every row with a new `updated_at` on each fetch, so
  `updated_at` is useless as a change marker. Observed across three fetches in `logs/import.log`.

## Remaining actions, in order

1. Add the re-run test to `tests/test_importer.py`.
2. Run the migration on staging.

## Open questions to investigate

- Does the reader honor `CancellationToken` on the streaming path? Probe: cancel mid-enumeration.

## Blockers needing an outside decision

None. Nothing waits on a person or an access grant.

## Suggested skills

- `/testing:write` (if installed) for the re-run test.

## This session

did: added the composite key to importer.py and ran the local migration · left: the re-run test and the staging migration

## Prior sessions

None (first hop).

## Resume prompt

`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @/work/repo/.work/handoffs/20260901T100000Z-handoff-widget.md, confirm its Original goal still governs the remaining next steps, then continue them. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.
Handoff origin: ssh://git@github.com/example/repo .work/handoffs/20260901T100000Z-handoff-widget.md
Next:
Add the re-run test to tests/test_importer.py
Run the migration on staging
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`.
