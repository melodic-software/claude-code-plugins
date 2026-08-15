---
description: "Coordinate Git/GitHub hygiene across a cross-repository fleet: discover canonical repositories, collect and roll up cross-repository evidence (including merged remote-tracking heads still on origin), and hand an action plan to repo-hygiene/source-control, which own per-repository cleanup. The current collector is read-only and emits detailed exact handoffs; it never deletes, prunes, repairs, fetches, checks out, or rewrites. Use when: 'audit repositories', 'repo fleet hygiene', 'stale branches across repos', 'orphaned worktrees across repos', 'merged remote branches', 'moved repos', 'renamed GitHub owner', 'cross-repo git cleanup report'."
user-invocable: true
argument-hint: "[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>] [--canonical <github.com/owner/repo=path>]... [--max-depth <1..12>] [--detail] [--plan-file <path>] | --apply-plan <path>"
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/audit-fleet.sh:*)
metadata:
  workflow-stage: operator
  summary: Discover a repository fleet and coordinate read-only evidence handoffs
  cadence: weekly
---

## Purpose

Coordinate cross-repository hygiene. This skill owns bounded fleet discovery, canonical
checkout resolution, fleet-scale evidence collection, rollup, and action-plan routing. It does
**not** own per-repository cleanup decisions or execution; those belong to `repo-hygiene` and
`source-control`.

