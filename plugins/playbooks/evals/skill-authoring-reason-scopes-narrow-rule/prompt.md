/playbooks:skill-authoring. Rewrite this section of my skill's SKILL.md so it meets our skill criteria. Print only the rewritten section in your reply; do not write any file.

## Rules

- Commit with `--no-verify`.
- Regenerate the lockfile in step 4 with `pnpm install --lockfile-only` and commit it.

Author's note, not part of the section: only the lockfile commit in step 4 needs --no-verify, because the pre-commit hook times out on the 40,000-line generated lockfile. Every other commit must run the hooks.
