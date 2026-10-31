---
bump: minor
---

### Added

- The control-skill contract gains `## Mask` ([#11387](https://github.com/melodic-software/claude-code-plugins/issues/11387)): mask lines (`- <label> | <regex>`) or `none: <reason>` for what a `screenshot` or `video` must hide, and an optional `values:` line naming the config fields or read-only `cli/` commands that give the literal values to look for. A `screenshot` or `video` Capture command applies the mask lines and writes an `<artifact>.txt` sidecar holding the text the capture still shows.
- `/app-control:drive` writes redacted `report.public.md` and `report.public.json`, then scans each sidecar and both public reports for the `values:` values and a generic credential pattern, with line wraps joined and box-drawing characters stripped. `report.json` gains `capture_count`, `artifacts` (each with `mask`: `applied`, `none-declared`, `not-checked` or `hit`, and `publishable`) and `publishable`, the paths safe to upload. A hit, a missing sidecar, no `## Mask` line or an unresolved value keeps a file out; a raw capture and any file with a `secrets_mark` entry are never publishable.
- A `## Launch` command may name `<changed files>`: one argument per file in the run directory's `affected.json`.
- `/app-control:map check` reports a hub whose `## Capture` records a `screenshot` or `video` and whose `## Mask` holds no mask line, under the new `mask-missing` rule, and `/app-control:map create` writes a `## Mask` for such a hub.
