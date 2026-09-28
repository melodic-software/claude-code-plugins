# Interview finalize action: build-later backlog (#3941)

Option A: accept as a backlog row. No Action Router row and no page code in this record.

## Decision record

- **Claim:** A `finalize` action that recaps the Q&A from the register and checks that this
  skill's own procedure ran is build-later. The current stop sequence stays: Step 3
  confirmation gate, `scripts/check-open-questions.sh`, Step 4 `--brief` cross-check, and
  `/planning:audit-answers`. This record does not add an Action Router row (that table is
  digest-pinned) and does not add page code.
- **Basis:** Issue [#3941](https://github.com/melodic-software/claude-code-plugins/issues/3941).
  Upstream grilling (Lane 5 in `docs/upstream/aihero-course.md`) has a stop-condition plus a
  confirmation gate and no Q&A recap. The Action Router in `SKILL.md` is digest-pinned by
  `tests/interview-defenses.test.sh`, so adding a row is an attended change. Same docs-backlog
  shape as [#4653](https://github.com/melodic-software/claude-code-plugins/issues/4653).
- **As of:** 2026-09-28.
- **Recheck:** an operator names the shape (new Action Router action vs Step 3 gate extension
  vs separate skill) in an attended issue, then a PR may add the row and recompute the
  interview-defenses digests.

## Backlog

| Item | Decision | Notes |
| --- | --- | --- |
| Shape of `finalize` | Build later | Action vs gate extension vs separate skill. Record the choice before any SKILL.md edit |
| Q&A recap at sign-off | Build later | Source the register, not the transcript, so it survives compaction |
| Procedure-walked check | Build later | At least one mechanical exit code; name what stays model judgment |
| Overlap with `/planning:audit-answers` | Build later | Compose or state the non-overlap in both bodies |
| `3cca18b3` as-of line in `docs/upstream/aihero-course.md` | Ride along | Recheck-regime stamp; not a reason to build `finalize` |
| Upstream `---` separator between questions | Ride along | Cosmetic; verdict either way when `finalize` is built |

## Park

Do not add `finalize` to the Action Router in this settle. Do not extend the interview page
for a recap view. Track implementation under #3941 until the shape is named in an attended
issue.
