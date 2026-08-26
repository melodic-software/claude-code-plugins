# claude-config

A Claude Code plugin bundling six configuration-health skills (plus a `setup` skill) for one
cohesive capability: keeping a repo's Claude Code configuration healthy. Each skill answers a
different question about the same surface:

| Skill | Question it answers |
|---|---|
| `/claude-config:audit` | Are the configuration FILES (`settings.json`, `settings.local.json`, `.mcp.json`, hooks, plugins, permissions) correct against upstream truth? |
| `/claude-config:audit-automation-gaps` | Is the configured automation SET the right set? Are there genuine gaps, judged against the enforcement hierarchy? |
| `/claude-config:audit-permission-grants` | Are the permission GRANTS (`allowed-tools`, `permissions.allow`) portable and durable? Do they survive auto mode, work across machines, and live where they can take effect? |
| `/claude-config:audit-permission-state` | Which permission rules are actually IN EFFECT, and where does each one come from, across managed policy, user-global, project, local, and the pre-v2.1.211 start-directory copy? |
| `/claude-config:audit-instructions` | Are the INSTRUCTIONS you wrote (CLAUDE.md, rules, skill bodies, agents, hooks, output styles) still earning their context cost against current model capability, or is prior-model scar tissue holding the model back? |
| `/claude-config:audit-pass` | Can all of that run as ONE ordered, resumable pass over a named target, with every scope inventoried before any check, one reconciled findings artifact, and one human gate, instead of several separate runs whose results nobody reconciles? |
| `/claude-config:unhobble` | What does the CURRENT MODEL actually still need, measured rather than reasoned: reversibly strip the project's standing instructions to a bare baseline, log real stumbles, and re-add only what the evidence earns back? |

The instruction/memory-layer *hygiene* question (is `CLAUDE.md` too long, well-placed, free of
inferable content) is owned by the `audit` skill in the separate `claude-memory` plugin;
`audit-instructions` here owns the distinct *capability* question (do these instructions still fit
what current models need) and routes memory-layer hygiene findings to `claude-memory:audit`. See
"Migrating from `claude-config-audit`" below if you relied on the old `memory-health` skill here.

All default to report-only; mutations (`--fix`, `--implement`) require explicit opt-in and per-item
user approval. `audit-permission-grants` is report-only (its correct remediation is operator-manual).

## What each skill does

### audit

Five phases: load/parse config files, validate nine categories (schema, permissions, MCP servers,
hooks, plugins, env vars, skill-listing budget, model and effort settings, deep-link registration),
recheck against live official docs and known upstream
issues, report severity-rated findings, and optionally fix. Includes live plugin-drift detection
against each registered marketplace's upstream `marketplace.json` (ORPHAN / NEW / RENAME modes) with an
asymmetric auto-fix policy that never removes a plugin the user explicitly enabled. `settings.local.json`
is inspected structurally (key counts) only, never read or echoed.

```shell
/claude-config:audit              # full report-only audit
/claude-config:audit permissions  # one category
/claude-config:audit --fix        # audit, then apply approved fixes
```

### audit-automation-gaps

Discovers automation-gap candidates (hooks, MCP servers, skills, subagents, scheduled tasks), then
deep-dives each against eight quality gates (already enforced, too slow, not scriptable, zero
incidents, already exists, YAGNI, platform mismatch, premature) with required evidence. Default
verdict is REJECT. A clean bill of health is a valid outcome.

```shell
/claude-config:audit-automation-gaps               # evaluate, recommend-only
/claude-config:audit-automation-gaps hooks         # one category
/claude-config:audit-automation-gaps --implement   # implement user-approved items
```

### audit-permission-grants

Audits permission GRANTS (not file correctness, which is `audit`) for the failure modes that
make a grant silently do nothing: interpreter-wildcard / blanket rules that Claude Code drops on
entering auto mode, hardcoded absolute machine/user paths (Bash rules match literally, no expansion),
and inert plugin self-grants. A deterministic detector scans skill/command/agent frontmatter
`allowed-tools` and the project, local, and user-global `permissions.allow` arrays, and recommends the
bare-command-on-PATH pattern. The user-global file
(`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`) is where Claude Code's own "Always allow" path
writes, so on a long-lived machine expect it to carry most of the findings. Their remediation is
the operator's, since no skill can write that file. The principle and citations live in the marketplace
[permission-rule-hygiene convention](../../docs/conventions/permission-rule-hygiene/README.md).
Report-only.

```shell
/claude-config:audit-permission-grants              # full grant audit
/claude-config:audit-permission-grants frontmatter  # allowed-tools only
/claude-config:audit-permission-grants settings     # permissions.allow only
```

