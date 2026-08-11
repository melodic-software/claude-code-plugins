# audit — Phase 2 validation categories

Detailed checks for each Phase 2 category (A–I). SKILL.md Phase 2 names the categories + points here;
this file carries the per-check criteria. Run each category's checks and record findings with severity
ratings.

Load the audit checklist alongside these: [audit-checklist.md](../reference/audit-checklist.md).

## Category A: Schema & Structure

- `$schema` present and points to `https://json.schemastore.org/claude-code-settings.json`
- No unknown top-level keys (cross-reference against official docs schema)
- `settings.local.json` does NOT contain `mcpServers` (wrong file — use `.mcp.json`)

## Category B: Permissions

- **Baseline permission patterns**: iterate the patterns in
  [required-permissions.md](../reference/required-permissions.md) — each pattern in
  `sensitive-file-deny` and `destructive-bash-deny` must appear in `settings.json` `permissions.deny`;
  each pattern in `ask-rules` must appear in `settings.json` `permissions.ask`. When the consuming
  repo's own rules declare additional required patterns, check those too
- **Before flagging an absent baseline pattern, apply the narrowings** in
  [required-permissions.md](../reference/required-permissions.md) "Narrowing the baseline" — a
  documented repo exemption, a documented project hook convention, or a **live** `PreToolUse` hook that
  already blocks that family on the tool surface the pattern defends (that third case is `info` with
  the residual named, not `error`). Read the three preconditions there before downgrading: installed
  and enabled is not enough, a `Bash` hook does not cover a `Read`-pattern family, and coverage of one
  command family says nothing about a neighbouring one. Where no hook inventory was taken, state the
  finding as conditional rather than as an assertion
- **The liveness reading is Category D's, and Category D runs after this one.** A–I is presentation
  order, not a dependency ban: pull Category D's hook-suppression lever reading forward before taking
  the third narrowing, or defer the downgrade until Category D has run and revise the severity then.
  What you may not do is take the narrowing on an unread lever. On a scope-filtered run that excludes
  Category D — `/audit permissions` is exactly this — the reading is unavailable unless the operator
  supplies it, so the narrowing is unavailable too
