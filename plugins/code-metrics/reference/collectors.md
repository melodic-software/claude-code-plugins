# Collectors and parsers

One stamped row per external tool the plugin can run and per artifact format it can read. Each
row is a verification stamp in the marketplace's upstream-drift form: the claim the adapter relies
on, where it was verified, when, and the observable event that obliges re-deriving it. The
ordered ladder that decides which tool a lane tries first is `scripts/collector-ladder.tsv`; this
table is the provenance behind it.

| Tool or format | Lane(s) | Measure | Claim the adapter relies on | Basis | Verified | Recheck trigger |
|---|---|---|---|---|---|---|
| `scc` 3.7.0 | every lane | `file_lines` | `scc --by-file --format json` prints a list of per-language objects, each with `Files[]` carrying `Location`, `Lines`, `Code`, `Comment`, `Blank`; the `Complexity` field is a substring count and is never read | github.com/boyter/scc, probed in this repository | 2026-09-05 | an scc release changes the JSON shape, or ships a parsed per-function cyclomatic mode |
| bundled counter | every lane | `file_lines` | total and blank lines only; comment-agnostic by construction, labelled so in every row | this plugin | 2026-09-05 | none; it has no upstream |
