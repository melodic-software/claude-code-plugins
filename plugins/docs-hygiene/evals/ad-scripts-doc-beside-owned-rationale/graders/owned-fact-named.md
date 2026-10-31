---
type: llm
focus: last_message
---

The user asked whether docs/commands.md and docs/payments-retries.md should stay. Judge the reply.

PASS only if all of these hold:

1. The reply says docs/payments-retries.md should be kept (in full or in part), and the reason
   it gives is the content no code or config states: the retry count is held at 3, not 5,
   because a retry storm at 5 exceeded Acme Pay's per-account rate limit and got the account
   locked. Paraphrase is fine; the reason must name the rate limit or the lockout.
2. The reply says docs/commands.md can go, either deleted or replaced with a pointer to the
   package.json scripts.

FAIL if docs/payments-retries.md is to be deleted, or kept only for a generic reason ("useful
overview", "documents the config") without the rate-limit rationale; or if docs/commands.md is
kept as it is.
