---
bump: minor
---

### Added

- `scripts/check-plan-citations.sh` fails a PLAN.md whose `path:line` citation (a path from the repository root, then a line, a `start-end` range or a comma list of them) names a file, or a line, that does not exist at a named commit (default `HEAD`). It prints one `citation=` line per failure with its reason (`missing-path`, `not-a-file`, `line-zero`, `reversed` or `past-end`) and the full commit it checked at ([#10037](https://github.com/melodic-software/claude-code-plugins/issues/10037)). Citations inside code fences and on a line marked `<!-- citation-example -->` are skipped, and a fence left open exits 2. `/planning:plan`'s Step 4.7 outcome gate runs it, and the PLAN.md template carries a `Citations checked at:` line for the commit it printed.
