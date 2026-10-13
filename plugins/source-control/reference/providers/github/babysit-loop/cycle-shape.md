# babysit-loop cycle shape on GitHub

This file serves the babysit-loop
[cycle-shape spoke](../../../../skills/babysit-loop/reference/cycle-shape.md): it holds the GitHub
form of the reads that spoke names. The spoke owns the rung partition and every fail-closed rule.
The [GitHub provider reference](../README.md) indexes the other operations.

## Close-linked work item

A PR's close-linked work item is GitHub's own computed close-linkage, the GraphQL
`closingIssuesReferences` field on the pull request, read with `gh api graphql`.