The currently shipped collector produces the detailed read-only report described below, including
the compact machine-readable rollup and action-plan artifact from
[#2608](https://github.com/melodic-software/claude-code-plugins/issues/2608) /
[#2609](https://github.com/melodic-software/claude-code-plugins/issues/2609). Execute that plan with
`/repo-fleet-hygiene:apply --plan-file <path>` (dry-run by default; `--apply` plus confirmation or
`--yes` to mutate). Do not add an execute flag to this audit script.

## Non-negotiable boundary

Never run or suggest running inline from this skill: `git fetch`, `git worktree prune`,
`git worktree repair`, `git worktree remove`, `git branch -d/-D`, `git remote set-url`, or any
filesystem deletion. The bundled script has no mutation mode — `--apply-plan` is a read-only
dry-run approval artifact over a prior plan file. A report may name a command/tool as a future
handoff; the fleet action plan lists those invocations once per repository behind one confirmation
gate. Actual fleet mutation belongs to `/repo-fleet-hygiene:apply`, not this skill.

## Input resolution

Parse `$ARGUMENTS` as opaque arguments for the bundled script. Supported flags:

- `<dir>`: a bare positional path, treated as `--root`. A drive root (`D:`, `D:/`) is a legitimate
  discovery root and normalizes to `D:/`. This is the form `/repo-fleet-hygiene:audit D:` uses.
- `--root <dir>`: bounded recursive repository discovery (repeatable).
- `--repo <dir>`: exact repository/worktree target (repeatable).
- `--config <file>`: explicit Git-format config (at most one).
- `--canonical <github.com/owner/repo=path>`: invocation-specific canonical checkout override
  (repeatable; explicit wins over config).
- `--max-depth <1..12>`: discovery bound; explicit wins over config/default `5`.
- `--project-dir <dir>`: the session's project directory, used for the project-scoped config rung.
  It is **not** a scope fallback — a run with no scope fails rather than auditing it.
- `--detail`: emit collapsed per-target evidence after the rollup (default is rollup + action plan
  only).
- `--plan-file <path>`: write the machine-readable action-plan JSON to this path (otherwise a temp
  file is created and named in the report).
- `--apply-plan <path>`: standalone read-only mode — render the ordered dry-run approval artifact
  for a previously written plan (cannot combine with discovery flags).

Always pass `--project-dir "${CLAUDE_PROJECT_DIR}"` on audit runs (not on `--apply-plan`). That
variable is substituted in this markdown content and in `allowed-tools` Bash rules, but it is
**not** present in the Bash tool's environment, so the script cannot read it for itself — passing
it in is what makes the project rung below reachable at all.

If no scope resolves — no bare path, no `--root`, no `--repo`, and no config-supplied
`fleet.root`/`fleet.repo` — the run **stops** and names the ways to supply scope plus
`/repo-fleet-hygiene:setup apply`. Pass that guidance through rather than re-deriving a root
yourself. The project directory is **not** a fallback scope: auditing the session's incidental
working directory was removed because it silently audited whatever tree the shell happened to sit
in. Config
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

Before execution, reject any arguments outside this grammar — noting that a bare positional path
**is** in the grammar, so `/repo-fleet-hygiene:audit D:` and
`/repo-fleet-hygiene:audit /path/to/tree` are valid invocations to pass through, not arguments to
refuse. What stays rejected is an unrecognized flag: anything beginning with `-` that is not listed
above. Pass every path/override as a quoted argument; never assemble a shell fragment from config,
repository, remote, or branch text.

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
   (up to `MERGED_PR_GRAPHQL_ALIAS_PAGE` `headRefName` aliases per call, `first:1`,
   `states:[MERGED]`). GraphQL's `headRefName` argument is an **exact** match — never the search
   API's prefix-matching `head:` qualifier, so `feature/auth` and `feature/auth-v2` never conflate.
   Measured rate cost stays 1 per call (nodeCount equals the alias count); that stays well under
   GitHub's documented 500,000-node ceiling and 5,000-point/hour primary limit. This retires the REST
   `merged-pr-window-truncated` disclosure and the privacy-gated per-branch `--head` fallback:
   every non-default local branch the operator asked about is queried by exact name, including
   heads GitHub auto-deleted and a later fetch pruned. Fail closed when `gh`/GraphQL is
   unavailable — emit `github-pr-evidence-unavailable` and never infer unmerged from a missing
   row after a failed page. Identical branch names in another repository are unrelated. `HIGH`
   requires the PR `headRefOid` to equal the current local tip. Tip drift is `MEDIUM` manual
   review. Git ancestry without GitHub evidence is `LOW` and never called merged-by-PR — and
   under squash merges that ancestry predicate is near-inert, so on a squash-merging fleet
   GitHub evidence is effectively the only merge evidence.
4. **Merged remote branch:** after local classification, the same merged-PR rows are matched
   against each remote-tracking tip under the selected remote. When `headRefOid` equals that tip
   and the branch is not the default, probe live existence with
   `git ls-remote --heads <remote> refs/heads/<branch>`. A matching tip → `HIGH`
   `merged-remote-branch` (remote head still present after merge — unset or blocked
   `delete_branch_on_merge`). ls-remote failure → `MEDIUM` cached observation (may be stale after a
   prune-less fetch). Empty ls-remote → no finding (head already gone upstream). Remote-only heads
   (local already deleted) are included. The handoff is an optional `git push --delete --dry-run`
   preview naming the remote and branch; this skill never runs it and never calls org-admin APIs to
   flip repository settings. Enabling `delete_branch_on_merge` is complementary (it stops the class
   accruing) and is **not** a substitute for this fleet visibility.
5. **Local inventories:** parse only `git worktree list --porcelain -z` registrations and
   NUL-delimited `git for-each-ref` branch/tip records. Directory naming is
   never worktree evidence. Compare each existing registered path's actual `--git-common-dir` with
   the canonical checkout's expected common dir. A mismatch is `HIGH` evidence of an administrative
   linkage problem but **manual review only**. Missing/prunable registrations never trigger pruning.
   Linked, unlocked registrations with reliable admin emit one `MEDIUM` `worktree-status-handoff`
   per repository naming those paths — disposability (stranded / unknown / safe) is owned by
   `/source-control:worktree status`, and this collector emits no `git status`-based substitute
   verdict. Separately, every linked worktree that passes existence and root-verifiability checks
   is classified against the configured worktree root (`melodic.worktreeroot` when present on the
   first resolvable TARGET, else source-control `worktree_root`): conforming, outside/wrong-layout
   (expected `<root>/<owner>-<repo>-<slug>` or `<root>/<repo>-<slug>` without origin, matching
   `/source-control:worktree create`; create-shaped basenames stay conforming after branch
   rename/detach; comparisons use physical paths so symlink aliases of the configured root do not
   false-positive), or tool-owned (Codex/Cursor).
   Missing, prunable, non-root, and root-unverifiable registrations keep their own finding kinds and
   are excluded from conformance denominators. When no root is configured, placement is reported
   without asserting a convention. The collector uses a single fleet-wide root (first TARGET with
   `melodic.worktreeroot`, else pluginConfigs); intentionally different per-repository `includeIf`
   roots are not modeled. If pluginConfigs cannot be read because `jq` is missing, emit
   `worktree-root-pluginconfigs-unreadable` rather than pretending the key is unset.
   Per-repository and fleet rollups always state the classifiable counts. If either inventory
   command fails or emits malformed/partial output, discard it, emit `UNKNOWN`, stop local
   branch/worktree classification, and do not count that repository as successfully audited; an
   empty/failed inventory never means no branches are attached.
6. **Protection:** current/default/worktree-attached branches are never emitted as standalone branch
   cleanup candidates. A merged worktree is routed to worktree dry-run first. `merged-remote-branch`
   is independent of local attachment — it describes the remote ref.

Every emitted finding kind, both confidence axes, and the merge-strategy and
`gc.worktreePruneExpire` dependencies the tiers rest on:
[reference/confidence-model.md](reference/confidence-model.md). The official Git/GitHub behaviours
this collector relies on: [reference/official-sources.md](reference/official-sources.md). The
read-only enforcement model and its threat assumptions:
[reference/security-review.md](reference/security-review.md).

## Presentation

Default output is screen-scale:

1. Fleet header (config, scope, discovery counts).
2. **Repository rollup** — one row per repository with `CLEAN` / `N candidates` /
   `BLOCKED (evidence gap)`, plus counts by finding kind. Fleet-level findings (stale config,
   duplicate checkouts) get their own row. A fleet verdict summarizes blocked vs candidate vs clean.
3. **Fleet action plan** — recommended skill invocations **once per repository** (not once per
   finding), ordered so branch cleanups precede worktree cleanups, behind **one** confirmation gate.
4. Path to the machine-readable action-plan JSON (and the `--apply-plan` dry-run invocation).

Pass `--detail` when the operator needs evidence: targets are collapsed (one entry per path/branch
carrying every applicable finding), never duplicated across confidence groups. Never collapse
same-named branches across repositories.

`ACKNOWLEDGED` remains a prominence demotion, not a fifth confidence tier: the evidence stays exactly
as weak as the `UNKNOWN` it came from. A rollup `CLEAN` verdict means no actionable cleanup-plan
candidates (the kinds that produce skill invocations) and no UNKNOWN evidence gap for that
repository — not "GitHub was unreachable so nothing was wrong." Manual-review HIGH/MEDIUM findings
(for example `locked-worktree` or `merged-pr-tip-drift`) remain in kind counts but do not inflate
`N candidates` when the action plan correctly lists `Actions: none`.

When acting on a fleet report, prefer `/repo-fleet-hygiene:apply --plan-file <path>` (dry-run, then
`--apply`) over driving per-repository skills by hand.

## Fleet cleanup plan

This section defines how audit relates to the execute verb; it does not add a mutation command to
the audit argument grammar.

The cleanup-plan consumer is `/repo-fleet-hygiene:apply`. It takes only the machine-readable rollup
artifact tracked by [#2608](https://github.com/melodic-software/claude-code-plugins/issues/2608).
Never parse this skill's human report into executable operations. The apply verb
([#2597](https://github.com/melodic-software/claude-code-plugins/issues/2597) /
[#2609](https://github.com/melodic-software/claude-code-plugins/issues/2609)):

1. rejects an incomplete, invalid, or non-audit artifact and preserves every repository-qualified
   target, confidence, evidence gap, and disposition;
2. owns batched merged-local-branch deletion (with fail-closed OID refresh) and worktree cleanup in
   plan order rather than widening this audit script;
3. presents one fleet action plan and obtains one explicit confirmation (or `--yes`) before any
   mutation; and
4. re-derives mutable facts, including relevant branch/worktree OIDs, at execution time. An old
   artifact is evidence, not authorization.

On this release, the rollup, `--apply-plan` dry-run, and `/repo-fleet-hygiene:apply` ship. Do not
invent `--cleanup-plan`, `--execute`, or report-and-execute behavior on `audit-fleet.sh`. Return the
report, rollup, and plan path; hand execution to `:apply`. A `HIGH` evidence tier is never itself
permission to delete a branch or worktree.

Related fleet contracts that remain separate:

- merged remote branches with a distinct safety gate:
  [#2607](https://github.com/melodic-software/claude-code-plugins/issues/2607) (reporting shipped;
  remote deletion is not part of `:apply`).

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
- A path discovered under `--root` that is unreadable or not a Git working tree (despite a `.git`
  marker) degrades the same way: an `UNKNOWN` `discovery-skip` finding, header skip counts, and the
  rest of the fleet is still audited. An explicitly named `--repo` that is not a working tree still
  hard-fails.
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
| `merged-remote-branch` | Optional preview only: `git push --delete --dry-run <remote> <branch>` in the canonical repository (never executed here). Enabling GitHub `delete_branch_on_merge` is complementary and owned by the repository's settings automation — this audit does not change it |
| `merged-worktree`, `prunable-worktree`, `missing-worktree` | Run `/source-control:worktree cleanup --dry-run` in the canonical repository |
| `worktree-status-handoff` | Run `/source-control:worktree status` in the canonical repository (stranded-work axis); use cleanup `--dry-run` only after Work is safe. If `source-control` is not installed, name the listed worktree targets and the missing collaborator — emit no porcelain-based substitute verdict |
| `worktree-admin-mismatch` | Manual inspection; `git worktree repair` is an option only after validating which administrative directory is authoritative |
| `worktree-not-a-root` | Manual inspection of the registered path; a `git -C` probe of it describes the CONTAINING repository, so no cleanup handoff is safe until the path is resolved |
| `worktree-root-unverifiable` | Manual inspection of the registered path. Root-ness is unproven here rather than disproven — the probe itself failed — so infer nothing about the path in either direction |
| `worktree-nested-in-repository` | Recreate at an external root with `/source-control:worktree create`, then remove the nested one |
| `worktree-outside-configured-root` | Recreate at the expected location named in evidence with `/source-control:worktree create`, then remove the misplaced one |
| `worktree-wrong-layout` | Recreate at the expected `<owner>-<repo>-<slug>` path under the configured root, then remove the wrong-layout one |
| `worktree-tool-owned` | Leave to Codex/Cursor lifecycle, or migrate deliberately to the configured root |
| `worktree-root-conformance` | Read the per-worktree outside/wrong-layout findings for expected paths; migrate toward the configured root |
| `worktree-root-conformance-summary` | Same as per-repository conformance; fleet-scale migration toward the configured root |
| `worktree-root-unconfigured` | Set `melodic.worktreeroot` (git config) or source-control `worktree_root`, then rerun |
| `worktree-root-pluginconfigs-unreadable` | Install `jq`, or set `melodic.worktreeroot`; do not treat the fleet as unconfigured |
| `worktree-placement-unverifiable` | Inspect the canonical checkout; placement was not checked for any of its worktrees, so their placement is unknown rather than confirmed |
| `bare-repo-with-working-tree` | Manual review. `core.bare=true` coincides with working-tree content or registered linked worktrees, so the main worktree is disabled while linked worktrees keep working. Nothing is lost; the documented remedy is `git config --local core.bare false` in the named checkout |
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
