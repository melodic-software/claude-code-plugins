---
name: audit
description: "Audit Git/GitHub hygiene across a fleet of local repositories: find GitHub-merged local branches, merged/missing/prunable/mislinked worktree registrations, and remotes that resolve to a moved or renamed GitHub repository. Read-only and confidence-tiered; emits exact handoffs to repo-hygiene/source-control but never deletes, prunes, repairs, fetches, checks out, or rewrites. Use when: 'audit repositories', 'repo fleet hygiene', 'stale branches across repos', 'orphaned worktrees across repos', 'moved repos', 'renamed GitHub owner', 'cross-repo git cleanup report'."
user-invocable: true
argument-hint: "[--root <dir>]... [--repo <dir>]... [--config <file>] [--canonical <github.com/owner/repo=path>]..."
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-fleet.sh *)
---

## Purpose

Produce one read-only fleet report. This skill owns cross-repository discovery, evidence collection,
classification, and routing. It does **not** own cleanup execution.

## Non-negotiable boundary

Never run or suggest running inline from this skill: `git fetch`, `git worktree prune`,
`git worktree repair`, `git worktree remove`, `git branch -d/-D`, `git remote set-url`, or any
filesystem deletion. The bundled script has no mutation mode. A report may name a command/tool as a
future handoff, but the receiving per-repository tool or human owns its preview and confirmation gate.

## Input resolution

Parse `$ARGUMENTS` as opaque arguments for the bundled script. Supported flags:

- `--root <dir>`: bounded recursive repository discovery (repeatable).
- `--repo <dir>`: exact repository/worktree target (repeatable).
- `--config <file>`: explicit Git-format config (at most one).
- `--canonical <github.com/owner/repo=path>`: invocation-specific canonical checkout override
  (repeatable; explicit wins over config).
- `--max-depth <1..12>`: discovery bound; explicit wins over config/default `5`.

If neither `--root` nor `--repo` is present, the script uses `${CLAUDE_PROJECT_DIR}`. Config
resolution is the script's own ladder — do not pre-resolve or pass a probed path yourself:
explicit `--config` wins, else the script probes
`${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf` (project-scoped), else
`~/.claude/repo-fleet-hygiene.conf` (user-global — a machine-scoped fleet config placed there is
recorded user intent, not a guessed root). The report header names the consumed config and its
source, or states that none was consumed. Never guess a broader machine root from the current
path beyond that ladder.

Before execution, reject any arguments outside this grammar. Pass every path/override as a quoted
argument; never assemble a shell fragment from config, repository, remote, or branch text.

Run exactly once:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-fleet.sh" <validated-and-quoted-arguments>
```

The script validates config with `git config --file`; it never sources or executes it.

## Evidence rules

The bundled collector is authoritative for classifications. Preserve its evidence in the report:

1. **Canonical checkout:** explicit remote-keyed override → configured remote-keyed override →
   `git rev-parse --show-toplevel`. The report always shows discovered and canonical paths. An
   override target with a missing/non-GitHub remote, or a different identity that cannot be proven to
   resolve to the same GitHub repository, stops that repository's local audit before evidence combines.
2. **GitHub identity:** read the selected fetch remote with `git remote get-url`; accept only
   `github.com/owner/repo`; query `GET /repos/{owner}/{repo}`. If returned `full_name` differs, report
   `HIGH` transfer/rename evidence. A 404/403/network error is `UNKNOWN`, never "deleted" or "moved".
3. **Merged branch:** query `gh pr list --repo <this-repo> --state merged --head <this-branch>` for
   each local branch in each repository. Identical branch names in another repository are unrelated.
   `HIGH` requires the PR `headRefOid` to equal the current local tip. Tip drift is `MEDIUM` manual
   review. Git ancestry without GitHub evidence is `LOW` and never called merged-by-PR.
4. **Local inventories:** parse only `git worktree list --porcelain -z` registrations and
   NUL-delimited `git for-each-ref` branch/tip records. Directory naming is
   never worktree evidence. Compare each existing registered path's actual `--git-common-dir` with
   the canonical checkout's expected common dir. A mismatch is `HIGH` evidence of an administrative
   linkage problem but **manual review only**. Missing/prunable registrations never trigger pruning.
   If either inventory command fails or emits malformed/partial output, discard it, emit `UNKNOWN`,
   stop local branch/worktree classification, and do not count that repository as successfully
   audited; an empty/failed inventory never means no branches are attached.
5. **Protection:** current/default/worktree-attached branches are never emitted as standalone branch
   cleanup candidates. A merged worktree is routed to worktree dry-run first.

Full tier/disposition table: [reference/confidence-model.md](reference/confidence-model.md).

## Presentation

Return the script's repository sections and finish with four grouped lists:

1. `HIGH — candidate handoffs`
2. `MEDIUM — manual review`
3. `LOW — informational only`
4. `UNKNOWN — evidence gaps`

For each candidate, keep repository, canonical path, exact branch/worktree/remote target, PR/API
evidence, and handoff. Never collapse same-named branches across repositories.

If the report has no findings, say what was actually checked and list any skipped/unknown evidence;
do not turn "no verified finding" into "fleet is clean".

## Graceful degradation

- Git missing or too old: stop before scanning and give the prerequisite error.
- Invalid config/override/path: report the exact invalid input and stop; never silently fall back.
- `gh` missing/unauthenticated or API/timeout failure: continue Git/worktree checks, report GitHub
  evidence as `UNKNOWN`, and make no merged/migration claim. Compatible `timeout`/`gtimeout` is
  preferred; otherwise use the collector's finite TERM-to-KILL Bash watchdog.
- Non-GitHub or ambiguous remote: continue local checks; GitHub identity/PR evidence is `UNKNOWN`.
- Canonical override is missing a GitHub remote or does not resolve to the same normalized GitHub
  identity as the discovered repo: surface `UNKNOWN`, stop that repository, and do not merge evidence.
- Worktree porcelain fails: surface `UNKNOWN` and stop local branch/worktree classification for that
  repository so no branch can be mislabeled unattached.
- Branch enumeration fails or is malformed: discard every partial record, surface `UNKNOWN`, stop
  branch classification, and exclude the repository from the successful-audit count.

## Integration

| Finding | Handoff (not executed here) |
|---|---|
| `merged-local-branch` | Run `/repo-hygiene:clean git` in the named canonical repository |
| `merged-worktree`, `prunable-worktree`, `missing-worktree` | Run `/source-control:worktree cleanup --dry-run` in the canonical repository |
| `worktree-admin-mismatch` | Manual inspection; `git worktree repair` is an option only after validating which administrative directory is authoritative |
| `github-remote-moved` | Human-reviewed `git remote set-url`; this plugin never changes remotes |

This plugin remains useful if those optional collaborators are absent: the report names the local
Git/GitHub evidence and target so another tool or human can act.

## Gotchas

- **Which config is consumed depends on where the audit runs.** Config resolution follows the ladder in
  the Input resolution section: explicit `--config`, else the project-scoped
  `.claude/repo-fleet-hygiene.conf`, else the user-global one. A project-scoped config is invisible when
  the audit runs from a different project, so confirm the consumed config named in the report header
  before trusting a run's scope.
- **Config paths resolve relative to the config file's directory.** A relative `root`/`repo`/canonical
  path is anchored at the config directory, not the audit's working directory. Absolute paths work but
  are what a consumer's write-time path guard flags, so author config via
  `/repo-fleet-hygiene:setup apply`, which prefers the portable relative form.
