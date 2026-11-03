---
bump: minor
---

### Added

- The `code-tidying:comment-reviewer` agent. `/code-tidying:remove-comments` hands it the triage and the comment-only edits, checks its diff with the token proof, retries a rejected report once, and applies any code moves itself.
- Postures `none`, `necessary` and `explanatory` (setting `comment_posture`, default `auto`: `explanatory`, or `necessary` with `--pipeline`). Under `necessary` only machine-read directives, license headers, `TODO(#issue)` markers, paired comment-and-test records, public-API doc comments and verified outside-constraint comments stay; every other comment is deleted with its narrative staged and a reshape flag naming the symbol.
- Settings `comment_edit_scope` (`diff` by default: only the comments on lines a change adds) and `encode_constraints_unattended` (off by default), and a constraint-encoding step that offers a type, an assertion, a test or a lint rule for a constraint comment.
- The settings now also read from `docs/conventions/code-tidying.yaml` and its personal overlay `code-tidying.local.yaml`, validated by `schemas/code-tidying.schema.json`.

### Changed

- `/code-tidying:dissolve-comments` is now `/code-tidying:remove-comments`, which gains an `audit` action that holds the residue classifier. `/code-tidying:audit-comment-residue` stays as a read-only skill that runs that action. The old `aggressive` and `strip` tokens still work as `necessary` and `none`, and the old posture values still resolve. A linked workaround comment no longer survives `necessary`: it is deleted and listed as open root-cause work.

### Removed

- The `dissolve-comments` skill.