### audit-permission-state

Reports the permission state actually in effect. Claude Code exposes no `claude permissions`
subcommand and no machine-readable export, so "where is this rule coming from" has meant reading five
files in five places and hoping you knew all five. A deterministic reader discovers every settings
scope, covering managed policy, user-global, project, local, and any pre-v2.1.211 copy left in the
session's start directory, then inventories each one's `allow` / `ask` / `deny` rules with its source named.

The status vocabulary is the point: `absent` means looked and found nothing, `skipped` means could not
look. The managed scope is four surfaces per OS, not one file; the Windows policy registry keys and
the macOS managed-preferences domain are optional platform integrations that degrade visibly while the
portable core (the JSON file and its `managed-settings.d/` drop-ins) still reads. Server-managed
settings have no local path and are disclosed as invisible rather than assumed empty. Report-only:
it writes nothing in any scope, and managed policy is read-only by construction.

```shell
/claude-config:audit-permission-state           # scopes + rule inventory
/claude-config:audit-permission-state --scopes  # which scopes exist and which were readable
```

### audit-instructions

Audits instruction *content* against current model capability, a different question from the
sibling audits (config-file correctness) and from `skill-quality:check` (structural lint) or
`docs-hygiene:compress` (token brevity). It sweeps the locally-owned surfaces (user + project
`CLAUDE.md`, `.claude/rules`, skill bodies, agent definitions, hook instruction text, output styles)
against a sixteen-check catalog cited to current official prompting and harness doctrine, running
a fresh read-only subagent per surface, then a fresh-context verify pass that re-judges every removal
proposal before it is surfaced. Findings are tiered mechanical vs behavioral and delivered as a
report plus proposed diffs, report-only and never auto-applied. On memory-layer surfaces it runs only
the model-era checks and routes hygiene findings to the `claude-memory` plugin's `audit` skill (with
a documented fallback when it is not installed); upstream-owned plugin-cache and managed-file
findings route to the owning repository rather than being edited in place.

**Check I15 asks a different question with a different unit of judgment.** Do two surfaces
contradict each other? A per-surface lane sees only one half of a pair, so it is answered by its own
pass over the pair set, against `reference/conflict-criteria.md`. The `conflicts` scope runs that
pass alone, so a scheduled hygiene routine can compose it on its own token budget.

```shell
/claude-config:audit-instructions              # every locally-owned surface, plus the conflict pass
/claude-config:audit-instructions skills       # one surface (claude-md|rules|skills|agents|hooks|output-styles)
/claude-config:audit-instructions conflicts    # the cross-surface conflict pass only
/claude-config:audit-instructions --opinion    # also run the default-off OPINION-tier checks
```

### audit-pass

Coordinates one pass rather than adding checks: every check is delegated to the plugin that owns it
through a presence-gated invocation with a documented fallback. It supplies run semantics that
invoking those skills by hand does not:

- A three-scope inventory taken before any check runs: managed policy read-only, user scope routed
  as recommendations, and project scope.
- An exclusion set derived at run time from the target's own shared-source registry, the `vendor/`
  rule, `git worktree list`, and the pass's own artifacts.
- Content-derived finding identity that survives an unrelated edit above it.
- A `finding_id`-keyed suppression record with staleness reporting.
- Per-lane persistence with resume.
- One human gate per run.

