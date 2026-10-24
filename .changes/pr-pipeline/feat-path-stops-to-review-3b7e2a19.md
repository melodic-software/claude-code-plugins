---
bump: minor
---

### Changed

- A trusted path no longer stops a lane; the review lanes judge it. `CODEOWNERS` and `.gitmodules` leave every `patch-rules.json` row and `UNIVERSAL_REFUSE`, and `.gitmodules` leaves `prepare.sh`'s conflict refusal. Address-feedback's thread scope is path hygiene alone (`thread-scope.mjs`: a plain path in normal form), so `CONTROL_PATH`, the instruction-file list and the plugin and `pr_paths` scope rules are gone from the select job, `apply-patch.mjs`'s `kept-threads` rule, the reply job and the review-thread tool; a PR that changes `.github/workflows/` no longer escalates `feedback-protected-path`.
- A kept path (a workflow, a `settings*.json`, a symbolic link, a gitlink, a backslash path, a rename into one) no longer refuses a `[head]` patch whole: `apply-patch.mjs` withholds it, pushes the rest, and writes the withheld part as `kept.diff` with its SHA-256. The write runner uploads it as `kept-paths-<lane>-<activity>-<attempt>`, and its `kept-paths` job posts it in one `<!-- lane-kept-paths -->` comment edited in place, naming the head, the SHA-256 and the run (`.github/scripts/apply-patch/kept-paths.mjs`). A PR patch of kept paths alone skips `prerequisite-missing`; an issue one comments that the apply is pending, adds no human label and removes `agent-ready`.
- `collect-patch.sh` leaves a CLI scrub-stub name that holds content out of the patch and names it on stderr, instead of writing no patch.
