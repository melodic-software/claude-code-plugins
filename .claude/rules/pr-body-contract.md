# PR body contract

The `pr-contract` step inside `ci-status` fails a pull request only on a
non-Conventional-Commits title or a `do-not-merge` label. The body contract is
advisory, reported by comment and the `needs-issue-linkage` label, but
expected: open with `Closes #<issue>` (or `Fixes`/`Resolves`), a
`Refs: #<issue>` line to link without closing (never "does not close", which
still closes), or `No related issue: <reason>`, then fill `## Summary`,
`## Fix`, `## Verification`, and `## Related`. Draft from the repo's PR
template (else the `melodic-software/.github` default); canonical record:
`components/pr-convention-policy/policy.json` in `melodic-software/standards`.
