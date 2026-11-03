# WIP commit: refusal checks, staging and record

Read this once `wip_commit` resolves `true` for a handoff that qualifies ("WIP commit on an
explicit pause" in `SKILL.md`).

**Refuse, commit nothing, and say why in the save-point** when any of these holds. Read each
from git, one command per call:

- A sequencer operation is in progress: `git rev-parse --git-path <name>` names an existing path
  for `MERGE_HEAD`, `REBASE_HEAD`, `CHERRY_PICK_HEAD` or `REVERT_HEAD`, or for the `rebase-merge`
  or `rebase-apply` directory. A commit now would conclude that operation under a pause subject.
- HEAD is detached: `git symbolic-ref -q HEAD` prints nothing.
- HEAD is the default branch: `git symbolic-ref refs/remotes/origin/HEAD` names the same branch
  as HEAD. When that command fails (no origin HEAD), the default branch is unknown: refuse.
- A path is partially staged: it appears in both `git diff --cached --name-only -z` and
  `git diff --name-only -z`. The unstaged hunks are a choice the user made; staging them undoes it.
- A path outside this work holds staged changes. A commit takes the whole index, so it would
  carry that path along.

**Otherwise commit.** The paths are the tracked files this work changed, the ones the save-point's
"File roles in this work" section names. Paths are data: never type one into a command line.
Write the list NUL-separated to a file with the Write tool, check each entry against
`git diff --name-only -z` output, and stage with
`git add -u --pathspec-from-file=<list> --pathspec-file-nul`, which never picks up an untracked
file. A tracked file changed outside this work stays out of the commit, and the save-point lists it
as left uncommitted. Commit with the subject `chore(wip): <one-line state of the work>` and the
repository's usual body and trailer rules, with every commit hook running. When a hook rejects the
commit, do not retry it with hooks skipped and do not reword it to get past the hook: unstage the
paths this step staged (`git restore --staged --pathspec-from-file=<list> --pathspec-file-nul`, the
list holding only the paths that had no staged change before), leave the work in the working tree,
and state the hook's message in the save-point. Never push.

**Record it.** Put the commit SHA and subject under "Side effects already applied", or the refusal
and its reason there instead, and list every untracked path under "File roles in this work",
since the commit left them out. On the prompt-only path, which writes no file, the same facts go
into the resume prompt as one bullet.
