---
bump: minor
---

### Changed

- `select` treats deleting a trailing comment (a `#` comment after code on the same line, the code left byte for byte) like deleting a whole comment line, in a shell file and in a `case.yaml`, under the same hidden rule. A `case.yaml` comment counts only when the file parses the same without it; a `#` inside a quote, heredoc, block scalar, `$(`, `${`, `((` or backtick stays content.
- The hidden check proves more scaffold helpers hidden by setting aside a few reference forms: a `plugins: [...]` entry naming the suite's own plugin, a `$(cd "$var/.." && pwd)` path, a `(cd <dir> && bash "$script" <args>)` run with `<dir>` outside the suite, and `$0` inside an `awk`, `sed`, `grep` or `jq` program. A file that pipes into a shell, runs a string (`eval`, `bash -c`, `trap`, `alias`) or sources a stream (`/dev/stdin`, `<(...)`, a here-string) gets no quote reading.
- The hidden check also catches more ways a case exposes a file: an assignment with a command after it on the same line, a `cd` into the suite, a case file finding its own folder by `${0%/*}`, `realpath "$0"` or `__file__`, and a case script naming `case.yaml`.
- An `.editorconfig` line that `#` or `;` opens is a comment line, and deleting such lines runs no case anywhere, under an `evals/` folder too (an editor-settings comment cannot change what the agent does); a `#` after a value is part of the value, and any other `.editorconfig` edit keeps its treatment.
- A shell `$'...'` string now reads cleanly, so a file holding one keeps the comment-deletion exemption.
- A `plugins/*/skills/*/evals/` folder gets no hidden exemption: it is not the plugin's eval directory, so the agent can read it with the skill.

### Fixed

- A `case.yaml` edit that only drops a trailing comment no longer counts as a description-only edit, which ran nothing without the hidden check.
