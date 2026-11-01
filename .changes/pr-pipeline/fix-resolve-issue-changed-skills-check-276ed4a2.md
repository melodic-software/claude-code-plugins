---
bump: patch
---

### Fixed

- A work-resolve-issue run now runs CI's changed-skills gate before its pull request opens: `resolve-issue` lists `scripts/check-changed-skills.sh --merge-base` in its `checks`, so the skill runs it, fixes what it reports and runs it again, and the run-checks job stops a run that still fails it. The new mode diffs the checkout against origin's default branch (else `HEAD`), counts untracked files, and runs the base copy of skill-quality's `check-skill.sh` with each skill's script tests and markdownlint skipped, so it runs no checkout code. Lane pull requests that added or changed a skill used to open red on `changed-skills`.
