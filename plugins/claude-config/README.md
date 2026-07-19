# claude-config

A Claude Code plugin bundling three audit skills for one cohesive capability: keeping a repo's Claude
Code configuration healthy. Each skill answers a different question about the same surface:

| Skill | Question it answers |
|---|---|
| `/claude-config:audit` | Are the configuration FILES (`settings.json`, `settings.local.json`, `.mcp.json`, hooks, plugins, permissions) correct against upstream truth? |
| `/claude-config:audit-automation-gaps` | Is the configured automation SET the right set — are there genuine gaps, judged against the enforcement hierarchy? |
| `/claude-config:audit-permission-grants` | Are the permission GRANTS (`allowed-tools`, `permissions.allow`) portable and durable — do they survive auto mode, work across machines, and live where they can take effect? |

The instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`, auto-memory) is audited
by the `health` skill in the separate `claude-memory` plugin (see "Migrating from
`claude-config-audit`" below if you relied on the old `memory-health` skill here).

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

## Consumer conventions

The skills read the consuming repo's own `CLAUDE.md` / `.claude/rules/` for project-specific policy:
additional required permission patterns, documented reasons for disabled MCP servers, and a custom
enforcement hierarchy. Nothing project-specific is baked into the plugin.

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
separate `claude-memory` plugin (as `health`). The rename only rewrites the `claude-config-audit`
plugin key; it does not enable additional plugins, so `claude-memory` is not installed for you
automatically. If you used `/claude-config-audit:memory-health`, install it explicitly:

```shell
/plugin install claude-memory@melodic-software
```

## Configuration

No `userConfig`; no persistent plugin state. Network: `audit` fetches official docs pages and each
registered marketplace's `marketplace.json` from `raw.githubusercontent.com` (read-only; a failed
fetch degrades to SKIP).

## Requirements

The bundled scripts run in `bash` (Claude Code's Bash-tool shell on every platform;
[Git Bash](https://code.claude.com/docs/en/setup#set-up-on-windows) on native Windows) and require
`jq`; the plugin-drift check additionally requires `curl`. Run `/claude-config:setup` (`check` by
default) to verify these prerequisites; `apply` gives platform install guidance and re-verifies.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
