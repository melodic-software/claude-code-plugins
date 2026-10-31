---
bump: minor
---

### Added

- `block-root-delete-target` judges a delete run through `eval`, `watch`, `wsl`, `cmd /c` or a shell that reads its program from stdin the way it judges a recursive `rm`: one aimed at a root or at HOME is refused, and when the payload carries a cwd the target must sit under the git toplevel or strictly under a temp root, the session scratchpad or an allowed root. That covers the words `eval` joins, the command `watch` runs through `sh -c` (or as its argv with `-x`), the command line `wsl` hands the distribution's shell, `rd /s`, `rmdir /s` and `robocopy` in the line `cmd /c` or `cmd //c` runs from the Bash tool, a heredoc or here-string a shell reads as its program (`bash <<'EOF'`), and the text `echo`, `printf` or a `cat` of a heredoc pipes into a shell (`echo 'rm -rf /' | sh`). A mechanism named inside quoted prose, such as a `git commit -m` message, stays allowed.
