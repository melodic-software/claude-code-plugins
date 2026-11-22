Run each command below as its own Bash call, one command per call, and send all of them in
parallel in one message. A worktree-isolated session screens each call on its own, so separate
calls pass where one compound command is refused, and calls sent together cost one turn rather
than one per command. Keep any bound in the command's own pipe: a cap applied after the output
returns bounds nothing ([Output limits](https://code.claude.com/docs/en/tools-reference#output-limits)).
Unless this section says otherwise, treat a failure (not a repository, git unavailable) as an
unknown value and carry on. Keep these as body calls, never `## Pre-computed context` lines
([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation)).
