# PR body contract

The `pr-contract` step inside `ci-status` fails a pull request on a
non-Conventional-Commits title or a `do-not-merge` label, and, in repositories
that enable it, on a body line that would start with the word `committer` after
the 72-column squash wrap, which breaks the squash commit's signature: reword
that line. The body contract is advisory, reported by comment and the
`needs-issue-linkage` label, but expected: open with `Closes #<issue>` (or
`Fixes`/`Resolves`), a `Refs: #<issue>` line to link without closing (never
"does not close", which still closes), or `No related issue: <reason>`, then
fill `## Summary`, `## Fix`, `## Verification`, and `## Related`. Draft from
the repo's PR template (else the `melodic-software/.github` default);
canonical record: `components/pr-convention-policy/policy.json` in
`melodic-software/standards`.
