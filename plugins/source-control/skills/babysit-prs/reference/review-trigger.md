# AI Review Trigger

A generic, bot-agnostic module for summoning an external AI reviewer with a trigger comment and
reading its engagement gate. Four configuration slots drive it — `<review-trigger-phrase>` (the
exact comment body that summons the reviewer), `<review-bot-logins>` (the reviewer's GitHub App
login or logins), `<review-gate-context>` (the commit-status context that reports reviewer
engagement), and `<ci-gateway-context>` (the aggregate CI gateway context, where the repo has
one). Slots are filled from the effective-configuration block in this skill's `SKILL.md`, which
renders every key's resolved value and its unset fallback; `<state-dir>` is the
`state/babysit-prs` subdirectory of the plugin data directory.

**All four slots are absent by default, and this module is dormant until they are configured:**
no trigger comments are ever posted, the engagement gate is treated as absent (the snapshot
degrades to `gate_state == "absent"` and never reports a pending-engagement blocker), and nothing
else in this file activates. Configure the slots only for repositories that actually wire such a
reviewer.

## Engagement Gate Semantics

GitHub check runs and commit statuses are distinct typed records. Normalize them by `__typename`:

- `CheckRun`: use `status` and `conclusion`.
- `StatusContext`: use `state`.

Never discard a pending or failed `StatusContext` because a same-name `CheckRun` succeeded. In
repositories wiring a comment-driven review gate, a successful CheckRun of that name usually
means only that the gate workflow ran. The separate `<review-gate-context>` StatusContext is the
engagement signal: `PENDING` means no qualifying reviewer activity was found after the gate's
polling window, while `SUCCESS` can reflect activity from an earlier head. A failing gate is not an
engagement signal: it is never a trigger candidate, and reaches the operator through the ordinary
failing-check blocker rather than through an automatic trigger comment.

Therefore, keep both records. Verify completion only from a submitted review or inline review
comment whose own commit ID equals the current head SHA and whose author carries an exact login
from `<review-bot-logins>` AND is a bot — by the authoritative GitHub `Bot` type, or because the
operator declared that login in `<extra-bot-logins>`, the standing seam for an automation account
GitHub types as a `User`. Both halves are required, so declaring an account a bot never promotes
it to reviewer, and with `<extra-bot-logins>` unset the rule is the authoritative type alone.
Fetch those records through the paginated GitHub review APIs; a successful status, or an
undeclared human account with a reviewer-like login, is not evidence that the reviewer reviewed
the current head.

Reactions do not carry a commit SHA and persist across pushes. An eyes reaction on this run's
durable trigger comment means the reviewer is engaged while that comment's recorded head remains
current, but it is not completion; continue waiting for a commit-scoped review. A PR-level,
arbitrary-comment, or thumbs-up reaction may suppress another automatic request, but must remain
unverified and must not be treated as current-head approval.

## Requesting A Review

Only the orchestrator may post the trigger comment, and posting is terminal for that PR's cycle:
after posting, defer the PR until a later snapshot. Use the guarded helper rather than posting
directly:

```text
python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/request_review.py" --pr owner/repo#42 --expected-head-sha <expected-head-sha> --trigger-phrase <review-trigger-phrase> --review-bot-logins <review-bot-logins> --extra-bot-logins <extra-bot-logins> --lease-token <worker-token> --state-dir <state-dir> --apply
```

The helper requires all of these conditions:

- a non-draft, non-behind, stable current head SHA;
- an owned, unarchived base with `mutation_policy.review_trigger_allowed`;
- the PR-scoped worker lease held by the orchestrator;
- the explicit pending engagement signal — `<review-gate-context>` pending while no
  current-head review from the configured reviewer exists — observed in two consecutive
  snapshots at least three minutes apart. This confirmation window is the generic anti-flap
  rule: a status flapping through an asynchronous recompute never triggers a post;
- every other observed check terminal and nonfailing, including a green `<ci-gateway-context>`
  where one is configured;
- no durable request or attempt record for the current head SHA, including close/reopen or
  head-cycle history;
- no current-head review from `<review-bot-logins>`, no reviewer reaction signal, and no
  branch-refresh attempt for that head;
- no blocking or unresolved human feedback in durable state or the immediate pre-request
  recheck.

The helper serializes state, rechecks immediately before and after posting, and persists a
write-ahead attempt plus confirmed comment history. GitHub's issue-comment API has no atomic
head-SHA precondition, so a push or another trigger can still race the POST. The helper rescans
trigger commands immediately before posting and rechecks the head after posting; ambiguous
outcomes require user review instead of retrying. Treat any unattributed trigger-phrase comment,
including one with extra guidance, the same way. Never repost for a SHA with any durable attempt
— strictly one shot per head. If the reviewer does not engage after that one request, report it
rather than retrying. A genuinely new head SHA starts a new observation window unless its SHA
already exists in history.
