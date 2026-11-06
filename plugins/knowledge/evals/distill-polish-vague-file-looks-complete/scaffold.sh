#!/usr/bin/env bash
# A git repo with no remote, a two-chapter text PDF, and a testing skill distilled from it
# through Phase 4: backoff.md carries the chapter's specifics; idempotency.md looks complete
# but paraphrases Chapter 2 without its header name, retention or status codes.
set -euo pipefail

git init -q
mkdir -p books skills/testing/reference
python3 -I "$(dirname "${BASH_SOURCE[0]}")/../fixtures/distill-make-pdf.py" books/field-notes-on-retries.pdf

cat > skills/testing/SKILL.md <<'EOF'
---
name: testing
description: "Retry practice from Field Notes on Retries: backoff schedules and idempotent retries."
---

# Testing

## Routing table

| Query about... | Load |
|---|---|
| Backoff delays, jitter, retry caps, attempt limits | [reference/backoff.md](reference/backoff.md) |
| Safe retries, duplicate requests, replays, idempotency keys | [reference/idempotency.md](reference/idempotency.md) |

## Quick decision guide

- "How long between retries?" → exponential backoff with full jitter, 100 ms doubling, capped at 30 s, 6 attempts.
- "Is this request safe to retry?" → only when the operation is idempotent; send a key the server can deduplicate on.
EOF

cat > skills/testing/reference/backoff.md <<'EOF'
# Backoff

Source: Field Notes on Retries, Chapter 1 (PDF page 1).

- Retry with exponential backoff and full jitter, so many clients do not retry in lockstep.
- Schedule: start at 100 ms, double each attempt, cap the delay at 30 seconds.
- Stop after 6 attempts.
EOF

cat > skills/testing/reference/idempotency.md <<'EOF'
# Idempotency

Source: Field Notes on Retries, Chapter 2 (PDF page 2).

- A retried request is safe only when the operation is idempotent.
- The client sends a unique key with each logical operation, generated once.
- The server stores the key with the first response and returns that response for a replay.
- The server rejects a replay that conflicts with the original request.
EOF

git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm "distill: phases 1-4"
