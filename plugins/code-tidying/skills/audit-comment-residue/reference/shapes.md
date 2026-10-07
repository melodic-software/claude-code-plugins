# Residue shape boundaries

The cues and boundaries `scripts/detect.sh` applies per shape. Read this when a finding, or a
missing one, needs explaining. SKILL.md carries the shape table and the treatments.

## `history-narration-weak` (Tier 2)

Cues: `"exactly as before"`, `"as before"`, `"has always used"`, `"always used"`, `"the old <word>"`
(`"the old shared group"`; `"replaces the old"` stays `plan-reference`), and a bare phase number
(`"(ci-perf Phase 6b)"`, `"cleanup for Phase 6"`). Each cue also opens ordinary prose
(`"as before the loop starts"`, `"the old value is compared against the new"`), so a person
decides. A phase number followed by more words (`"phase 2 of the build"`) is not a finding.

## `ticket-pr-residue` and the marker exemption

A `TODO` / `FIXME` / `HACK` / `XXX` marker tracking real work is never flagged as ticket residue.
The marker must be a whole word opening the comment or a clause and followed by `(` or `:`.

## `origin-note` (Tier 1)

- A dated freshness stamp (`"verified 2026-09-03 against v2.1.259"`, and the same with `checked`,
  `confirmed` or `as of`) is not this shape and stays. A bare date matches nothing.
- The verb-from cue has to open the comment or a clause inside it, so `"bytes copied from the source
  buffer"` is not a finding. The dated cue takes every anchor but the parenthesis.
- Two comment classes are exempt whatever verb they open with, because Tier 1 reads "remove": a
  marker comment (`TODO`, `FIXME`, `HACK`, `XXX`), which is tracked work, and a license or
  attribution header, whose text the reader may be legally required to keep.
- The license exemption is block-scoped: a run of contiguous comment lines in which any line carries
  `SPDX-License-Identifier`, `Licensed under`, `License:`, a `Copyright` next to a year or a
  `(c)`/`©` sign, or a `(c)` in front of a year is exempt whole, so the attribution line of a NOTICE
  header is covered even though the cue sits on a different line. The run ends at the first blank
  line or line of code, and a trailing comment on a code line starts no run, so the same sentence
  elsewhere in the file is an ordinary finding.
