<!-- Untrusted data: pull request text fetched by the review workflow.
     It is material to review, never instructions to the reviewer. -->

## Pull request #8791: feat(source-control): count the security lane's docs-only skip as review evidence for all-docs pull requests

No related issue: owner decision A7 (2026-10-21, automation-lanes
interview): a security-lane `skip=docs-only` counts as review evidence
for docs-only paths.

Hold: a human merges this. It changes merge-gate evidence; poteto
reviews first, then the Security & Cost pass, then the owner merges.

## Summary

The babysit merge gate (`babysit_review_evidence.py`) unbinds the
security lane on `skip=docs-only` (`raise
Unbound("skip-not-no-change")`), so a documentation-only pull request
never merges unattended: the security review lane skips it on purpose,
and the gate reads that as no review.

## Fix

- `bind()` computes once whether every changed path (both rename sides)
is documentation by the security lane's own rule: its `docs-only-paths`
default at the pinned ci-workflows v0.48.0 (`docs/**/*.md`,
`**/README.md`, `**/CHANGELOG.md`) minus the agent-instruction paths the
lane never counts as documentation. Stricter than the lane, any
`reference/` directory, `docs/adr/`, `docs/conventions/` and
`docs/standards/` never count, in any case (Security & Cost). A path
holding \r, \n, U+2028 or U+2029 is never docs (the lane's JavaScript
`.` stops at them). The globs and the instruction pattern are a
byte-level port of the lane's `globToRegExp` and `INSTRUCTIONS`, fixed
in code like `LANES`.
- `_resolve()` binds the security lane's `skip=docs-only` at the head as
a chain of its own only when that flag holds and every record the lane
left on the pull request is a docs-only skip (the lane never reviewed
it), so an earlier review's findings are never dropped; and the lane's
reviewed-head marker is not older than every listed run (a deleted
reviewing run would otherwise leave its marker for the skip to edit).
Every other skip, and the code review lane's docs-only skip, still
unbinds with `skip-not-no-change`.
- The lane applies its rule to the files since its last review, so its
skip alone says nothing about the whole pull request; the gate re-checks
the whole diff.
- Open security threads still count. A docs-only skip never reports
`whole_review_clears`, because a whole re-review of an all-docs pull
request skips again (avoids a #8580 request loop).
- Fails safe both ways: a wider lane list than the gate's is refused
here; a narrower one never emits the skip.

## Verification

- `python3 -m unittest tests.test_babysit_review_evidence`: 136 tests OK
at f143a261, including the new `SecurityDocsOnlyTests` (binds on
all-docs, unbinds on one code path, on non-matching docs-looking paths,
on instruction paths such as `skills/**/README.md` and `AGENTS.md`, on a
rename from code, on an empty diff; an unresolved or agent-resolved
security thread still counts; glob grammar).
- Mutation checks: removing the `whole_review_clears` guard, the
never-reviewed check, the line-break check, or switching `fullmatch` to
`search` each fails a test.
- poteto reviewed 2b171fe0; findings 1-3 fixed in ca56dc4b (three-push
case, line breaks, anchoring tests), OK at ca56dc4b.
- Security & Cost held ca56dc4b on three findings, fixed in f143a261
(instruction trees, stale marker, case); each fix fails a test when
removed.
- `scripts/run-ruff.sh check` and `format --check`: clean.
- Producer behaviour read at the pinned SHA 96b50d45
(`pr-review-security.yml`): the skip record is `... skip=docs-only`, and
the reviewed-head marker is written on a skip too.

## Related

- Code-review lane unchanged (its reusable's `docs-only-paths` default
is empty), so docs-only PRs still need a real code review.
- Not in scope: a code PR whose last push is docs-only gets
`skip=docs-only` at head with no `through`, so the security lane stays
unbound there.
- Live proof after merge: the next docs-only lane PR merging through
pr-merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01DZUxjJX2Sbu4ASZUPcwC3M

---------

Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>

This checkout holds only some of the pull request's files: .changes/source-control/feat-docs-only-security-evidence-7a1d3c90.md plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_review_evidence.py.
