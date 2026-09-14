# PR body contract

`ci-status` is the single required check on every pull request. It fails on a
title that is not Conventional Commits and on a `do-not-merge` label. A body
missing the closing keyword or a section does NOT turn it red: the gate leaves
an advisory comment and the `needs-issue-linkage` label instead. The body
contract below is still expected on every pull request; it is reported, not
gating.

Every pull request body:

- Opens with a native closing-keyword line: `Closes #<issue>` (`Fixes`/`Resolves`
  also accepted, one keyword per issue), or, when the PR closes nothing, the
  literal `No related issue: <reason>`.
- Carries a non-empty section for each of `## Summary`, `## Fix`,
  `## Verification`, and `## Related`.

Draft the body to this contract BEFORE creating the PR (`gh pr create`, MCP, or
web); the advisory comment and label are noise this rule exists to prevent.

The canonical machine-readable convention is
`components/pr-convention-policy/policy.json` in `melodic-software/standards`;
the SHA-pinned ci-workflows `pr-contract` composite that runs as a step inside
`ci-status` is the enforcement authority, and its step output is the statement
of record.
