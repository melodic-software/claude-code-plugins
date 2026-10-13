---
bump: patch
---

### Fixed

- **`block-root-delete-target` no longer refuses a backticked `rm -rf /` quoted inside a heredoc whose delimiter is quoted (#6625).** Bash expands nothing in a `<<'EOF'`, `<<"EOF"` or `<<\EOF` body, so where the whole command is one `cat` or `gh pr|issue|api|release` line feeding that body (no pipe, redirection or substitution, nothing before it or after the body), `gh pr create --body-file - <<'EOF'` with an example command in Markdown backticks now runs. Every other heredoc body is still scanned, including one fed to a shell (`bash <<'EOF'`, `cat <<'EOF' | sh`, `bash -c "$(cat <<'EOF' ...)"`, a compound piped into a shell), so a substitution holding a root delete there is still refused.