- **Deny rules in settings.json ONLY** — not in settings.local.json (bug [#8961](https://github.com/anthropics/claude-code/issues/8961))
- **No overly broad patterns** — `Bash(git *)` should be split into specific operations
- **Evaluation order** makes sense — deny overrides ask overrides allow

## Category C: MCP Servers

- All stdio server commands resolve (check `which` or `command -v` for the binary)
- If the repo wraps npx-based MCP servers with a launcher script (Windows cross-platform spawn
  workaround per CC issue [#36808](https://github.com/anthropics/claude-code/issues/36808)), every
  npx-based server entry references the same launcher path AND the launcher file exists and is
  readable. Repos without a launcher convention skip this check
- Env var references use `${VAR_NAME}` syntax (not bare `$VAR`)
- `disabledMcpjsonServers` entries match actual server names in `.mcp.json`
- Disabled servers have a documented reason (cross-reference the repo's MCP server convention docs when present)
- HTTP-type servers have valid URL patterns

## Category D: Hooks

- All hook script paths resolve to existing files on disk
- Scripts are readable (not permission-denied)
- `timeout` is a seconds value — flag a recognizably millisecond-scale figure (a round thousands
  multiple like `30000` or `120000`), not merely a large one: the docs give defaults, not a maximum
- Timeouts are reasonable: 5-15s for simple formatters, 30s for slow-startup tools (pwsh)
- Matchers take their intended evaluation path — only letters, digits, `_`, `-`, spaces, `,`, `|`
  makes it an exact-string list; any other character makes it an unanchored JavaScript regex, which
  needs `^…$` to match a whole string (`Edit.*` also matches `NotebookEdit`)
- A shell-form hook quotes each path placeholder; exec form is the docs' preference but shell form
  is correct when the hook needs pipes, `&&`, redirects, or a `.cmd`/`.bat` shim — do not flag it
- On a Windows-targeting repo, exec-form `command` resolves to a real executable — `bash` there
  finds the WSL relay and the hook silently never launches
- No duplicate hooks (same script registered twice for same event)
- Hook events are valid (cross-reference against official docs)
- **Hook-suppression levers are read and reported**, because a hook that cannot run is not a control:
  `disableAllHooks` in the settings-declared layer, and `allowManagedHooksOnly` /
  `strictPluginOnlyCustomization` in the managed layer. Report each as set or unset — this is a state
  reading, not a finding on its own — and say which of the inventoried hooks each one switches off.
  Category B's third baseline narrowing depends on this reading: it may not downgrade a missing deny
  rule on the strength of a hook any of these has already disabled

## Category E: Plugins

Two layers:

**E.1 Static checks**:

- Enabled plugins belong to an installed marketplace in `extraKnownMarketplaces`
- No references to plugins from unknown/uninstalled marketplaces
- Explicitly disabled plugins are intentional (not stale entries from removed marketplaces)

**E.2 Upstream drift detection** (live network — `scripts/check-plugin-drift.sh`):

Compares `enabledPlugins` keys against live `marketplace.json` for each registered marketplace.
Detects three drift modes static checks miss:

| Mode | Definition | Auto-fix policy |
|---|---|---|
| **ORPHAN** (false) | Plugin in `enabledPlugins` set to `false`, NOT in upstream catalog | AUTO-REMOVE — behaviorally a no-op (`false` ≡ absent for plugin loading) and the entry generates `/doctor` errors |
| **ORPHAN** (true) | Plugin in `enabledPlugins` set to `true`, NOT in upstream catalog | REPORT ONLY — user explicitly enabled a plugin that is now gone upstream; surface for manual review, never auto-remove |
| **NEW** | Plugin in upstream catalog, NOT in `enabledPlugins` | AUTO-ADD as `enabledPlugins["<name>@<market>"]: false` — records the discovery as an explicit opt-out, which keeps per-developer `settings.local.json` overrides functional |
| **RENAME?** | Heuristic match between an ORPHAN and a NEW within the same marketplace | REPORT ONLY — flag for human review, no automation |

**Network-tolerant**: a marketplace whose upstream fetch fails is reported `SKIP` and does not fail
the run. Use `SETTINGS_AUDIT_FIXTURE_DIR=<dir>` to short-circuit network calls in tests (loads
`<market-key>.json` from the fixture directory).

**Invocation:**

```bash
# Project audit (default — reads .claude/settings.json at the project root)
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-plugin-drift.sh"

# User audit (override target file)
CLAUDE_SETTINGS_FILE=~/.claude/settings.json \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-plugin-drift.sh"

# Plan + dry-run apply
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/fix-plugin-drift.sh"

# Apply auto-fixes
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/fix-plugin-drift.sh" --yes
```

**Env var contract:**

| Env var | Purpose | Default |
|---|---|---|
| `CLAUDE_SETTINGS_FILE` | Path to the `settings.json` to audit | `<project>/.claude/settings.json` |
| `SETTINGS_AUDIT_FIXTURE_DIR` | Test fixture directory (skips network) | unset |
| `SETTINGS_AUDIT_OUTPUT_JSON` | Path to write structured findings JSON | unset (stdout only) |

## Category F: Environment Variables

- Env vars in `settings.json` are documented Claude Code variables or justified custom vars
- Secrets (tokens, keys, passwords) are in `settings.local.json`, NOT in `settings.json`
- Path-based env vars (cloud-CLI config dirs, tool-cache paths) use forward slashes for cross-platform portability

## Category G: Skill-listing budget

- **Overflow check** — if `/doctor` reports dropped skill descriptions, the skill listing has exceeded
  its budget and the least-invoked skills' trigger keywords are silenced (names still resolve;
  auto-invocation degrades silently). `/doctor` needs an interactive TTY — prompt the user to run it.
  Repos with large skill rosters overflow routinely
- **Levers, cheapest first** — trim `description` / `when_to_use` frontmatter (key use case first;
  1,536-char cap per entry), `skillOverrides: { <skill>: "name-only" }` in a contributor's
  `settings.local.json` (does NOT apply to plugin skills), then `skillListingBudgetFraction` /
  `SLASH_COMMAND_TOOL_CHAR_BUDGET` in project settings as a last resort (costs context every turn)
- **Recommend, don't apply the list** — `skillOverrides` is contributor-scoped; surface the candidate
  least-invoked skills, leave the actual name-only list to the developer

## Category H: Model and effort settings

Row-by-row criteria are in [audit-checklist.md](../reference/audit-checklist.md) "H. Model and
effort settings". What governs the category:

- **Scope** — `effortLevel`, `fallbackModel`, `availableModels`, `enforceAvailableModels` in the
  settings files this skill already opens, `settings.local.json` included: `check-structure.sh`
  reports those four by value while keeping env and permission entries as counts, so a local-only
  misconfiguration is checkable without dumping the secrets beside it. `modelOverrides` values are
  deliberately not validated; the checklist says why
- **Fetch before reporting** — every row rests on upstream-owned behavior, so a finding requires the
  Phase 3.3 model-config fetch, not this file's wording
- **Two authorities, and they can disagree** — the declared settings schema constrains `effortLevel`
  by `enum` and `fallbackModel` by `maxItems` (raw array length), while the harness caps the
  fallback chain after deduplication. Report a schema violation and a harness-behavior finding as
  the separate things they are
- **Per-row visibility, not a blanket claim** — some of these are silent and some announce
  themselves (a narrowed alias shows a substitution notice). Each row states which, because it
  changes what the finding is worth to the reader
- **Placement is out of reach** — `availableModels` and `enforceAvailableModels` belong in the
  highest-precedence managed source, and admin-deployed managed sources do not merge. Nothing in the
  files this skill reads decides whether that holds, so report the value-level finding and leave
  placement to the administrator

## Category I: Deep-link registration

Row-by-row criteria are in [audit-checklist.md](../reference/audit-checklist.md) "I. Deep-link
registration". What governs the category:

- **Scope** — the single key `disableDeepLinkRegistration`, in the files this skill reads by value
  (`.claude/settings.json`, `~/.claude/settings.json`). `check-structure.sh` does not report it, so
  a `settings.local.json` or managed-settings occurrence is not inspectable rather than absent —
  and no file read would close the managed gap, since server-managed delivery, MDM plist, and
  registry policy are managed sources with no file on the path this skill resolves. Whether the OS
  handler is actually registered is workstation state, not configuration, and is not audited here
- **Fetch before reporting** — the accepted value is upstream-owned, so a finding requires the
  Phase 3.1 settings fetch, the way Category F resolves environment variables against their own page
- **Two authorities, agreeing on the value only** — the declared settings schema types the key
  `"type": "string", "enum": ["disable"]`, so a schema-aware editor flags a wrong value before the
  file is loaded, the same authoring-time path two of Category H's rows have. The row stays because
  the schema is advisory and the harness still reads a file that violates it. The agreement stops at
  the value: the schema's own `description` puts registration at startup where the docs page puts it
  at the first prompt sent. Behavior is the docs page's to state, so cite it, not the schema
- **Value first, then placement** — a key that is **present** and not the string `"disable"` is a
  prevention that was never invoked (warning); gate on `has(…)`, since an absent key is a consumer
  accepting the default on purpose. Where an organization requires enforcement and the key sits with
  `"disable"` in a readable scope, the finding is that **this placement** cannot enforce it
  (warning) — never that the system is unenforced, because nothing about the managed layer is
  decidable from here. Deliberately below its `enforceAvailableModels` sibling's `error`: a bypass
  is exactly what cannot be proven, and managed settings may already carry the key. Absent a
  declared enforcement requirement, user-scope placement is the documented single-machine usage and
  is not a finding
