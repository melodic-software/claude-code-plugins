# babysit-prs orchestration on GitHub

This file serves the babysit-prs
[orchestration spoke](../../../../skills/babysit-prs/reference/orchestration.md): it holds the
GitHub commands and CLI facts for the operations that spoke names. The spoke owns every contract,
check and refusal around them. The [GitHub provider reference](../README.md) indexes the other
operations, and the [safety provider file](safety.md#a-cli-merge-the-queue-took) holds the CLI
merge.

## Read the true PR head

- A conflict worker in its assigned worktree: `gh pr view --json headRefOid`.
- The orchestrator, whose working directory is never reliably the target repository:
  `GH_REPO=<owner>/<repo> gh pr view <N> --json headRefOid`, or the equivalent
  `--repo <owner>/<repo>` spelling.

## Re-acquire a cross-repo head

A cross-repo head is re-acquired with `gh pr checkout`, or with a fetch from the validated fork
remote.

## Remote target for gh calls

`GH_REPO=owner/repo` selects the *remote* repository only. `gh help environment` scopes it to
"commands that otherwise operate on a local repository," not to the local working tree, so it is
the escape for read-only and remote-only `gh` calls (`pr view`, `pr checks`, `api`,
`pr comment`). `gh pr checkout`, whose own help reads "Check out a pull request in git", mutates
the local checkout, so it takes a same-call `cd` into the worktree instead.

## Disarm auto-merge

When `gh pr view <N> --json autoMergeRequest --jq '.autoMergeRequest // empty'` prints anything,
run `gh pr merge <N> --disable-auto`.
