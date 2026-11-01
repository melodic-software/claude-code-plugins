---
bump: patch
---

### Fixed

- `plugin-eval` preflight prints an `eval_tmpdir` field and refuses before any spend when the `TMPDIR` directory the run step will use is longer than 24 characters and a case requests `Bash` or `PowerShell`. 24 characters is the longest length measured to work; at 63, the shell sandbox's Unix sockets could not be created, so every shell call failed while the run still exited 0 and scored ([#11740](https://github.com/melodic-software/claude-code-plugins/issues/11740)).
- `run-validity.py` names a `session started` failure in its verdict as a harness failure whose score measures the harness, not the skill, and the `read` action reports such a run that way instead of as the skill's result.
- `reference/sandboxes.md` gives the 24-character bound for `<dir>` in the Docker link swap and Sandbox start sections, with the socket names and measurements behind it.
