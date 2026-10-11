---
bump: patch
---

### Fixed

- **`block-root-delete-target` no longer refuses a backticked `rm -rf /` quoted inside a heredoc whose delimiter is quoted (#6625).** Bash expands nothing in a `<<'EOF'`, `<<"EOF"` or `<<\EOF` body, so where that body plainly feeds `cat`, `tee` or `gh pr|issue|api|release` (one command on the line, no pipe, redirection or substitution), `gh pr create --body-file - <<'EOF'` with an example command in Markdown backticks now runs. A body fed to a shell (`bash <<'EOF'`, `cat <<'EOF' | sh`, `bash -c "$(cat <<'EOF' ...)"`) and every unquoted heredoc body are still scanned, so a root delete there is still refused.
