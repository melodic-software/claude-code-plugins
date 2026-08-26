# Mechanical noise-detector baseline

Full-corpus run of `audit-noise`'s own `scripts/detect.sh`, captured before the L5 lane began, so
the lane spends its budget on judgment instead of re-deriving the mechanical layer.

## Provenance

Two defects in the detector had to be fixed before this run was possible at all. Both were the same
shape: a `BASH_REMATCH` read placed after a `flush_negation` call that overwrites it. See
docs-hygiene `0.21.12` and `0.21.13`. Before those fixes the scan died at file 213 of 1302 and
reported the files it had reached as though that were the whole corpus.

Anyone re-running this must confirm the run exits `0` **and** that the reached-file count matches
expectations. A partial scan here does not look partial.

## Coverage

| | Count |
|---|---|
| In-scope corpus | 1302 |
| Scanned | 1218 |
| Skipped: `CHANGELOG.md` | 84 |

The 84 skips are all `CHANGELOG.md`, excluded by basename in `detect.sh` per the skill's own hard
rules. Coverage over what the detector is meant to scan is complete.

## Raw findings by shape

| Shape | Count |
|---|---|
| `enum-list` | 4568 |
| `negation` | 1229 |
| `ghost-ref` | 36 |
| `ticket-pr-residue` | 7 |
| `citation` | 7 |
| `preamble` | 4 |
| `scope-meta` | 3 |
| `plan-reference` | 2 |
| `conversational-antecedent` | 2 |

Tier split: 4582 Tier 1, 1276 Tier 2, 0 Tier 3.

## How to read these numbers

**These are detector candidates, not findings.** Two shapes are 99% of the volume, and both are
recall-biased by design:

- `enum-list` at 4568 across 1218 files is roughly 3.7 per file. A hit rate that uniform across a
  corpus this varied is the signature of a cue that fires on structure rather than on a defect.
- `negation` at 1229 has the same problem in a repo whose whole subject matter is prohibitions and
  guardrails. A rule file that says what not to do is doing its job.

The skill body is explicit that this detector is recall-biased and that the author owns every
treatment decision. The lane's job is to triage these down to what is genuinely worth editing, and
to say plainly how many candidates it rejected. A lane that reports thousands of findings has
copied the detector's output rather than judged it.

The six low-volume shapes (61 candidates total) are where the precision is. Start there.

## Regenerating

```bash
git ls-files '*.md' | grep -v '/vendor/' > paths.txt
plugins/docs-hygiene/skills/audit-noise/scripts/detect.sh --paths-file paths.txt
```

Takes about four minutes.
