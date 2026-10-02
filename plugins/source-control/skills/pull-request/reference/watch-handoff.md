# Who watches the pull request

Once a PR is out of draft, CI and the review lanes start posting, and something has to answer them.
Choose who does at the end of `ready` (2.5.5) and again at `monitor` entry when no choice was made.
The facts each route rests on (who can start it, what it needs, what it cannot see) are recorded in
[native-surfaces.md](native-surfaces.md); this file holds the decision.

## Ask one question

"Are you staying in this session, leaving with this machine left on, or leaving with it off?"
When the person already said (for example "I'm heading out"), use that and do not ask. An
unattended run asks nothing, starts nothing, and records the matrix row it would pick in its output.

## The matrix

| Situation | Route | Who starts it |
|---|---|---|
| Staying | `/source-control:pull-request monitor <N>` in this session | The model, now |
| Leaving, machine stays on | `/session-flow:continue-in-background` seeded with `monitor <N>`, a fresh background agent under this skill's full monitor discipline | The model, only on the person's explicit yes |
| Leaving, machine stays on, wants this conversation to continue | `/background` detaches this whole session | The person types it |
| Leaving, machine may go off | `/autofix-pr` with the prompt below, from a terminal on the PR's branch | The person types it |
| Several open PRs, not just this one | `/source-control:babysit-loop <owner/repo>` under `/loop` | The person, or the model on request |

Recommend the first row that fits and say why in one line. A local route keeps this skill's
discipline: research-gated CI fixes and a classified reply before every fix. `/autofix-pr` fixes
what it judges clear, so the prompt below carries that discipline to it in words.

## Hand over `/autofix-pr` ready to paste

The model never runs it; it prints it filled in. Give the person:

1. The checkout to run it from: the worktree path, or `gh pr checkout <N>`. It finds the PR from
   the current branch.
2. The command, with `<N>` and the project line filled:

   ```text
   /autofix-pr Watch PR #<N>. For each review comment, verify its claim against the code first and
   reply in its thread with your verdict, valid or incorrect, and the evidence; change code only for
   a valid finding. For a CI failure, read the failing job's log and fix the root cause; never
   retry, skip or weaken a check or a test. Never merge, force-push, rewrite history, or resolve a
   thread a human opened. <project rule>
   ```

   `<project rule>` is the one convention from the repository's `AGENTS.md` or `CLAUDE.md` a fix is
   most likely to break (for example, commit subjects and the PR title stay Conventional Commits); drop
   the slot when there is none.
3. Its preconditions and limits, each from its native-surfaces row: the Claude GitHub App on the
   repository, cloud-session access, replies posted under the person's own account, no reaction to
   a merge conflict (when the base moves, run `/source-control:pull-request ready` again, which
   merges it), and comment-triggered automation its replies can set off.

When the person also keeps `monitor` running here, both push to one branch; the Mutation gate in
[SKILL.md](../SKILL.md) covers that.
