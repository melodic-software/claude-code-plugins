---
bump: minor
---

### Changed

- `select` treats deleting a trailing comment (a `#` comment after code on the same line, the code left byte for byte) like deleting a whole comment line, in a shell file and in a `case.yaml`, under the same hidden rule. A `case.yaml` comment counts only when the file parses the same without it; a `#` inside a quote, heredoc, block scalar, `$(`, `${`, `((` or backtick stays content.
- The hidden check proves more scaffold helpers hidden by setting aside a few reference forms: the body of a `cat` or `tee` heredoc with a quoted delimiter (written out, never run), a `plugins: [...]` entry naming the suite's own plugin, a double-quoted copy whose literal ending (`"$dir/$1.txt"`) neither the script's name nor a folder holding it can match, a line that only binds a variable to the script's exact path that is only run, a `$(cd "$var/.." && pwd)` path, a `(cd <dir> && bash "$script" <args>)` run with `<dir>` outside the suite, an `echo`, `printf` or `${1:?message}` message that prints the script's name, and `$0` inside an `awk`, `sed`, `grep` or `jq` program. A file that pipes into a shell, runs a string (`eval`, `bash -c`, `trap`, `alias`) or sources a stream (`/dev/stdin`, `<(...)`, a here-string) gets neither the heredoc nor the quote reading. A literal heredoc's body counts as code once any case shell file names the file it writes on a line other than its opener or a plain `git add`, `rm` or `commit` (running, sourcing, renaming, linking or making it executable), and every body does when a case file runs a tool that executes files it finds (`make`, `npm`, `python`, `find`), points git's `hooksPath` anywhere but `/dev/null`, writes a heredoc into a hooks folder or to a name that is not literal, or redefines `cat`, `tee`, `PATH`, `BASH_ENV` or a sourced file; a file that sources anything gets no heredoc reading.
- A copy whose source is a helper's positional argument (`cp "$dir/$src"` with `src="$1"`) exposes nothing when every call of the helper passes only literal arguments and none names the script or a folder holding it.
- The hidden check also catches more ways a case exposes a file: an assignment with a command after it on the same line, a `cd` into the suite, a case file finding its own folder by `${0%/*}`, `realpath "$0"` or `__file__`, and a case script naming `case.yaml`.
- An `.editorconfig` line that `#` or `;` opens is a comment line, and deleting such lines runs no case anywhere, under an `evals/` folder too (an editor-settings comment cannot change what the agent does); a `#` after a value is part of the value, and any other `.editorconfig` edit keeps its treatment.
- A shell `$'...'` string now reads cleanly, so a file holding one keeps the comment-deletion exemption.
- A `plugins/*/skills/*/evals/` folder gets no hidden exemption: it is not the plugin's eval directory, so the agent can read it with the skill.

### Fixed

- A `case.yaml` edit that only drops a trailing comment no longer counts as a description-only edit, which ran nothing without the hidden check.
