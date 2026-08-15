---
description: "Audit Git/GitHub hygiene across a fleet of local repositories: find GitHub-merged local branches, merged/missing/prunable/mislinked worktree registrations, and remotes that resolve to a moved or renamed GitHub repository. Read-only and confidence-tiered; emits exact handoffs to repo-hygiene/source-control but never deletes, prunes, repairs, fetches, checks out, or rewrites. Use when: 'audit repositories', 'repo fleet hygiene', 'stale branches across repos', 'orphaned worktrees across repos', 'moved repos', 'renamed GitHub owner', 'cross-repo git cleanup report'."
user-invocable: true
argument-hint: "[--root <dir>]... [--repo <dir>]... [--config <file>] [--canonical <github.com/owner/repo=path>]... [--max-depth <1..12>]"
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/audit-fleet.sh:*)
metadata:
  workflow-stage: operator
  summary: Audit git and GitHub hygiene across all local repositories, read-only
  cadence: weekly
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
- `--project-dir <dir>`: the session's project directory, used for the project-scoped config rung
  and the no-scope fallback target.

Always pass `--project-dir "${CLAUDE_PROJECT_DIR}"`. That variable is substituted in this markdown
content and in `allowed-tools` Bash rules, but it is **not** present in the Bash tool's environment,
so the script cannot read it for itself — passing it in is what makes the project rung below
reachable at all.

If neither `--root` nor `--repo` is present, the script uses the project directory as an exact
`--repo` target — not as a discovery root, so nothing beneath it is searched. A project directory
that is not a Git working tree is therefore rejected, and the rejection names the three ways to
supply scope plus `/repo-fleet-hygiene:setup apply`; pass that guidance through rather than
re-deriving a root yourself. If no project directory resolves either, the run stops with the same
remedies rather than auditing the shell's incidental working directory. Config
resolution is the script's own ladder — do not pre-resolve or pass a probed path yourself:
explicit `--config` wins, else the script probes
`<project-dir>/.claude/repo-fleet-hygiene.conf` (project-scoped), else
`~/.claude/repo-fleet-hygiene.conf` (user-global — a machine-scoped fleet config placed there is
recorded user intent, not a guessed root). The report header names the consumed config and its
source, or states that none was consumed. Never guess a broader machine root from the current
path beyond that ladder.

Config-supplied scope is **additive** to CLI-supplied scope: a `--repo X` run still walks every
configured root. The header's `Scope:` line names each contributing rung and its entry count, so
report that line rather than assuming the arguments were the whole scope.

Before execution, reject any arguments outside this grammar. Pass every path/override as a quoted
argument; never assemble a shell fragment from config, repository, remote, or branch text.

Run exactly once:

```bash
${CLAUDE_SKILL_DIR}/scripts/audit-fleet.sh --project-dir "${CLAUDE_PROJECT_DIR}" <validated-and-quoted-arguments>
```

The script validates config with `git config --file`; it never sources or executes it.

## Evidence rules

The bundled collector is authoritative for classifications. Preserve its evidence in the report:

1. **Canonical checkout:** explicit remote-keyed override → configured remote-keyed override → the
   repository's **main worktree**, read as the first record of `git worktree list --porcelain`
   (which lists the main worktree first regardless of where it runs). `git rev-parse
   --show-toplevel` alone cannot identify a canonical checkout: inside a linked worktree it returns
   the linked root, so a sibling worktree reached first by discovery would otherwise become the
   path every handoff points at. When a supplied or discovered path resolves to a different main
   worktree, the header states the substitution on one `Resolved to main worktree:` line per
   repository, naming every path that resolved into it — relay it, because the operator named one
   path and the report is about another. The report always shows
   discovered and canonical paths. An
   override target with a missing/non-GitHub remote, or a different identity that cannot be proven to
   resolve to the same GitHub repository, stops that repository's local audit before evidence combines.
2. **GitHub identity:** read the selected fetch remote with `git remote get-url`; accept only
   `github.com/owner/repo`; query `GET /repos/{owner}/{repo}`. If returned `full_name` differs, report
   `HIGH` transfer/rename evidence and **continue** branch/worktree analysis against that resolved
   identity — a moved remote is not a reason to skip local classification or merge evidence. A
   404/403/network error is `UNKNOWN`, never "deleted" or "moved". A 404/403 on an identity listed
   in `fleet.ackUnavailable` is demoted to `ACKNOWLEDGED` — still reported, never suppressed; acks
   never touch non-404/403 failures or successful-response evidence.
