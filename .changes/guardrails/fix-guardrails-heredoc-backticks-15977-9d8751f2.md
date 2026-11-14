---
bump: patch
---

### Fixed

- `block-root-delete-target` no longer refuses a python or node program fed on a quoted heredoc (`python3 - <<'EOF'`, `node - <<'EOF'`) because a backtick or `$(` span in its strings holds a word like "form" and a paren. Such a span is still read when it holds a `$`, a glob, brace, pipe or redirection character, a backslash other than `\n`, `\t` or `\r`, or a deleter, shell or eval word at the start of a word, also after the shell joins quoted pieces (`r""m`); any other heredoc shape is scanned as before.
