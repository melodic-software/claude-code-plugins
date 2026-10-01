## Checks

`check` runs `check-skill.sh`. Twenty-five checks, reported as `FAIL:` (blocking) or `WARN:` (advisory):

- `description` + `when_to_use` within the 1536-char **per-skill** listing-entry cap (overflow
  truncates that entry). A different, narrower limit from the shared budget below.
- Trigger-keyword preservation vs `HEAD` (skipped for a new, uncommitted skill).
