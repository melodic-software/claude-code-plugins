---
bump: minor
---

### Changed

- `select` treats deleting a trailing comment (code, then ` # ...` on the same line, the code left byte for byte) like deleting a whole comment line, in a shell file and in a `case.yaml`, under the same hidden rule. A `case.yaml` comment counts only when the file parses the same without it; a `#` inside a quote, heredoc, block scalar, `$(`, `${`, `((` or backtick stays content.
- The hidden check proves more scaffold helpers hidden, each by a pattern that cannot expose the script: the body of a `cat` or `tee` heredoc with a quoted delimiter (written out, never run), a `plugins: [...]` entry naming the suite's own plugin, a double-quoted copy whose literal ending (`"$dir/$1.txt"`) the script's name cannot match, a variable bound to the script's exact path and only run, a `$(cd "$var/.." && pwd)` path, a `(cd dir && bash "$script")` run, an `echo`, `printf` or `${1:?message}` that prints the script's name, and `$0` inside single quotes (awk's record). A script that runs a string (`eval`, `bash -c`) gets none of the single-quote reading.
- A shell `$'...'` string now reads cleanly, so a file holding one keeps the comment-deletion exemption.
- A `plugins/*/skills/*/evals/` folder gets no hidden exemption: it is not the plugin's eval directory, so the agent can read it with the skill.

### Fixed

- A `case.yaml` edit that only drops a trailing comment no longer counts as a description-only edit, which ran nothing without the hidden check.
