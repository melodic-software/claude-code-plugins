# skill hubs: 5,000-token compaction re-attach slice

Recorded park for
[#4255](https://github.com/melodic-software/claude-code-plugins/issues/4255).

## Decision

**Parked, unpaid diet.** This repository does not split or reorder the
oversized `SKILL.md` hubs so their mandatory gates sit inside the first
5,000 tokens Claude Code re-attaches after compaction. The 500-line
`skill-quality:check` cap stays the merge gate. This file is the docs note.

**Claim:** five hubs exceed the ~20,000-byte / 5,000-token re-attach slice
(4 characters per token, the issue's conversion). After compaction their
own gates can drop. Dieting them is unpaid.
**Basis:** #4255; https://code.claude.com/docs/en/skills.md (fetched
2026-09-28): "Claude Code re-attaches the most recent invocation of each
skill after the summary, keeping the first 5,000 tokens of each.
Re-attached skills share a combined budget of 25,000 tokens." Disk
measurements on origin/main 2026-09-28:

| Hub | Bytes | Lines | Words | Lines in first 20,000 bytes |
|---|---|---|---|---|
| `planning:plan` | 47328 | 342 | 6711 | 147 (cut inside Step 3) |
| `discovery:research` | 41582 | 304 | 6152 | 142 |
| `discovery:explore` | 33132 | 254 | 4752 | 125 |
| `implementation:implement-dispatch` | 32614 | 158 | 4862 | 103 |
| `source-control:worktree` | 30982 | 209 | 4399 | 138 |

The issue title said four hubs and listed five files; all five still exceed
the slice. `planning:plan` still ends the 20,000-byte prefix inside Step 3;
Step 4.7's outcome gate and Step 5 (the approval gate the skill calls "the
point") sit outside it. Every listed hub is under the 500-line FAIL cap.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds the diets (or reorders gates into the first
~20 KB) and unparks #4255, or a fetch of skills.md drops or changes the
5,000-token re-attach figure.

## What stays

- The hubs as written.
- `skill-quality:check` FAIL at 500 whole-file lines (check 4) and WARN
  above 200 (check 10).
- Advisory 5k-token / re-attach guidance in
  `docs-hygiene:audit-progressive-disclosure` and
  `playbooks` skill-authoring.

## What does not ship

- Deleting spoke-duplicated content from the hubs.
- Moving `explore` worker content (lines 86-235 of the 2026-09-19 body)
  into `reference/workflow.md`.
- Extending `contract.test.sh` assertion 8 to every hub.
- A new merge-failing token-slice check.

## Rationale

- The line cap is already satisfied. A diet is a structural rewrite of four
  to five orchestrators, not a docs-only trim.
- The cheapest per-hub fix (pointer-not-copy, then reorder gates) is still
  unpaid authoring across `planning`, `discovery`, `implementation`, and
  `source-control`.
- Recording the exceedance is the note the issue allowed as the alternative
  to the diet.

## Revisit when

- A maintainer unparks #4255 and funds the diets, or
- skills.md changes the 5,000-token / 25,000-token re-attach budgets.

## Prior requests

- #4255 (2026-09-28): four (listed five) hubs over the re-attach slice;
  drain shipper parks the unpaid diet and records current sizes.
