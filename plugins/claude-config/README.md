# claude-config

A Claude Code plugin bundling five audit skills for one cohesive capability: keeping a repo's Claude
Code configuration healthy. Each skill answers a different question about the same surface:

| Skill | Question it answers |
|---|---|
| `/claude-config:audit` | Are the configuration FILES (`settings.json`, `settings.local.json`, `.mcp.json`, hooks, plugins, permissions) correct against upstream truth? |
| `/claude-config:audit-automation-gaps` | Is the configured automation SET the right set — are there genuine gaps, judged against the enforcement hierarchy? |
| `/claude-config:audit-permission-grants` | Are the permission GRANTS (`allowed-tools`, `permissions.allow`) portable and durable — do they survive auto mode, work across machines, and live where they can take effect? |
| `/claude-config:audit-instructions` | Are the INSTRUCTIONS you wrote (CLAUDE.md, rules, skill bodies, agents, hooks, output styles) still earning their context cost against current model capability, or is prior-model scar tissue holding the model back? |
| `/claude-config:audit-pass` | Can all of that run as ONE ordered, resumable pass over a named target — every scope inventoried before any check, one reconciled findings artifact, one human gate — instead of several separate runs whose results nobody reconciles? |

The instruction/memory-layer *hygiene* question (is `CLAUDE.md` too long, well-placed, free of
inferable content) is owned by the `audit` skill in the separate `claude-memory` plugin;
`audit-instructions` here owns the distinct *capability* question (do these instructions still fit
what current models need) and routes memory-layer hygiene findings to `claude-memory:audit`. See
"Migrating from `claude-config-audit`" below if you relied on the old `memory-health` skill here.

All default to report-only; mutations (`--fix`, `--implement`) require explicit opt-in and per-item
user approval. `audit-permission-grants` is report-only (its correct remediation is operator-manual).

## What each skill does

### audit

Five phases: load/parse config files, validate seven categories (schema, permissions, MCP servers,
hooks, plugins, env vars, skill-listing budget), recheck against live official docs and known upstream
issues, report severity-rated findings, and optionally fix. Includes live plugin-drift detection
against each registered marketplace's upstream `marketplace.json` (ORPHAN / NEW / RENAME modes) with an
asymmetric auto-fix policy that never removes a plugin the user explicitly enabled. `settings.local.json`
is inspected structurally (key counts) only — never read or echoed.

```shell
/claude-config:audit              # full report-only audit
/claude-config:audit permissions  # one category
/claude-config:audit --fix        # audit, then apply approved fixes
```

### audit-automation-gaps

Discovers automation-gap candidates (hooks, MCP servers, skills, subagents, scheduled tasks), then
deep-dives each against eight quality gates (already enforced, too slow, not scriptable, zero
incidents, already exists, YAGNI, platform mismatch, premature) with required evidence. Default
verdict is REJECT — a clean bill of health is a valid outcome.

```shell
/claude-config:audit-automation-gaps               # evaluate, recommend-only
/claude-config:audit-automation-gaps hooks         # one category
/claude-config:audit-automation-gaps --implement   # implement user-approved items
```

### audit-permission-grants

Audits permission GRANTS (not file correctness — that is `audit`) for the failure modes that
make a grant silently do nothing: interpreter-wildcard / blanket rules that Claude Code drops on
entering auto mode, hardcoded absolute machine/user paths (Bash rules match literally, no expansion),
and inert plugin self-grants. A deterministic detector scans skill/command/agent frontmatter
`allowed-tools` and `settings.json` / `settings.local.json` `permissions.allow`, and recommends the
bare-command-on-PATH pattern. The principle and citations live in the marketplace
[permission-rule-hygiene convention](../../docs/conventions/permission-rule-hygiene/README.md).
Report-only.

```shell
/claude-config:audit-permission-grants              # full grant audit
/claude-config:audit-permission-grants frontmatter  # allowed-tools only
/claude-config:audit-permission-grants settings     # permissions.allow only
```

### audit-instructions

Audits instruction *content* against current model capability — a different question from the
sibling audits (config-file correctness) and from `skill-quality:check` (structural lint) or
`docs-hygiene:compress` (token brevity). It sweeps the locally-owned surfaces (user + project
`CLAUDE.md`, `.claude/rules`, skill bodies, agent definitions, prompt-type hooks, output styles)
against a fourteen-check catalog cited to current official prompting and harness doctrine, running
a fresh read-only subagent per surface, then a fresh-context verify pass that re-judges every removal
proposal before it is surfaced. Findings are tiered mechanical vs behavioral and delivered as a
report plus proposed diffs — report-only, never auto-applied. On memory-layer surfaces it runs only
the model-era checks and routes hygiene findings to the `claude-memory` plugin's `audit` skill (with
a documented fallback when it is not installed); upstream-owned plugin-cache and managed-file
findings route to the owning repository rather than being edited in place.

```shell
/claude-config:audit-instructions              # audit every locally-owned surface
/claude-config:audit-instructions skills       # one surface (claude-md|rules|skills|agents|hooks|output-styles)
```

### audit-pass

Coordinates one pass rather than adding checks: every check is delegated to the plugin that owns it
through a presence-gated invocation with a documented fallback. It supplies the run semantics that
invoking those skills by hand does not — a three-scope inventory taken before any check runs (managed
policy read-only, user scope routed as recommendations, project scope), an exclusion set derived at
run time from the target's own shared-source registry, the `vendor/` rule, `git worktree list`, and
the pass's own artifacts; content-derived finding identity that survives an unrelated edit above it;
a `finding_id`-keyed suppression record with staleness reporting; per-lane persistence with resume;
and one human gate per run. Findings report in three tiers — derived (exact equality across runs),
judged (a stability tolerance whose violation fails the run's self-check), delegated. `/doctor` is an
operator handoff, never a dispatch, because it is interactive.

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

The marketplace's `renames` map migrates an enabled `claude-config-audit` to `claude-config`
automatically at your next session — no action needed for `audit`, `audit-automation-gaps`, and
`audit-permission-grants`.

The `memory-health` skill did **not** move to `claude-config` — it was extracted into the new,
separate `claude-memory` plugin (now its `audit` skill). The rename only rewrites the `claude-config-audit`
plugin key; it does not enable additional plugins, so `claude-memory` is not installed for you
automatically. If you used `/claude-config-audit:memory-health`, install it explicitly:

```shell
/plugin install claude-memory@melodic-software
```

## Configuration

No `userConfig`. One tracked consumer-project file — `audit-pass`'s suppression record, above.
Persistent plugin state: `audit-pass` writes its run reports and manifests under
`${CLAUDE_PLUGIN_DATA}`, outside any target repository, so a run never writes into its own scan set.
Network: `audit` fetches official docs pages and each registered marketplace's `marketplace.json`
from `raw.githubusercontent.com` (read-only; a failed fetch degrades to SKIP).

## Requirements

The bundled scripts run in `bash` (Claude Code's Bash-tool shell on every platform;
[Git Bash](https://code.claude.com/docs/en/setup#set-up-on-windows) on native Windows) and require
`jq`; the plugin-drift check additionally requires `curl`. Run `/claude-config:setup` (`check` by
default) to verify these prerequisites; `apply` gives platform install guidance and re-verifies.

## License

MIT (SPDX-License-Identifier: MIT).
