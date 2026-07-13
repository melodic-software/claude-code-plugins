# Label taxonomy

The label prefix structure consumed by every action that creates, queries, or filters work items. UNIVERSAL groups work in any repo; PROJECT-SPECIFIC groups carry the consuming repo's concrete values.

When no taxonomy enforcement is desired, actions accept any label without a prefix check. By default, actions validate labels against the groups below.

## Universal groups

These groups work in any repo and don't change per team.

| Group | Prefix | Members |
|-------|--------|---------|
| Type | `type:` | `type:feat`, `type:fix`, `type:chore`, `type:docs`, `type:refactor`, `type:test`, `type:build`, `type:perf` (Conventional Commits) |
| Priority | `priority:` | `priority:p0-critical`, `priority:p1-high`, `priority:p2-medium`, `priority:p3-low` |
| Status | `status:` | `status:needs-triage`, `status:considering`, `status:claimed`, `status:blocked`, `status:needs-info` |
| Meta | (none) | `automated`, `recurring`, `agent-ready`, `needs-human`, `good-first-issue`, `migrated`, `stale` |
| Cadence | `cadence:` | `cadence:weekly`, `cadence:biweekly`, `cadence:monthly`, `cadence:quarterly`, `cadence:semi-annual`, `cadence:annual` |

## Project-specific groups

The consuming repo defines the members of these groups to match its own architecture surface, domain categorization, and language/toolchain mix. Discover the live set from the bound adapter's label listing (for the GitHub adapter, `tools/work-item-tracker/adapters/github/README.md` — e.g. `gh label list`).

| Group | Prefix | What it encodes |
|-------|--------|-----------------|
| Area | `area:` | The repo's architecture surface (modules, apps, infrastructure lanes) |
| Category | `category:` | Domain categorization of the work (e.g. guardrails, testing, general) |
| Ecosystem | `ecosystem:` | Language/toolchain (e.g. dotnet, python, typescript, bash) |

When a project-specific group has no labels in the consuming repo, actions simply omit that group — no validation error. To adopt a group, create its labels once through the bound adapter and list the members in the consuming project's own rules if agents should prefer specific values.
