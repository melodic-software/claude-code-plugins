# PR activity event log: melodic-software/claude-code-plugins#10630

Subscribed at 2026-10-28T08:19:46Z. subscribe_pr_activity returned:

> Subscribed to activity on melodic-software/claude-code-plugins#10630. Comments, CI status changes, reviews, and other PR events will now be delivered into this conversation as <wake reason="external-event"><event source="github" …> envelopes.

Format: receipt time (UTC) | event type | payload top-level keys | delivery (woke idle session, or seen at next turn)

## Events

- 2026-10-28T08:20:10Z | subscription.created | pr | woke idle session (queued-notification wake; server queued-at 2026-10-28T08:19:44Z)
- 2026-10-28T08:29:45Z | check_run.completed | check, check_run_id, conclusion, details_url, head_sha, pr | woke idle session (queued-notification wake; server queued-at 2026-10-28T08:26:42Z, reached session ~2s before read)
- 2026-10-28T08:39:18Z | pull_request_review.submitted | author, author_association, author_type, comment, pr, review_id, state | woke idle session (queued-notification wake; server queued-at 2026-10-28T08:38:59Z, reached session ~2s before read)

Note: the check_run head_sha (bbe0690…) is not the last commit this session pushed (2af09ea2), so the host's push happened, but no push/synchronize event was delivered for it.
