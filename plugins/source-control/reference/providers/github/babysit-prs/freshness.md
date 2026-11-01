# babysit-prs freshness on GitHub

This file serves the babysit-prs [freshness spoke](../../../../skills/babysit-prs/reference/freshness.md):
it holds the GitHub commands for the reads that spoke names. The spoke owns the comparison rule
and every refresh invariant. The [GitHub provider reference](../README.md) indexes the other
operations.

## Single-PR diagnostic

Read the PR's merge state, base ref name and head commit, then compare the head against the base
by NAME:

```text
gh pr view 42 -R owner/repo --json mergeStateStatus,baseRefName,headRefOid
gh api "repos/owner/repo/compare/<baseRefName>...<headRefOid>" --jq "{status,ahead_by,behind_by}"
```

The spoke's verification record reproduces the same way: read `mergeStateStatus` and
`baseRefName` with `gh pr view`, then compare the same head SHA against each of the two bases with
`gh api repos/{owner}/{repo}/compare/{basehead}` and read `behind_by`.
