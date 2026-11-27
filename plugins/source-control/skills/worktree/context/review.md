# Worktree `review`: cited verdicts for the nightly reap's review rows

`<scripts-dir>` is the scripts directory resolved in SKILL.md; substitute it before a command
reaches Bash.

The nightly reap (`<scripts-dir>/worktree-reap.sh`) keeps a worktree it cannot judge on facts alone
and marks it `review`. This action reads those rows, gathers the evidence for each, writes one cited
verdict per worktree, and resolves a row only by making its work durable: a push, or a carried file
synced back to main. It never deletes anything; removal stays with the reap and
[cleanup](cleanup.md), which re-check every guard on the next run.

## Input: the reap's run file

The reap writes one run file per run: `${XDG_STATE_HOME:-~/.local/state}/worktree-reap/runs/<utc>.jsonl`,
in the same directory as its `reap.log` (or beside the log its `--log` flag names). Its lines:

- One `{"type":"worktree",...}` line per examined worktree: `path`, `repo`, `branch`, `head`, the
  facts the reap collected (each with the script that owns it), `verdict` (`remove`, `keep` or
  `review`) and `reason`.
- One closing `{"type":"run",...}` line with run-level facts (phase wall times, bytes removed,
  memory peak).

Read the newest run file (the greatest `<utc>` name) and keep its `"type":"worktree"` lines whose
`verdict` is `review`. With no `runs/` directory or no run file, report that the reap has written no
run record yet and stop. With no `review` rows, report the run's stamp and that nothing needs review.

Skip a row whose `path` and `head` already have a verdict in an earlier review file: the facts have
not changed since someone judged it.

## Step 1: Gather evidence per row

For each `review` row, read-only:

1. **Worktree state.** `git -C <path> status --porcelain`, `git -C <path> log --oneline HEAD --not --remotes`
   (the commits no remote holds), and whether `head` still equals `git -C <path> rev-parse HEAD`. A
   moved HEAD means the run's facts are out of date: verdict `keep`, cited to the new HEAD.
2. **Pull request.** `gh pr list -R <owner>/<repo> --head <branch> --state all --json number,state,url,headRefOid,mergedAt,closedAt`
   (`<owner>/<repo>` from `git -C <repo> remote get-url origin`). Read the newest match's body and
   its closing issue (`gh pr view <n> -R <owner>/<repo> --json closingIssuesReferences`, then
   `gh issue view <issue> -R <owner>/<repo> --json state,title,url`).
3. **Carried files.** `bash "<scripts-dir>/worktree-include.sh" diff '<path>' --main-root '<repo>' --worktree-only`
   lists the carried files the worktree edited (`MODIFIED`), included files it never carried
   (`NEW`), or one `NO-MANIFEST` row.

## Step 2: Decide one verdict per row

Match the row's `reason` to one case below. A reason not listed here, or evidence that fits no case,
is `owner`.

| Reason | Evidence that settles it | Verdict |
|---|---|---|
| Stranded work (commits no remote holds) | The branch is not the default branch and HEAD is not detached | `push` |
| Stranded work, on a detached HEAD or the default branch | No branch to push without choosing one | `owner` |
| Unknown work (landedness unproven) | Re-read with `<scripts-dir>/landed-work.sh`; a definite `landed` row | `keep`, cited to the row; the next reap re-judges |
| Unknown work, still unproven | | `owner` |
| A carried file edited in the worktree (`MODIFIED`) | The edit belongs in main and `sync-back` accepts it | `sync-back` |
| A carried file edited in the worktree, main changed since the copy | `sync-back` exits 2 | `owner`: show both versions |
| `NO-MANIFEST` (no `carried.index`) | Timestamp evidence, below | `owner` until the user answers |
| A PR closed unmerged | Commits pushed and the closing issue's state read | `owner`: the user decides whether the work is abandoned |

A verdict cites what settled it: the command and the line it printed, or the PR, issue or commit URL.
A verdict with no citation is `owner`.

### `NO-MANIFEST` rows: show the timestamps first

A worktree made before `carried.index` existed has nothing to judge its carried files against. Show
the user, for each included file the worktree holds: its modification time, the worktree's creation
time (the modification time of `<path>/.git`), and the modification time of main's copy. A worktree
file not modified since the worktree was created was not edited there. Act on a `NO-MANIFEST` row
only after the user answers yes for that worktree.

## Step 3: Write the verdicts

Write one JSON line per reviewed worktree to `reviews/<utc>.jsonl` beside the run file's directory
(`${XDG_STATE_HOME:-~/.local/state}/worktree-reap/reviews/<utc>.jsonl`, with the run file's `<utc>`
so the two pair), written with the Write tool:

```json
{"path":"<path>","head":"<head>","run":"<run file name>","reason":"<row reason>","verdict":"push|sync-back|keep|owner","evidence":["<command: line>","<url>"],"action":"none|pushed|synced|declined","at":"<utc>"}
```

The next review reads these files to skip rows already judged; the user reads them to see why each
worktree is still on disk.

## Step 4: Resolve, with two actions only

Present the verdict table, then run only what the user confirms:

- `push`: `git -C <path> push -u origin HEAD`. The commits become durable; the next reap reads the
  branch as pushed.
- `sync-back`: `bash "<scripts-dir>/worktree-include.sh" sync-back '<path>' --main-root '<repo>' --copy '<relpath>'`
  for each `MODIFIED` file the user wants in main. It refuses (exit 2) a file main changed since the
  copy; record that row as `owner`.

Update the row's `action` in the review file after each. `keep` and `owner` rows take no action.
Nothing in this procedure deletes a worktree, a branch or a file.
