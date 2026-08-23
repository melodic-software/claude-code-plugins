# Worktree `audit` — configuration health checks and findings presentation

Full detail for the `/source-control:worktree audit` action. SKILL.md carries the headline plus Step 1 (run `status` internally); this file carries the Step 2 configuration-health checklist and the Step 3 findings presentation.

Periodic health check for worktree infrastructure. Suitable as a recurring item in your work-item tracker.

## Step 2: Check configuration health

| Check | How | Expected |
|-------|-----|----------|
| `delete_branch_on_merge` | `gh api repos/{owner}/{repo} --jq '.delete_branch_on_merge'` | `true` recommended — remote branches auto-delete on merge, so cleanup only handles local branches |
| Worktree root convention | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-root-doctor.sh" --repo-dir <repo>` | Exit 0 — the doctor makes the `melodic.worktreeroot` / `includeIf` silent-failure classes loud (misfiring conditions, missing include files, parse-order shadowing, a root inside a repository) and names which rule supplied this repository's root; report each `warn:`/`error:` line as a finding. Convention: `reference/worktree-root-convention.md` |
| Gitignored-file propagation | Check whether a `.worktreeinclude` file exists at the repo root | Optional — suggest when the project keeps local secrets/config in gitignored files (e.g. `.claude/settings.local.json`); Claude Code copies matching gitignored files into new worktrees |
| Project worktree hooks | If the project registers `WorktreeCreate` / SessionStart setup hooks in its settings, confirm they are present as its docs expect | Per project convention — skip when the project has none |
| Stale metadata | `git worktree list --porcelain` shows no `prunable` entries | Clean — otherwise suggest `git worktree prune` via `/source-control:worktree cleanup` |
| Orphaned plugin install records | `claude plugin list --json`, project-scope records grouped by `projectPath` (see below) | Zero records naming a path under the resolved worktree root that is no longer a registered worktree |

## Step 2b: Orphaned project-scope plugin install records

`cleanup` reaps these at teardown, but only for a teardown it performs. Every worktree removed
before that step existed left its records behind, and they are unreachable by any hook that did not
exist when they were created — on this convention's own author machine, 108 project-scope records
across 8 marketplaces, all naming one worktree directory that is long gone. Audit is where they
become visible.

**Read-only. This step reports; it never removes a record.** That is the whole boundary: a
project-scope record for a live repository on an unmounted network share or a detached external
volume is indistinguishable from a dead worktree to a bare existence check, so nothing here may act
on path non-resolution.

Collect (enumeration is cwd-independent — measured, [fixtures/README.md](../fixtures/README.md)
§ `project-scope-reap-probe.sh`):

```bash
claude plugin list --json | jq -r '
  (if type=="object" then (.installed // .plugins // []) else . end)
  | map(select(.scope=="project"))
  | group_by(.projectPath)
  | map({path: .[0].projectPath, count: length, marketplaces: ([.[].id | split("@")[1]] | unique)})
  | .[] | [.path, (.count|tostring), (.marketplaces|join(","))] | join("\t")' | tr -d '\r'
```

Classify each path into exactly one of three buckets, and never merge them:

| Bucket | Test | Reported as |
|---|---|---|
| **live** | the path is in this repository's `git worktree list` | not a finding |
| **orphaned worktree records** | the path is under the worktree root the doctor resolved above, **and** is not a registered worktree | a finding, with the remedy below |
| **other project records** | anything else | listed for information only, explicitly labelled *not this plugin's lifecycle*, with **no remedy offered** |

The third bucket exists because this plugin owns worktree lifecycle and nothing more. A record for
some other project's checkout may be perfectly current — including one whose volume simply is not
mounted right now — and this skill has no standing to judge it. Report the count; stop there.

**The remedy, emitted for the user to run, never inline.** Removing a record requires standing in
the directory it names (`-s project` has no path flag), so the only route to a path that no longer
exists is to recreate it. That is a deliberate act, not something an audit performs:

```bash
# For a path in the "orphaned worktree records" bucket ONLY, after confirming
# it is genuinely a dead worktree and not an unmounted volume:
mkdir -p "<path>"
cd "<path>" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/reap-project-plugin-records.sh" --worktree-path "<path>"
# then remove what the uninstall itself created, and the directory:
rm -rf "<path>/.claude" && cd .. && rmdir "<path>"
```

Run it `--dry-run` first to see what it would remove. The helper refuses unless the directory it is
standing in is the one named, and it never touches `installed_plugins.json` directly.

## Step 3: Present findings

```markdown
## Worktree Audit

### Infrastructure
| Check | Status |
|-------|--------|
| delete_branch_on_merge | OK (enabled) |
| Worktree root convention | OK (melodic.worktreeroot supplied by includeIf "gitdir/i:~/work/") |
| .worktreeinclude | SUGGEST — gitignored local settings exist but no .worktreeinclude |
| Stale metadata | OK (none prunable) |
| Orphaned plugin install records | 108 records across 8 marketplaces, 1 dead worktree path (0 other project paths) |

### Worktree Health
- 3 worktrees total
- 1 stranded (4 commits at risk) — push before any cleanup
- 0 unproven (Work axis unavailable)
- 0 in-progress — cleanup refuses (sequencer / conflict state dies with the directory)
- 0 dirty — cleanup refuses (uncommitted edits, or status unreadable)
- 1 stale (> 14 days, no PR) — consider `/source-control:worktree cleanup`
- 0 prunable

### Recommendations
- Push the stranded worktree's branch: `git -C <path> push -u origin HEAD`
- Create `.worktreeinclude` with your local-settings pattern for automatic propagation
- Run `/source-control:worktree cleanup` to remove the stale worktree
- 108 plugin install records name `<dead-worktree-path>`, a path under your worktree root that is no
  longer a worktree. `cleanup` reaps these at teardown; these predate that step. Removing them needs
  the directory recreated — the commands are in Step 2b, and they are yours to run, not the audit's.
```

Stranded and unproven counts lead the health list and are reported even when zero — a class that only appears when non-zero cannot be distinguished from one that was never measured, and "the Work axis could not be computed" is exactly the answer an audit must not swallow. `in-progress` and `dirty` follow them for the same reason: both are classes `/worktree cleanup` refuses to act on, and `in-progress` is invisible to `git status --porcelain`, so nothing else in the audit surfaces it unless named here.
