# Action: `check-all`

**Usage:** `/claude-ops:known-issues check-all`

Check every registry issue against current GitHub status. Primary purpose: find issues RESOLVED since last check — unblocked work needing follow-up.

## Batch backend and its scratch directory

`scripts/check-all.sh` re-checks every row in one pass. Its scratch directory is **keyed by project and is not guessable**, so ask the script for it rather than composing a path:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/known-issues/scripts/check-all.sh" --print-output-dir
```

Write `registry-snapshot.tsv` (`number<TAB>repo<TAB>tracked_status`) into the directory it names, run the script with no arguments, then read `check-all-results.tsv` back from that same directory. The key is `lib/state-key.sh`'s `<repo-identity>/<worktree-discriminator>` under [`docs/conventions/plugin-data-report-keying/`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-data-report-keying/README.md) rule 1: the registry is project-relative whenever `registry_dir` is set, so an unkeyed scratch directory hands one project the other's rows.

Files sitting directly under `check-all-output/` are unkeyed leftovers from the older layout. The script names them on stderr. Offer them to the operator as deletable; do not read them.

## Process

1. Read `registry.json`
2. For each tracked issue, check current status via `gh issue view <number> --repo <repo> --json state,title,closedAt,stateReason`
3. Compare current state to tracked state
4. For newly resolved issues:
   - Update `registry.json`: `--status closed --closedAt <GitHub closedAt>` and re-categorize
     to `--category fixed` (`fixed` is a category; `status` only accepts `open`/`closed`)
   - Identify what was blocked (from `blocked_work` field)
   - Identify what docs need updating (from `affected_files` field)
   - Propose a follow-up work item for each action (file with the consumer's tracker — e.g. `gh issue create` — after user confirmation):
     - "Update `<affected_file>` — issue #NNNNN (`<title>`) is now resolved. Remove workaround, update documentation, and implement/enable the previously blocked feature."
   - Present summary of what changed

## Output format

```markdown
## Registry Check: N issues checked

### Newly Resolved (action needed)

| # | Title | Resolved | Blocked Work | Follow-Up |
|---|-------|----------|--------------|-----------|
| #NNNNN | Title | Date | What was blocked | follow-up item filed |

### Still Open

| # | Title | Category | Last Checked |
|---|-------|----------|--------------|
| #NNNNN | Title | blocking | YYYY-MM-DD |

### No Change

N issues unchanged since last check.
```
