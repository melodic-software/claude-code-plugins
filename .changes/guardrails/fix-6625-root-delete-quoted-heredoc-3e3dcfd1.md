---
bump: patch
---

### Fixed

- **`block-root-delete-target` no longer refuses a backticked `rm -rf /` quoted inside a heredoc whose delimiter is quoted (#6625).** Bash expands nothing in a `<<'EOF'`, `<<"EOF"` or `<<\EOF` body, so `gh pr create --body-file - <<'EOF'` with an example command in Markdown backticks now runs. An unquoted heredoc body is still scanned, so a substitution there that deletes a root is still refused.
