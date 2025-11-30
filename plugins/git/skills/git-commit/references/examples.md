# Git Commit Examples

This document provides concrete examples of common Git commit scenarios following Conventional Commits specification with required Claude Code attribution.

## Example 1: Simple Feature Addition

```bash
# After completing feature work
git add src/components/UserProfile.tsx

git commit -m "$(cat <<'EOF'
feat(components): add user profile avatar display

Displays user avatar with fallback to initials when image unavailable.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Example 2: Bug Fix with Scope

```bash
git add src/utils/dateFormatter.ts tests/dateFormatter.test.ts

git commit -m "$(cat <<'EOF'
fix(utils): resolve timezone handling in date formatter

Fixes incorrect timezone conversion for dates before 1970 by using
UTC epoch calculation instead of local timezone offset.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Example 3: Breaking Change

```bash
git add src/api/v2/

git commit -m "$(cat <<'EOF'
feat(api)!: redesign authentication API response format

BREAKING CHANGE: Auth response now returns `accessToken` and `refreshToken`
as separate fields instead of single `token` field. Clients must update
to handle new response structure.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Example 4: Documentation Only

```bash
git add README.md docs/installation.md

git commit -m "$(cat <<'EOF'
docs: update installation instructions for Windows

Adds Windows-specific setup steps and troubleshooting guidance.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Example 5: Multiple File Refactor

```bash
git add src/services/ src/components/

git commit -m "$(cat <<'EOF'
refactor(services): extract API client to shared service

Consolidates duplicate API client logic into single shared service
to improve maintainability and reduce code duplication.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Key Patterns to Follow

- **Always use HEREDOC format**: `$(cat <<'EOF' ... EOF)` ensures proper formatting
- **Include attribution footer**: Required for all Claude Code commits
- **Use imperative mood**: "add feature" not "added feature"
- **Focus on WHY**: Explain intent and reason, not just the change
- **Be concise**: 1-2 sentences in body if needed

---

**Last Verified:** 2025-11-25
**Related**: conventional-commits-spec.md, workflow-steps.md
