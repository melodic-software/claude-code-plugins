---
bump: minor
---

### Changed

- `/disk-hygiene:clean`: `preview` now takes the tier and its paths inline (`--tier` plus repeated `--path`, in place of `--plan`), and the engine writes an all-`unmanaged` `plan-<tier>.json` beside the snapshot under that fixed name. Step 4 no longer has the model write the plan, so a tier costs no protected-path write under `~/.claude` for it: a prompt in default and acceptEdits mode, a classifier round trip in auto, a denial in dontAsk. An inline path follows the handoff-list rules (relative, no traversal, present in the snapshot, non-overlapping). The inline plan's prose is fixed text, so the approval table reads provenance and risk from the audit report. `--plan` still works, and the `apply`, `handoff-apply` and lexer shapes are unchanged. ([#4225](https://github.com/melodic-software/claude-code-plugins/issues/4225))
