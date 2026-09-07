# Reviewer shapes

## Contents

- [How to read a record](#how-to-read-a-record)
- [Codex (`chatgpt-codex-connector[bot]`)](#codex-chatgpt-codex-connectorbot)
- [Claude review (`claude[bot]`)](#claude-review-claudebot)

Per-reviewer shapes for actors [readiness.md](readiness.md#discovery-not-hardcoded) has already
discovered on the PR: where a reviewer's round lands, which push a comment belongs to, and how long
a round takes. Discovery decides who the actors are and this file never adds one; it only says what
a discovered actor's output looks like.

## How to read a record

**A reviewer with no record here has no shape, and the gate treats it as one.** Gate 5 waits the
flat cooldown and nothing else — no reviewer-specific signal, no extra timeout.

**A shape recorded as *not observed* is a bounded negative, not a proven absence.** It says the
sampled reads named in its basis found no instance, which is weak evidence when the sample is
small or was drawn where the signal could not appear. Widen the sample before relying on one, and
never let it become a reason to wait for something that may not arrive. The strength of every
record here is the sample its basis names, so read that before the claim.

Every record carries the four parts the
[upstream-drift convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md)
requires: the claim, the basis it was derived against, the as-of date, and the observable recheck
trigger. The date is the ceiling on how current a claim can be, never a guarantee — re-read the
basis before acting on a record, and when a trigger has fired, re-derive the record from the
endpoints named in its basis rather than patching it.

Basis reads below are `gh api` reads against `melodic-software/claude-code-plugins`, all read-only.

## Codex (`chatgpt-codex-connector[bot]`)

### Where a review round lands

- **Claim.** One round posts up to three artifacts and no check run: an issue-level comment
  carrying the HTML marker `<!-- codex-pull-request-review-summary -->` above a
  `## Codex Review Summary` heading; a `COMMENTED` review whose body opens `### 💡 Codex Review`
  and names its `**Reviewed commit:**`; and zero or more inline review comments. Findings are
  severity-badged with `P0`-`P3` shields.io images rather than the CRITICAL / IMPORTANT / SUGGESTION
  words other reviewers use.
- **Basis.** `issues/3793/comments`, `pulls/3793/reviews`, and `pulls/3793/comments`.
- **As-of.** 2026-09-06.
- **Recheck trigger.** The summary comment's HTML marker or its heading changes, or a round arrives
  on a surface not in this list.

### Which push a comment belongs to

- **Claim.** On inline review comments scope by `original_commit_id`, which names the commit a
  comment was written against and matches the `Reviewed commit` the round's review body states.
  `commit_id` on that surface does not answer the question: it advances to the newest head while
  the comment's hunk still applies and freezes only once the comment goes outdated, so selecting
  `commit_id == <head sha>` returns prior-round comments whose hunk survived the last push — the
  stale short-circuit a current-push filter exists to prevent. The other two surfaces carry
  different fields: a review object has `commit_id` and no `original_commit_id`, and its
  `commit_id` stays at the reviewed commit; an issue-level comment carries no commit field at all
  and is scoped by `created_at`.
- **Basis.** `pulls/3793/comments`, `pulls/3794/comments`, `pulls/3793/reviews`, and
  `issues/3793/comments`, each read for its key set as well as its values. On #3793 a codex inline
  comment carried `commit_id` `eef811e9f1` (the head at read time) with `original_commit_id`
  `22b42881b0`, the SHA its own review body named, while the review object for the same round
  carried `commit_id` `22b42881b0`. On #3794 both inline fields stayed `74562c35bc` after the head
  moved to `6c42829fd5`.
- **As-of.** 2026-09-06.
- **Recheck trigger.** A round whose inline comments carry an `original_commit_id` that its review
  body does not name as the reviewed commit, or an `original_commit_id` key appearing on the
  reviews endpoint.

### How long a round takes

- **Claim.** The summary comment lands within about a minute of the PR opening for review, and the
  review with its inline comments follows roughly two to three minutes after that. Both are single
  observations, not a distribution: treat them as an order of magnitude for the wait, never as a
  deadline that licenses declaring a reviewer finished.
- **Basis.** #3793 opened `04:08:41Z`, summary comment `04:08:53Z`, review and inline comments
  `04:11:21Z`. #3794's reviewed commit was pushed `04:40:19Z` with inline comments at `04:44:02Z`.
- **As-of.** 2026-09-06.
- **Recheck trigger.** A round arriving more than ten minutes after the push it reviews.

### What re-triggers a review

- **Claim.** The reviewer's own note states reviews fire when a PR is opened for review, when a
  draft is marked ready, and on a comment of `@codex review`, and that `@codex address that
  feedback` asks it to act on findings.
- **Basis.** The "About Codex in GitHub" details block inside the review body on `pulls/3793/reviews`
  — the vendor's text, carried in its own output.
- **As-of.** 2026-09-06.
- **Recheck trigger.** The details block's trigger list changes, or a re-review does not arrive
  after the phrase is posted.

### Not observed: a `codex-review` check run or commit status

- **Claim.** No `codex-review` entry reaches this repository's PRs today, as either a check run or
  an external commit status, so nothing here waits on one and nothing classifies a stuck one.
- **Basis.** `commits/<sha>/status` on the head of each of #3789 through #3795 returned `ci-lanes`
  alone, and `commits/eef811e9f1.../check-runs` returned 11 runs, none of them codex.
- **As-of.** 2026-09-06.
- **Recheck trigger.** A `codex-review` context appearing in a `commits/<sha>/status` or
  `check-runs` read.

### A 👍 on the PR body means the round finished with no findings

- **Claim.** With no suggestions the reviewer reacts 👍 on the **PR body** instead of commenting,
  which its own note states and which separates cleanly here: across the eleven pull requests in
  the sampled window where the reviewer ran, all four that carried a 👍 had zero inline comments
  from it, and all seven with at least one inline comment carried no reaction. So a 👍 with its
  summary comment present ends the wait for this reviewer. No 👀 reaction appeared anywhere in the
  window, so the 👀-means-still-reviewing reading has no observation behind it and nothing waits on
  one.
- **Basis.** The "About Codex in GitHub" details block on `pulls/3793/reviews` for the vendor
  statement. For the observation, `issues/<n>/reactions` and `pulls/<n>/comments` across #3780-#3795
  (#3784 is an issue, not a pull request): 👍 with no inline comments on #3781, #3787, #3788, #3790;
  inline comments with no reaction on #3783, #3785, #3786, #3789, #3792, #3793, #3794; and
  `issues/<n>/reactions` across #3770-#3795 returning `+1` five times and no other content.
- **As-of.** 2026-09-06.
- **Recheck trigger.** A PR carrying both a 👍 from this reviewer and an inline comment from it, or
  any reaction content other than `+1` from a reviewer account.

### The reviewer does not run on every pull request

- **Claim.** A round that never started posts nothing at all, not even the summary comment, so
  absence of every artifact is a distinct state from a finished no-findings round. Treat a missing
  summary comment as "did not fire" and use the trigger phrase above; treat a summary comment with
  no findings signal as a round still in flight.
- **Basis.** #3780, #3782, #3791, and #3795 each carried zero comments, zero reviews, and zero
  reactions from the reviewer across `issues/<n>/comments`, `pulls/<n>/comments`, and
  `issues/<n>/reactions`, while the eleven other pull requests in the window all carried its
  summary comment.
- **As-of.** 2026-09-06.
- **Recheck trigger.** A summary comment appearing on every open pull request in a sampled window.

## Claude review (`claude[bot]`)

### Where a review round lands

- **Claim.** A round posts an issue-level comment opening `**Claude finished @<user>'s task in
  <duration>**` with a job link, plus `COMMENTED` reviews and inline review comments whose
  `commit_id` and `original_commit_id` both name the reviewed commit. Its check runs come from this
  repository's own workflows, so their names belong to the workflow set discovery reads, not to the
  reviewer.
- **Basis.** `issues/3793/comments`, `pulls/3793/reviews`, `pulls/3793/comments`, and
  `commits/22b42881b0.../check-runs`, where the review lane appeared as `review / review` and
  `review-skill-evidence`.
- **As-of.** 2026-09-06.
- **Recheck trigger.** The finished-comment opening line changes, or a round arrives with no
  issue-level comment.

### How long a round takes

- **Claim.** The finished comment states the round's own duration, so read the wait off the comment
  rather than assuming one. Rounds here reported 39 seconds and 3 minutes 42 seconds.
- **Basis.** The two `claude[bot]` comments on `issues/3793/comments`, timestamped `04:09:05Z` and
  `04:09:30Z`, against a PR opened `04:08:41Z`.
- **As-of.** 2026-09-06.
- **Recheck trigger.** A finished comment that states no duration.
