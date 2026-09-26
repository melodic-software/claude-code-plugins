# plan

Recommend what to run in this repository, let the user choose on the selection page, then create
the sweep branch, worktree, and draft PR. `S` below is `${CLAUDE_SKILL_DIR}/scripts`, `C` is
`${CLAUDE_SKILL_DIR}/catalogs/hygiene.md`, and `W` is `.work/repo-sweep/` in the repository root
(create it). Run from the repository's main checkout or any worktree of it.

## 1. Check for an existing sweep

Run `bash S/state.sh` and act on its exit code:

- 0, 12, or 13: this branch is already a sweep with an open PR. Say so and point to
  `/playbooks:repo-sweep next` (13: every step is done; point to `/source-control:pull-request
  ready`). Stop.
- 14: one open sweep exists on another branch. Show its `pr` and `branch` lines and point to
  `next`, which resumes it. Stop.
- 15: several open sweeps exist. List the `sweep <n> <branch>` lines, ask which to resume, and
  point to `next` on that branch. Stop.
- 10 or 11: no open sweep. Continue.
- Anything else: show the error and stop.

State the repo order rule once: alphabetical from `.github`, the chezmoi dotfiles source last.

## 2. Recommend

1. `bash S/history.sh C > W/recs.tsv`. A stderr warning that `gh` failed means history came from
   trailers only; say so.
2. For every entry, judge its `applies-when` (column 7 of `bash S/catalog.sh C`) against this
   repository with cheap evidence: `git ls-files`, file globs, `ls`. When it does not hold, set
   that row's recommendation in `W/recs.tsv` to `not-applicable` and the reason to the evidence
   (for example `no tracked *.test.* files`). Keep reasons to one line with no tabs.
3. For every entry with an `issue`, run `gh issue view <n> -R melodic-software/claude-code-plugins
   --json state -q .state`. `CLOSED` means the skill no longer needs its override: add
   `override removable: #<n> closed` to the reason and list it at the end of the report.
4. Resolve arguments in angle brackets (`<human-facing markdown files>`, `<eval suite paths>`,
   `<instruction roots>`, `<lane>`) to concrete values for this repository and show them. `next`
   resolves them again when the step runs.

## 3. Show and select

1. Print a table in chat with every catalog id in catalog order: id, recommendation, reason,
   default checked (`checked` column, false for `not-applicable`). Every id appears, so a
   headless run still shows the full plan.
2. `bash S/render.sh --page C W/recs.tsv > W/plan-page.html`. Give the absolute path and open it
   (`wslview`, `xdg-open`, or `open`, whichever exists; otherwise the user opens it). The page
   lets the user tick, untick, and drag entries, then copy one `repo-sweep-selection:` line.
3. Fallback when the page cannot be opened: print the output of `bash S/render.sh --checklist C
   "repo-sweep-selection: <default checked ids, comma-separated>" W/recs.tsv` and ask the user to
   edit it in chat; convert their edited list back to a selection line.
4. Wait for the selection line. Validate it with `bash S/render.sh --checklist C "<line>"
   W/recs.tsv > W/checklist.md`; exit 1 names the bad id.

## 4. Create the sweep (after user approval)

Show the checklist and the branch name, and ask for approval to create the branch, push, and
open the draft PR. Then:

1. Branch: `chore/repo-sweep-hygiene-<yyyymmdd>`. When that name exists locally or on origin
   (`git ls-remote --heads origin <name>`), append `-2`, `-3`, and so on.
2. Worktree: invoke `/source-control:worktree` via the Skill tool to create a worktree for that
   exact branch off the up-to-date default branch. If it cannot take an exact branch name, run
   `git fetch origin` and `git worktree add -b <branch> <path> origin/<default-branch>` at the
   path it would have used. All later commands run in that worktree.
3. Seed commit, since GitHub refuses a PR with no commits: `git commit --allow-empty -m
   "chore(repo-sweep): seed hygiene sweep"`, then `git push -u origin <branch>`.
4. PR body in `W/pr-body.md`, per the repository's PR body convention when it has one, else:

   ```markdown
   No related issue: repo hygiene sweep

   ## Summary

   <contents of W/checklist.md>

   ## Fix

   Runs the hygiene playbook one step per commit. Each step commit carries a `Scope decisions:`
   section and `Playbook-Step:` trailers naming the skill versions that ran.

   ## Verification

   The last step runs verification:confirm. Each step's findings were reviewed before its fix.

   ## Related

   Playbook: /playbooks:repo-sweep, catalog hygiene.
   ```

5. `gh pr create --draft --base <default-branch> --head <branch> --title "chore: repo hygiene
   sweep <yyyy-mm-dd>" --body-file W/pr-body.md`. Confirm with `gh pr view --json body -q .body |
   grep -c 'repo-sweep:begin'` printing 1.

## 5. Hand off

Print the PR URL and the worktree path, then: open a session in the worktree, `/clear` between
steps, and run `/playbooks:repo-sweep next`.
