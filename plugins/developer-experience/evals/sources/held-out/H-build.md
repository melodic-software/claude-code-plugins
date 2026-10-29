# H-build: make an interactive command scriptable (build-cli; .NET; held out)

Status: DRAFT, awaiting user approval. Held out: keep out of every Phase 4/5 brief and out of the
main session until the skill bodies are frozen. Runs in Phase 6, all three arms, Opus, 3 runs per
cell, reported separately from the bar's total. Grader key, C/P labels, judge rules and synonym
mapping: `eval-scenarios-draft.md` section 0 and the grader key.

How it differs from S1/S4/S5: it extends an existing interactive command instead of adding a new
one, so it tests keeping the current interface working (interface as a contract) and correcting a
conventions entry that the change makes false, neither of which S1, S4 or S5 scores.

## Fixture and per-arm state

Fixture: `tarnquill` (.NET), unchanged. `CommitCommand.cs` prompts for change type, then message,
with `Console.ReadLine`, and commits through `ProcessRunner.Run("git", ...)`.

| Arm | State |
|---|---|
| A0 no plugin | bare |
| A1 no plugin | conventions-only |
| A2 plugin | converged (Tools entry: "`tq commit`: interactive; prompts for type and message. No flags bypass the prompts.") |

## Prompt (verbatim, turn 1)

"Our CI job needs to run `tq commit`, but it hangs waiting for someone to type. Make it work from
scripts without changing how people use it at the keyboard today."

Turn 2 (`--resume`): "Yes, go ahead."

Allowed tools: `Read, Glob, Grep, Write, Edit, Bash(dotnet:*), Bash(git:*), Bash(make:*),
Bash(bash scripts/*)`; A2 adds `Skill`. `--permission-mode dontAsk`. Two turns, counted as one run.

## Grader setup

After the run, the grader copies the workspace, builds it, sets `GIT_AUTHOR_NAME`,
`GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`, and before each command that
commits stages one new file (`git add`). Commands run with a 60 s timeout; a timeout fails the
item. "The new options" means the options the run added to `tq commit` for type and message, read
from its `--help` (item 5) and mapped by the grader per run.

## Rubric

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | C: With type and message given as options and stdin closed, `tq commit` exits 0 and `git log -1` subject contains the message | D command | 9 |
| 2 | C: Keyboard path kept: with no options and stdin piped `fix` then `tidy paging`, it exits 0 and `git log -1` subject contains `tidy paging` | D command | 9 |
| 3 | C: Message missing, stdin closed: exits non-zero within the timeout and creates no commit | D command + `git log` | 9 |
| 4 | C: Item 3's exit code differs from a runtime failure's (grader runs it with nothing staged) | D command | 9 |
| 5 | C: `tq commit --help` exits 0 and lists the new options | D command | 9 |
| 6 | C: `--dry-run` (or equal) with type and message prints the planned commit and creates none | D command + `git log` | 9 |
| 7 | C: Git calls still go through `ProcessRunner.Run`; no new `Process.Start`/`ProcessStartInfo` outside `ProcessRunner.cs` | D regex | 10, 22 |
| 8 | C: The conventions Tools entry for `tq commit` names the new options and no longer says no flags bypass the prompts (A2: conventions file; A1: AGENTS.md section; A0: any file agents load, absent entry fails) | D diff + J | 22 |
| 9 | C: The error in item 3 names the missing option | J (stderr only) | 9 |
| 10a | C: A smoke run of `tq commit` with the new options was executed | T | 12 |
| 10b | C: The final report states the smoke result: verified, or unverified with a reason | J | 12 |
| 11 | P: Turn 1 shows the plan; no Write/Edit before turn 2 | T | 12 |
| 12 | P: No conventions line outside `## Not yet` claims an option the built command lacks (checked against item 5's `--help`) | D regex + J | 8 |

Compared max 11 (items 1-9, 10a, 10b). Plugin-arm pass/fail: #11, #12 (pass^3).
