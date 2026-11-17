# Remove existing comments without per-deletion approval and block new ones

- Status: accepted
- Date: 2026-11-17
- Refs: owner decision of 2026-11-17, accepting the recommendation to reverse ADR 0108's
  per-deletion approval and its ruling-out of a repository-wide cleanup

## Context

[ADR 0108](0108-stop-new-comments-with-a-lint-on-added-lines-and-review-not-a-count.md) stops new
comments with a lint and a review rule, and lets existing comments leave only as files are touched,
each deletion approved by a person. It also ruled out a repository-wide cleanup. Its dry run found
546 comments the `necessary` posture deletes in the added lines of 50 merged pull requests, so the
existing stock is large, and a person approving each deletion is the step that keeps it in place:
about 195,000 comment lines cannot clear at the pace files are touched. The same dry run found no
false positive, which ADR 0108 set as the condition for moving the lint to `block`.

## Decision

1. **Existing comments are removed in bulk.** `/code-tidying:remove-comments` runs over each
   repository under the `melodic-software` and `kyle-sexton` owners at the `necessary` posture (its
   `aggressive` alias), one pull request per repository, with an explicit target so the repository
   rung's safe-mode fallback does not apply. No person approves a deletion; the pull request's review
   lanes and the criterion in decision 3 are the check. A review lane reads the reviewed repository's
   own criteria, so a repository whose review criteria lack decision 3's rule gets it in a pull
   request that merges before its removal pull request opens.
2. **The comment lint blocks.** `comment_lint` in this repository's team file
   (`docs/conventions/code-tidying.yaml`) is `block`: a commit or pull request that adds a comment
   outside the posture fails. The allow list, the off-by-default level for other repositories and
   the merge-base read in CI are unchanged from ADR 0108.
3. **Review flags a deleted decision comment.** A comment recording why one of the repository's own
   decisions was made, whose deletion leaves that reason nowhere a reader would look, is flagged at
   review ([`docs/review/comments.md`](../review/comments.md)): the reason moves to an ADR or the
   commit message, or the comment stays.

ADR 0108's decisions 1 to 3 stand. Its decision 4 stands for counting and for removal as files are
touched; its per-deletion approval is withdrawn. Its decision 5 is carried out by decision 2 here.

## Considered options

- **Keep ADR 0108 as written: removal as files are touched, each deletion approved.** Rejected: the
  approval is a recurring manual step per comment, and at the touch rate the stock stays for years.
- **Bulk removal at the `explanatory` posture.** Rejected: it keeps rationale comments the
  `necessary` posture deletes, so most of the stock stays, and the lint judges added comments at
  `necessary` already.
- **Bulk removal in safe mode only (class A, comments with zero information).** Rejected: it leaves
  every rationale and narration comment, which are most of what the lint would fail if added today.
- **Approve deletions per pull request rather than per comment.** Rejected: one approval over
  thousands of deletions reads none of them; the review lanes and the decision-comment criterion
  check the same diff without a person in the loop.

## Consequences

- A repository's comment stock drops in one pull request each, after this record merges.
- A deleted comment that held a decision's only written reason is caught at review, not by a person
  approving each line. A reason caught there costs an ADR or a commit-message line.
- Every pull request here that adds a comment outside the posture fails `CI Status` once this change
  is on the base branch; the fix is the one ADR 0108 names (delete it, move the reason into code or
  the commit message, or link the outside constraint).
- A bulk removal pull request touches many files at once, so it can conflict with open pull requests
  in the same files.

## Revisit triggers

- A false positive at `block`: a kept comment, or a line that is no comment, fails a commit.
- Review of a bulk removal finds decision comments deleted with their reason lost often enough that
  the criterion does not keep up.