3. **Merged branch:** one aliased `gh api graphql` query per repository page of local branches
   (up to 100 `headRefName` aliases per call, `first:1`, `states:[MERGED]`). GraphQL's
   `headRefName` argument is an **exact** match — never the search API's prefix-matching `head:`
   qualifier, so `feature/auth` and `feature/auth-v2` never conflate. Measured rate cost stays 1
   per call (nodeCount equals the alias count); that stays well under GitHub's documented
   500,000-node ceiling and 5,000-point/hour primary limit. This retires the REST
   `merged-pr-window-truncated` disclosure and the privacy-gated per-branch `--head` fallback:
   every non-default local branch the operator asked about is queried by exact name, including
   heads GitHub auto-deleted and a later fetch pruned. Fail closed when `gh`/GraphQL is
   unavailable — emit `github-pr-evidence-unavailable` and never infer unmerged from a missing
   row after a failed page. Identical branch names in another repository are unrelated. `HIGH`
   requires the PR `headRefOid` to equal the current local tip. Tip drift is `MEDIUM` manual
   review. Git ancestry without GitHub evidence is `LOW` and never called merged-by-PR — and
   under squash merges that ancestry predicate is near-inert, so on a squash-merging fleet
   GitHub evidence is effectively the only merge evidence.
4. **Local inventories:** parse only `git worktree list --porcelain -z` registrations and
   NUL-delimited `git for-each-ref` branch/tip records. Directory naming is
   never worktree evidence. Compare each existing registered path's actual `--git-common-dir` with
   the canonical checkout's expected common dir. A mismatch is `HIGH` evidence of an administrative
   linkage problem but **manual review only**. Missing/prunable registrations never trigger pruning.
   Linked, unlocked registrations with reliable admin emit one `MEDIUM` `worktree-status-handoff`
   per repository naming those paths — disposability (stranded / unknown / safe) is owned by
   `/source-control:worktree status`, and this collector emits no `git status`-based substitute
   verdict. If either inventory command fails or emits malformed/partial output, discard it, emit `UNKNOWN`,
   stop local branch/worktree classification, and do not count that repository as successfully
   audited; an empty/failed inventory never means no branches are attached.
5. **Protection:** current/default/worktree-attached branches are never emitted as standalone branch
   cleanup candidates. A merged worktree is routed to worktree dry-run first.

Every emitted finding kind, both confidence axes, and the merge-strategy and
`gc.worktreePruneExpire` dependencies the tiers rest on:
[reference/confidence-model.md](reference/confidence-model.md). The official Git/GitHub behaviours
this collector relies on: [reference/official-sources.md](reference/official-sources.md). The
read-only enforcement model and its threat assumptions:
[reference/security-review.md](reference/security-review.md).

## Presentation

Return the script's repository sections and finish with five grouped lists:

1. `HIGH — candidate handoffs`
2. `MEDIUM — manual review`
3. `LOW — informational only`
4. `UNKNOWN — evidence gaps`
5. `ACKNOWLEDGED — configured known-inaccessible identities` (present the group only when non-empty)

`ACKNOWLEDGED` is a prominence demotion, not a fifth confidence tier: the evidence stays exactly as
weak as the `UNKNOWN` it came from, and the finding is still reported. Never present it as stronger
evidence than an `UNKNOWN`, and never treat the group's emptiness as a clean signal.

For each candidate, keep repository, canonical path, exact branch/worktree/remote target, PR/API
evidence, and handoff. Never collapse same-named branches across repositories.

If the report has no findings, say what was actually checked and list any skipped/unknown evidence;
do not turn "no verified finding" into "fleet is clean".

## Graceful degradation

- Git missing or too old: stop before scanning and give the prerequisite error.
- Invalid config SYNTAX, invalid override, or an invalid CLI-supplied `--repo`/`--root` path: report
  the exact invalid input and stop; never silently fall back.
- No scope given and the project directory is not a Git working tree: stop, and relay the script's
  remedy block verbatim — the operator did not choose that path, so the rejection alone is not
  actionable.
- A config-sourced `fleet.repo`/`fleet.root` path that is missing or not a Git working tree degrades
  per-entry, not per-run: the entry becomes an `UNKNOWN` `stale-config-entry` finding and the rest of
  the fleet is still audited (deleting repositories right after an audit must not abort every
  subsequent run until the config is edited).
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
| `worktree-status-handoff` | Run `/source-control:worktree status` in the canonical repository (stranded-work axis); use cleanup `--dry-run` only after Work is safe. If `source-control` is not installed, name the listed worktree targets and the missing collaborator — emit no porcelain-based substitute verdict |
| `worktree-admin-mismatch` | Manual inspection; `git worktree repair` is an option only after validating which administrative directory is authoritative |
| `worktree-not-a-root` | Manual inspection of the registered path; a `git -C` probe of it describes the CONTAINING repository, so no cleanup handoff is safe until the path is resolved |
| `worktree-root-unverifiable` | Manual inspection of the registered path. Root-ness is unproven here rather than disproven — the probe itself failed — so infer nothing about the path in either direction |
| `worktree-nested-in-repository` | Recreate at an external root with `/source-control:worktree create`, then remove the nested one |
| `worktree-placement-unverifiable` | Inspect the canonical checkout; placement was not checked for any of its worktrees, so their placement is unknown rather than confirmed |
| `github-remote-moved` | Human-reviewed `git remote set-url`; this plugin never changes remotes |

This plugin remains useful if those optional collaborators are absent: the report names the local
Git/GitHub evidence and target so another tool or human can act. For `worktree-status-handoff`, when
`source-control` is missing, name the listed worktree paths and the missing collaborator and do not
invent a porcelain-based disposability substitute.

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
