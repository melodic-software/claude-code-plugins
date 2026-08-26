# I-songwriting

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 2 `HUMAN` rows
(`plugins/songwriting/README.md` and `plugins/songwriting/CHANGELOG.md`). The CHANGELOG is judged as
a class in `README.md`.

The 106-file group is almost entirely `AGENT` rows belonging to `L7`, plus a vendor tree this lane
never reads.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| I1 | `plugins/songwriting/README.md:79` | `M2` | S2 |

### I1. Release history inside a licence notice

`plugins/songwriting/README.md:74` opens `## License`. Its second paragraph, verbatim:

```text
**This wording changed in 0.8.6 because the previous version was inaccurate.** It
said the plugin "contains distilled craft guidance and short verified anchor
quotes, not book text." Since 0.8.5 that has not been true. The research files
under `context/pat-pattison/research/` reproduce Pat Pattison's examples, worked
analyses, exercise wording and printed answer keys **verbatim**, along with the
song lyrics he analyses, because a summarized exercise is not an exercise, and
a described worked example is not an example.
```

Predicate `M2`. The paragraph's first three sentences are a correction notice: what the licence text
used to say, when it changed, and why. That is changelog content. `plugins/songwriting/CHANGELOG.md`
is required to carry a `0.8.6` entry by `scripts/check-changelog-parity.sh`, so the record already
has a home.

This is the most delicate finding in the lane, and the remediation is deliberately conservative.
**Every factual and legal claim stays.** What moves is only the framing that addresses a reader of
the old version.

Replacement for the quoted paragraph:

```text
The research files under `context/pat-pattison/research/` reproduce Pat Pattison's examples, worked
analyses, exercise wording and printed answer keys **verbatim**, along with the song lyrics he
analyses, because a summarized exercise is not an exercise, and a described worked example is not
an example.
```

The three deleted sentences move verbatim into the `## [0.8.6]` entry of
`plugins/songwriting/CHANGELOG.md` if they are not already there. **Wave 3 must check that entry
first**, and must not delete from the README until the changelog carries the correction. Losing a
recorded licence correction would be worse than leaving it in the wrong document.

Note that `scripts/check-changelog-parity.sh` sanctions in-place corrections to an already-released
entry only when the correcting PR names each edit in its body and in the new release entry. If the
`0.8.6` entry needs augmenting rather than merely being confirmed, that gate applies to the sweep's
own PR.

## Document mode

`plugins/songwriting/README.md` holds reference mode through its skills and requirements sections
and then shifts, correctly, into **explanation** for the licensing question. Explanation is the one
mode that permits a view, and this section takes one:

```text
**If you are not the owner, do not treat the reproduced book text or lyrics as
MIT-licensed material.** Buy the books. They are the source, and they are worth
it:
```

That is a command with its condition in front, followed by an opinion the mode allows. It is
correct as written and this lane proposes no change to it. Recorded because a conformance pass that
read `## License` as reference would flatten it, and the resolved guide's register gate forbids
that.

The section's heading is the only thing that misleads: `## License` promises the SPDX identifier and
nothing else, and 28 prose lines follow. Filed at S3, no edit proposed. If wave 3 is already in the
file, renaming to `## License and attribution` would set the reader's expectation correctly.

## Predicates with no findings in this group

`M1`, `M3`, `A1`, `A2`, `L1`, `Am1`, `Am2`, `Am3`, `Am4`, `N1`, `C1`.

On `M3`: `plugins/songwriting/README.md` declares no `userConfig` and carries no generated options
block. Not applicable.

On `L1`: zero sentences over the filter in this README, the only plugin README in the corpus with a
`## License` section this long and no backtracking sentence anywhere.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this README. The book titles at lines 103 to 106 are italicised
  work titles, not emphasis formatting.
- **`source-control`**: the I1 remediation touches a released changelog entry, which
  `scripts/check-changelog-parity.sh` gates on PR-body content. The orchestrator should route that
  requirement to whoever writes the sweep's PR body.