Findings report in three tiers: derived (exact equality across runs),
judged (a stability tolerance whose violation fails the run's self-check), delegated. `/doctor` is an
operator handoff, never a dispatch, because it is interactive.

**The target must be a git repository**, and one that resolves to the active project root. Both halves
are refused non-zero rather than reinterpreted. The git requirement is not incidental: the state key,
the scan baseline, the worktree exclusion, and the top read-only assertion are all defined over git,
and suppression is enacted only by the *tracked* layer, so on a non-git target no suppression would
ever persist. Audit such a directory by opening it as a repository, or through the delegated skills
directly.

```shell
/claude-config:audit-pass                    # read-only pass over the current repo
/claude-config:audit-pass --opinion          # include the default-off OPINION-tier checks
/claude-config:audit-pass --resume           # resume an interrupted run
/claude-config:audit-pass --fix              # apply, per-finding confirmed, project scope only
```

The target is the active project root, and a `target` argument naming anything else is refused: the
delegated skills accept no target of their own, so a run pointed elsewhere would report that path
while every delegated finding came from the active project. Audit another repository by opening it
as the project.

### unhobble

The empirical counterpart to `audit-instructions`: instead of judging instruction *text* against
doctrine, it measures the *model* against the repo with the instructions gone. Four resumable
phases:

| Phase | What it does |
|---|---|
| `snapshot` | Inventories the live project surfaces on a dedicated experiment branch and classifies each hook as policy or behavioral |
| `bare` | Reversibly strips the behavioral tier: tracked files via git, settings entries via manifest-recorded backups. Policy gates and managed settings are never touched |
| `observe` | You work normally in fresh sessions, logging real stumbles to a ledger |
| `readd` | Restores only instructions with at least two same-cause ledger rows, each restore citing its evidence. Everything else stays deleted, with git history as the archive |

The canonical trigger
is a frontier model release. Instructions written for the previous generation are the experiment's
subject. Human-gated at every mutation; state persists under `${CLAUDE_PLUGIN_DATA}` for resume.

```shell
/claude-config:unhobble            # guided full flow
/claude-config:unhobble snapshot   # inventory + classify + strip plan
/claude-config:unhobble bare       # apply the confirmed strip plan
/claude-config:unhobble observe    # ledger instructions for the observation window
/claude-config:unhobble readd      # evidence-gated restores; close the experiment
/claude-config:unhobble status     # manifest summary: phase, ledger rows, candidates
```

## Consumer conventions

The skills read the consuming repo's own `CLAUDE.md` / `.claude/rules/` for project-specific policy:
additional required permission patterns, documented reasons for disabled MCP servers, and a custom
enforcement hierarchy. Nothing project-specific is baked into the plugin.

`audit-pass` reads one tracked consumer-project file: the suppression record at
`.claude/audit-pass.md`, layered per the marketplace's
[config-cascade](../../docs/conventions/config-cascade/README.md) contract, with its keys owned by
[finding-suppression](../../docs/conventions/finding-suppression/README.md). All layers absent is a
valid state.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install claude-config@melodic-software
```

## Migrating from `claude-config-audit`

The marketplace's `renames` map still carries a historical `claude-config-audit` →
`claude-config` entry, so settings that name the old plugin id resolve to this one at your next
session. No action is needed for `audit`, `audit-automation-gaps`, and `audit-permission-grants`.
That entry is a migration aid for consumers who predate the rename, not the marketplace's
go-forward mechanism: the map is frozen-historical and later renames ship as clean breaking
changes (see the [migration playbook](../../docs/MIGRATION-PLAYBOOK.md#version-pinning-and-update-delivery)).

The `memory-health` skill did **not** move to `claude-config`. It was extracted into the new,
separate `claude-memory` plugin (now its `audit` skill). The rename only rewrites the `claude-config-audit`
plugin key; it does not enable additional plugins, so `claude-memory` is not installed for you
automatically. If you used `/claude-config-audit:memory-health`, install it explicitly:

```shell
/plugin install claude-memory@melodic-software
```

## Configuration

No `userConfig`. One tracked consumer-project file, `audit-pass`'s suppression record, above.
Persistent plugin state: `audit-pass` writes its run reports and manifests under
`${CLAUDE_PLUGIN_DATA}`, which resolves under `~`, outside a target below the home directory and
inside one at or above it. A run never *scans* what it wrote: where the resolved report path is
contained in the target, the run excludes that path before writing and says so.
Network: `audit` fetches official docs pages and each registered marketplace's `marketplace.json`
from `raw.githubusercontent.com` (read-only; a failed fetch degrades to SKIP).

## Requirements

The bundled scripts run in `bash` (Claude Code's Bash-tool shell on every platform;
[Git Bash](https://code.claude.com/docs/en/setup#set-up-on-windows) on native Windows). The
JSON-parsing scripts require `jq`; the plugin-drift check additionally requires `curl`; and `awk`
and `sort` are required across three skills, not one: `audit`'s plugin-drift check (both) and its
fix (`sort`), `audit-permission-grants`' rule check (both), and `audit-instructions`' conflict pass
(both). Only the conflict pass probes for them and `exit 2`s naming the one that is missing; the
others call them unguarded, so an absent `awk` or `sort` surfaces there as a bare `command not
found` partway through a run. Both ship with every POSIX userland, so a missing one means a minimal
shell environment (Git Bash, a `busybox` shim) rather than an absent package. Install a full
userland (Git for Windows; `gawk`/`mawk` plus `coreutils` on Linux; `brew install gawk coreutils`
on macOS). Run `/claude-config:setup` (`check` by default) to verify these prerequisites; `apply`
gives platform install guidance and re-verifies.

## License

MIT (SPDX-License-Identifier: MIT).
