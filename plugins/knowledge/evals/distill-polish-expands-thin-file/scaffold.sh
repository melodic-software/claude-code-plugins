#!/usr/bin/env bash
# A git repo with no remote, a two-chapter text PDF, and a testing skill distilled from it
# through Phase 4: backoff.md carries the chapter's specifics, idempotency.md is one thin line.
set -euo pipefail

git init -q
mkdir -p books .claude/skills/testing/reference
python3 -I "$(dirname "${BASH_SOURCE[0]}")/../fixtures/distill-make-pdf.py" books/field-notes-on-retries.pdf

cat > .claude/skills/testing/SKILL.md <<'EOF'
---
name: testing
description: "Retry practice from Field Notes on Retries: backoff schedules and idempotent retries."
---

# Testing

## Routing table

| Query about... | Load |
|---|---|
| Backoff delays, jitter, retry caps | [reference/backoff.md](reference/backoff.md) |
| Safe retries, duplicate requests, idempotency keys | [reference/idempotency.md](reference/idempotency.md) |

## Quick decision guide

- "How long between retries?" → exponential backoff with full jitter, 100 ms doubling, capped at 30 s, 6 attempts.
- "Is this request safe to retry?" → only when the operation is idempotent.
EOF

cat > .claude/skills/testing/reference/backoff.md <<'EOF'
# Backoff

Source: Field Notes on Retries, Chapter 1 (PDF page 1).

- Retry with exponential backoff and full jitter, so many clients do not retry in lockstep.
- Schedule: start at 100 ms, double each attempt, cap the delay at 30 seconds.
- Stop after 6 attempts.
EOF

cat > .claude/skills/testing/reference/idempotency.md <<'EOF'
# Idempotency

Source: Field Notes on Retries, Chapter 2 (PDF page 2).

- Make retried operations idempotent.
EOF

git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm "distill: phases 1-4"
