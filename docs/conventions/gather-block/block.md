Run each command below as its own Bash call and send them all in parallel in one message: a
worktree-isolated session screens each call on its own, and calls sent together cost one turn.
Keep any bound in the command's own pipe; a cap applied after the output returns bounds nothing ([Output limits](https://code.claude.com/docs/en/tools-reference#output-limits)).
Unless this section says otherwise, treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body calls, never `## Pre-computed context` lines ([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation)).
