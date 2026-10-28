# PR activity event log: melodic-software/claude-code-plugins#10630

Subscribed at 2026-10-28T08:19:46Z. subscribe_pr_activity returned:

> Subscribed to activity on melodic-software/claude-code-plugins#10630. Comments, CI status changes, reviews, and other PR events will now be delivered into this conversation as <wake reason="external-event"><event source="github" …> envelopes.

Format: receipt time (UTC) | event type | payload top-level keys | delivery (woke idle session, or seen at next turn)

## Events

- 2026-10-28T08:20:10Z | subscription.created | pr | woke idle session (queued-notification wake; server queued-at 2026-10-28T08:19:44Z)
- 2026-10-28T08:29:45Z | check_run.completed | check, check_run_id, conclusion, details_url, head_sha, pr | woke idle session (queued-notification wake; server queued-at 2026-10-28T08:26:42Z, reached session ~2s before read)
- 2026-10-28T08:39:18Z | pull_request_review.submitted | author, author_association, author_type, comment, pr, review_id, state | woke idle session (queued-notification wake; server queued-at 2026-10-28T08:38:59Z, reached session ~2s before read)

Note: the check_run head_sha (bbe0690…) is not the last commit this session pushed (2af09ea2), so the host's push happened, but no push/synchronize event was delivered for it.

## Final summary (written 2026-10-28T09:00:24Z)

Subscribe call return value (exact):

> Subscribed to activity on melodic-software/claude-code-plugins#10630. Comments, CI status changes, reviews, and other PR events will now be delivered into this conversation as <wake reason="external-event"><event source="github" …> envelopes.

Events received since subscribing (3), each one woke the idle session through a queued notification; none showed up only with the end-of-probe message:

| Receipt (UTC) | Event type | Top-level payload keys | Delivery |
|---|---|---|---|
| 2026-10-28T08:20:10Z | subscription.created | pr | woke idle session |
| 2026-10-28T08:29:45Z | check_run.completed | check, check_run_id, conclusion, details_url, head_sha, pr | woke idle session |
| 2026-10-28T08:39:18Z | pull_request_review.submitted | author, author_association, author_type, comment, pr, review_id, state | woke idle session |

No event arrived for the host's push to the branch itself; only the check run on the new head (bbe0690…) was delivered.
No further events arrived with the end-of-probe message.

Unsubscribe call return value (exact):

> Unsubscribed from activity on melodic-software/claude-code-plugins#10630. Webhook events for this PR will no longer be delivered.
