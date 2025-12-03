# Git Commit Troubleshooting

This document provides solutions to common issues encountered during Git commit operations.

## Issue: Commit fails with "gpg failed to sign the data"

**Cause**: GPG signing is required but key is not configured or passphrase cache expired

**Solution**:

1. Use the `git:gpg-signing` skill for complete setup and troubleshooting
2. Verify GPG key configured: `git config user.signingkey`
3. Check GPG agent running: `gpg-agent --daemon`
4. Test signing: `echo "test" | gpg --clearsign`

**NEVER use `--no-gpg-sign` to bypass** - Fix the underlying issue instead.

## Issue: Pre-commit hook fails repeatedly

**Cause**: Code doesn't meet automated quality checks (linting, formatting, tests)

**Solution**:

1. Read hook error output carefully
2. Fix the underlying issues (linting errors, test failures)
3. Stage fixed files: `git add .`
4. Retry commit
5. If hook modifies files, follow the hook handling procedure in [hook-handling.md](hook-handling.md)

**NEVER use `--no-verify` to bypass** - Fix the issues instead.

## Issue: Uncertain about commit type

**Cause**: Change doesn't clearly fit one category

**Solution**:

- **Added new functionality?** → `feat`
- **Fixed a bug?** → `fix`
- **Only changed docs?** → `docs`
- **Reformatted code (no logic change)?** → `style`
- **Restructured without changing behavior?** → `refactor`
- **Improved performance?** → `perf`
- **Updated dependencies/configs?** → `chore`

When in doubt, use `chore` or `refactor` as safe defaults.

## Issue: Nothing to commit

**Cause**: Working tree is clean - all changes already committed or no modifications exist

**Solution**:

The skill detects this in Step 2 and exits gracefully with message:
"Working tree is clean - nothing to commit."

This is normal and expected - no commit needed.

**Do NOT create empty commits** with `--allow-empty` unless explicitly required for CI/CD triggers.

## Issue: Mixed staging state (some files staged, others not)

**Cause**: User has partially staged files and is uncertain what to commit

**Solution**:

The skill will detect this scenario (Scenario D) and ask for clarification using AskUserQuestion:

**Options:**

1. "Commit only the staged files" → Proceed with staged files only
2. "Stage and commit everything" → `git add -u` then commit all

See the main workflow in SKILL.md for details on how this is handled.

## Issue: Amend safety check failed

**Cause**: Attempting to amend a commit that was authored by someone else or has already been pushed

**Solution**:

Create a new commit instead of amending:

```bash
git add .
git commit -m "$(cat <<'EOF'
chore: apply automated linting fixes

Pre-commit hooks applied automatic formatting changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**NEVER amend commits that:**

- Were authored by someone else
- Have already been pushed to remote
- Are not the most recent commit on the branch

See [hook-handling.md](hook-handling.md) for complete amend safety protocol.

---

**Last Verified:** 2025-11-25
**Related**: hook-handling.md, safety-protocol.md
