# Editing the provenance audit skill: contributor conventions

## Keep measurement results out of `reference/rubric.md`

`reference/rubric.md` is inlined into every judge prompt at the judgment step, so anything
recorded in it is read by every judge before they grade. Nothing about a measurement's result
belongs in that file: not an expected tally, not the panel size, not an enumeration of which
golden case turns on which criterion. A judge should be able to read the whole file and still
not know the answer. Predictions, per-case enumerations, and the rubric's own version history
are `CHANGELOG.md` material.

Keep `reference/rubric.md` to the criteria, the carve-outs, the scope rule, the worked examples
and the tier table.

## `affected-tests.sh --run` exits 3 for this skill, and 3 is not failure

Exit 1 is a failing suite. Exit 3 means every shell suite it selected passed and it also selected
a suite in an ecosystem whose runner it deliberately declines to guess. This skill carries
`scripts/fingerprint.test.mjs`, so any diff touching it selects that suite and the runner can
never return 0.

Read both lanes: the shell result from `--run`, and `node scripts/fingerprint.test.mjs` on its
own.
