---
bump: minor
---

### Added

- **The evidence comment shows a small change inline.** `/source-control:pull-request evidence` lays out a change with at most two acceptance criteria and at most `evidence_inline_max_captures` captures (default 4), each mapped to an entry point by a drive `report.json`, as a Before/After table, one column per interaction, a caption under each image, and one line naming the capturing tool and what each row's state is. Any other change, an `e2e-summary.json` input included, keeps one collapsed section per acceptance criterion and `Other captures`. `--before <file>` takes the base commit's evidence file, governed by its own `publishable` list. A video sits in its own paragraph under the table.
- **Optional record block.** With `evidence_record_fields: true` (off by default) the comment carries who ran the verification (`--verified-by`), when (the evidence file's write time) and the issues found with their resolution (`--issues`, else the run's failed entries).
- `scripts/read-evidence-layout.sh` reads both keys from `docs/conventions/source-control.yaml` at the pull request's base, honored only on the default branch, with tests.

### Changed

- The evidence comment leads with the run's text result, one line per criterion or entry point; captures support it. The verifier-verdict and leak-scan gates are unchanged.
