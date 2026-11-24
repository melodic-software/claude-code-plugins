# Stop new comments with a lint on added lines and review, not a count

- Status: accepted; Decision 4's per-deletion approval and the ruling-out of a repository-wide
  cleanup are superseded by
  [ADR 0110](0110-remove-existing-comments-without-per-deletion-approval-and-block-new-ones.md)
- Date: 2026-11-14
- Refs: [#15647](https://github.com/melodic-software/claude-code-plugins/issues/15647); owner
  decisions of 2026-11-14 (the interview and design rounds recorded on that issue)

## Context

The shipped comment posture is `necessary`: the floor plus the keep list of
`/code-tidying:remove-comments`. Agent-written code adds comments outside it faster than a cleanup
pass removes them, and the review rule ([`docs/review/comments.md`](../review/comments.md)) catches
one only after the code is written. The owner asked that new comments be stopped by a lint rule and
caught again at review, not by pull-request prep, and ruled out a repository-wide cleanup for now.

## Decision

1. **A lint judges the comment lines a change adds.** The `code-tidying` plugin ships one
   language-agnostic git-hook entry, `comment-lint`. It finds comments through the pygments token
   stream the plugin's census uses and fails an added comment that has none of the allowed shapes
   (the floor's machine-decidable items, a doc comment, and under `necessary` a note carrying a
   URL or an RFC number). It detects and never edits.
2. **It is off unless a repository turns it on.** `comment_lint` in the team file is `off`,
   `report` or `block`; `comment_lint_allow` adds patterns for a repository's own markers. Neither
   has a personal override. A CI gate reads the merge base's copy, so a branch cannot lower its own
   level.
3. **Review is the second catch.** The review rule judges added comments, an ignore marker
   included, at the local quality gate and in the pull request review lane.
4. **No count.** Nothing counts comments, per file or per repository. Existing comments leave as
   files are touched (`comment_edit_scope: files`), each deletion approved by a person.
5. **This repository starts at `report`** and moves to `block` in a follow-up change.

### Dry run (2026-11-14)

The judge ran with posture `necessary` over the added lines of the last 50 merged pull requests
that touched a code file, after a control case with one planted comment reported exactly that
line. Every finding was read. The table is the judge as merged: each run over the same 50
commits after a review change to the judge removed no finding and added none.

| Class | Test and fixture paths | Workflow files | Hook-manager config | Other | Total |
|---|---|---|---|---|---|
| A comment the posture deletes | 233 | 44 | 0 | 269 | 546 |
| An outside-constraint note with no link | 30 | 11 | 0 | 34 | 75 |
| A comment the change moved or re-indented | 0 | 0 | 0 | 10 | 10 |
| A kept comment the lint failed (false positive) | 0 | 0 | 0 | 0 | 0 |
| A line that is no comment (false positive) | 0 | 0 | 0 | 0 | 0 |
| Total | 263 | 55 | 0 | 313 | 631 |

The allow list holds two patterns, for the `test-scope:` header `scripts/affected-tests.sh` reads
in `#` and `//` files; without the second the run had 633 findings. A bare tracker reference
(`owner/repo#N`) is not a link, so a note citing only one is in the second row. The branch that
added the lint has no finding on its own lines. With no false positive, the follow-up change may
set `block`.

## Considered options

- **A per-file ratchet on the comment count.** Rejected: it fails a change for comments it did not
  add, needs a checked-in ceiling per file, and says nothing about which comment to remove.
- **A repository-wide comment ceiling.** Rejected: one number for about 195,000 comment lines moves
  on every merge, so concurrent pull requests conflict on it, and it cannot tell a kept comment
  from one the posture deletes.
- **Readers only** (the review rule and the comment pass, no check). Rejected: the owner asked for
  a lint so that an author is stopped before review, and review alone is where the comments got in.
- **A rule in each language's own linter.** Rejected: it ships language specifics the plugins
  resolve from the consumer ([ADR 0101](0101-resolve-ecosystem-specifics-from-the-consumer-repository.md)).
- **The comment-leader heuristic of the read-only audit as the detector.** Rejected: it reads
  ordinary code as comments (`${#name}`, `#include`, an unquoted URL), which a blocking check
  cannot.

## Consequences

- A change here that adds a comment outside the posture gets a finding naming the fix: delete it,
  move the reason into the code or the commit message, or link the outside constraint.
- An outside-constraint note needs its link, or `remove-comments-ignore`, to pass the lint, though
  the keep list keeps it without one. About one finding in eight in the dry run was such a note.
- A comment moved in from another file counts as added. One only re-indented or moved within its own
  file does not, so a formatter-only change passes
  ([#17178](https://github.com/melodic-software/claude-code-plugins/issues/17178)).
- The commit-time hook needs Python 3 with pygments on each machine that commits; an agent without
  it gets a failed commit, a person a notice. CI installs pygments already.
- Workflow files are judged, since the version-pin shape exists only there; the comment pass skips
  those paths by default, so a finding there is fixed by hand.

## Revisit triggers

- A false positive at `block`: a kept comment or a line that is no comment fails a commit.
- The owner asks for a repository-wide cleanup, which the comment pass already takes as an explicit
  target.
