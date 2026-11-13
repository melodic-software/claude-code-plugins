---
bump: patch
---

### Fixed

- `block-root-delete-target` no longer refuses a python or node program fed on a quoted heredoc (`python3 - <<'EOF'`, `node - <<'EOF'`) because a backtick or `$(` span in its strings holds a word like "form" and a paren. Such a span is still read when a deleter name starts a word in it or it holds a `$`, and any other heredoc shape is scanned as before.
