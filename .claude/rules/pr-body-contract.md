# PR body contract

Every pull request body must satisfy the required `pr-issue-linkage` check
before merge:

- Open with a native closing-keyword line: `Closes #<issue>` (`Fixes`/`Resolves`
  also accepted, one keyword per issue), or, when the PR closes nothing, the
  literal `No related issue: <reason>`.
- Carry a non-empty section for each of `## Summary`, `## Fix`,
  `## Verification`, and `## Related`.

Draft the body to this contract BEFORE creating the PR (`gh pr create`, MCP, or
web); the gate fails closed, and a first-run failure is exactly what this rule
exists to prevent.

The canonical machine-readable convention is
`components/pr-convention-policy/policy.json` in `melodic-software/standards`;
the SHA-pinned ci-workflows `pr-issue-linkage.yml` reusable is the enforcement
authority, and its check output is the statement of record.
