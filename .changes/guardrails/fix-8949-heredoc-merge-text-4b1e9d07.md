---
bump: patch
---

### Fixed

- `block-unresolved-pr-merge` no longer refuses a command just because merge-shaped text and a backtick appear in the body of a quoted heredoc fed to a program that is not a shell, such as `python3 - <<'EOF'` or `git commit -F - <<'MSG'` (#8949). The backtick and line-continuation refusals now read the command with those bodies cut out, as the shared parser bounds them. A body is cut only when all of these hold:
  - it ends at its own plain-word delimiter;
  - it holds no backslash-newline and names no GraphQL merge mutation;
  - no word of the command names a shell, `sudo`, `su`, `ssh` or `at`;
  - the command word is not `eval`, `source`, `.` or a `.sh` script, and it can be read;
  - no backtick, `$(`, `${`, `$[`, `((` or `[[` comes before it.

  An unquoted heredoc body is never cut, because bash runs its backticks.
- hook-utils: `hook::bash_parse_segments` leaves the byte span of each here-doc body it skips in `HOOK_HEREDOC_BODIES`, along with whether its delimiter was quoted. `run-guards.sh` replays that array along with the rest of a shared parse. A here-doc delimiter word now ends at `(` or `)`, as it does in bash, so `(cat <<'E')` no longer hides the commands after its body.
