# audit: Phase 2 validation categories

Detailed checks for each Phase 2 category (A–I). SKILL.md Phase 2 names the categories + points here;
this file carries the per-check criteria. Run each category's checks and record findings with severity
ratings.

Load the audit checklist alongside these: [audit-checklist.md](../reference/audit-checklist.md).

## Category A: Schema & Structure

- `$schema` present and points to `https://json.schemastore.org/claude-code-settings.json`
- No unknown top-level keys (cross-reference against official docs schema)
- `settings.local.json` does NOT contain `mcpServers` (wrong file, use `.mcp.json`)

## Category B: Permissions

- **Baseline permission patterns**: iterate the patterns in
  [required-permissions.md](../reference/required-permissions.md). Each pattern in
  `sensitive-file-deny` and `destructive-bash-deny` must appear in `settings.json` `permissions.deny`;
  each pattern in `ask-rules` must appear in `settings.json` `permissions.ask`. When the consuming
  repo's own rules declare additional required patterns, check those too
- **Before flagging an absent baseline pattern, apply the narrowings** in
  [required-permissions.md](../reference/required-permissions.md) "Narrowing the baseline": a
  documented repo exemption, a documented project hook convention, or a **live** `PreToolUse` hook that
  already blocks that family on the tool surface the pattern defends (that third case is `info` with
  the residual named, not `error`). Read the three preconditions there before downgrading: installed
  and enabled is not enough, a `Bash` hook does not cover a `Read`-pattern family, and coverage of one
  command family says nothing about a neighboring one. Where no hook inventory was taken, state the
  finding as conditional rather than as an assertion
- **The liveness reading is Category D's, and Category D runs after this one.** A–I is presentation
  order, not a dependency ban: pull Category D's hook-suppression lever reading forward before taking
  the third narrowing, or defer the downgrade until Category D has run and revise the severity then.
  What you may not do is take the narrowing on an unread lever. On a scope-filtered run that excludes
  Category D, and `/audit permissions` is exactly this, the reading is unavailable unless the operator
  supplies it, so the narrowing is unavailable too
- **Deny rules in settings.json ONLY**, not in settings.local.json (bug [#8961](https://github.com/anthropics/claude-code/issues/8961))
- **No overly broad patterns**: `Bash(git *)` should be split into specific operations
- **Evaluation order** makes sense: deny overrides ask overrides allow
- **What the engine already settled.** `scripts/audit-engine.sh` decides pattern presence for every
  baseline row (reading the list from required-permissions.md, never a transcription), the
  deny-in-local placement, the blanket `Bash(git *)` allow, and the allow-completeness rows, which
  it reports at `info`: under auto mode the classifier decides those calls, so their absence is a
  convenience gap, never a security one. It also takes narrowing 3 mechanically wherever an enabled
  plugin ships `hooks/coverage.json`, checking all three preconditions (the hook is live under the
  lever reading, the pattern's tool is on the matcher, the pattern is named), and it retires any
  finding the consumer's `.claude/audit-pass.md` record suppresses by `finding_id`. The model's
  Category B work is what is left: narrowings 1 and 2, narrowing 3 for guards with no manifest, and
  the consuming repo's own extra patterns

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

**The engine decides the mechanical rows of this category** (path resolution and readability,
millisecond-shaped timeouts, matcher class and anchoring, placeholder quoting in shell form,
duplicates, the lever reading, cache-versus-loaded divergence) and the model does the rest below.
**The inventory this category checks is Phase 1.0's**, from
`scripts/check-hook-coverage.sh`, which the engine runs: settings-declared hooks *and* every enabled
plugin's own hook config, read from the directory the session loads (a `directory` marketplace's
checkout first, the installed-plugin registry otherwise). That matters for two of the rules below:
`${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}` only ever appear in a plugin-provided hook, so
those rules are decidable only against a plugin-inclusive inventory. Where the
script exited 1, say which sources went unenumerated rather than reporting the inventory as the
complete set.

- All hook script paths resolve to existing files on disk
- Scripts are readable (not permission-denied)
- `timeout` is a seconds value. Flag a recognizably millisecond-scale figure (a round thousands
  multiple like `30000` or `120000`), not merely a large one: the docs give defaults, not a maximum
- Timeouts are reasonable: 5-15s for simple formatters, 30s for slow-startup tools (pwsh)
- Matchers take their intended evaluation path. Only letters, digits, `_`, `-`, spaces, `,`, `|`
  makes it an exact-string list; any other character makes it an unanchored JavaScript regex, which
  needs `^…$` to match a whole string (`Edit.*` also matches `NotebookEdit`)
- A shell-form hook quotes each path placeholder; exec form is the docs' preference but shell form
  is correct when the hook needs pipes, `&&`, redirects, or a `.cmd`/`.bat` shim, so do not flag it
- On a Windows-targeting repo, exec-form `command` resolves to a real executable. `bash` there
  finds the WSL relay and the hook silently never launches
- No duplicate hooks (same script registered twice for same event)
- Hook events are valid (cross-reference against official docs)
- **Hook-suppression levers are read and reported**, because a hook that cannot run is not a control:
  `disableAllHooks` in the settings-declared layer, and `allowManagedHooksOnly` /
  `strictPluginOnlyCustomization` in the managed layer. Report each as set or unset, and say which
  of the inventoried hooks each one switches off. This is a state reading, not a finding on its own.
  Category B's third baseline narrowing depends on this reading: it may not downgrade a missing deny
  rule on the strength of a hook any of these has already disabled

## Category E: Plugins

Two layers:

**E.1 Static checks**:

The engine merges `enabledPlugins` from the user, project and local files (local over project over
user). Managed-scope `enabledPlugins` is not merged.

- A key in the project or local file whose marketplace no scope registers is an `error` finding
  (`unknown-marketplace:<key>`).
- Every `false` key in the user, project and local files is an `ok` inventory row
  (`disabled-plugin:<key>`, check `E/disabled-plugin`). A `false` that a `true` at a higher scope
  overrides says it is shadowed.
- The exception is a `false` that is the merged value and that an enabled plugin declares as a
  direct dependency: that is a `warning` finding, `dependency-disabled:<key>`, on the file holding
  the `false`, naming the enabled plugins that need it. Dependencies come from each enabled plugin's
  `.claude-plugin/plugin.json` at the install path the hook inventory resolved, in the string
  (`name`, `name@marketplace`) and object (`name`, optional `marketplace`) forms; a bare name
  resolves to the dependent's own marketplace. Version constraints and dependencies of
  dependencies are not checked. The manifest is optional, so an install path with no `plugin.json`
  declares no dependencies. An enabled plugin whose install path did not resolve, whose
  `plugin.json` is not valid JSON, or whose `dependencies` is not an array is one `not-inspectable`
  row (`dependencies-unread:<key>`). Basis: the
  [install page](https://code.claude.com/docs/en/plugins/install) "Plugins with dependencies" says
  disabling a plugin another enabled plugin still needs is refused, and the
  [dependencies page](https://code.claude.com/docs/en/plugins/dependencies) says a plugin whose
  local dependency copy is disabled "is disabled at the next plugin load"; both are pinned in
  `reference/doc-citations.tsv`. As of 2026-09-26; recheck when a Claude Code release note changes
  how a disabled dependency affects the plugin that declares it.

**E.2 Upstream drift detection** (live network, via `scripts/check-plugin-drift.sh`):

Compares the audited file's `enabledPlugins` keys against the live `marketplace.json` of each
marketplace declared in that file's `extraKnownMarketplaces`. Detects three drift modes static
checks miss:

| Mode | Definition | Fix policy |
|---|---|---|
| **ORPHAN** (false) | Plugin in `enabledPlugins` set to `false`, NOT in upstream catalog | Removal candidate, removed by `--yes`. The removal moves to manual review when a lower-precedence scope file (the user file, and the sibling `settings.json` when the audited file is `settings.local.json`) holds `true` for the key, because removing the `false` would let that `true` take effect; an unreadable or invalid lower scope file does the same. Other developers' user scopes and managed settings are not checked, and a plan with a pending removal says so |
| **ORPHAN** (true) | Plugin in `enabledPlugins` set to `true`, NOT in upstream catalog | REPORT ONLY. The user explicitly enabled a plugin that is now gone upstream; surface for manual review, never auto-remove |
| **NEW** | Plugin in upstream catalog with no entry in the audited file | REPORT ONLY. `fix-plugin-drift.sh` never adds a key. The engine reports catalog plugins with no entry in any scope as one `ok` inventory row per marketplace (check `E/drift-new`) |
| **RENAME?** | Heuristic match between an ORPHAN and a NEW within the same marketplace | REPORT ONLY. Flag for human review, no automation |

`check-plugin-drift.sh` exits 1 only when it finds an orphan (a rename pair always holds one); a run that finds
only NEW plugins exits 0.

**Coverage:** a marketplace the audited file does not declare is not diffed. Every
`check-plugin-drift.sh` run prints a `Not diffed:` line with the count and the keys, including when
the file declares no marketplace. The engine reports the same gap as an `E/drift` `skip` row
(`drift-coverage:<file>`) for the project and local files: their keys whose marketplace some scope
registers but the project file does not declare. A key whose marketplace no scope registers is
reported under `unknown-marketplace` instead.

**Network-tolerant**: a marketplace whose upstream fetch fails is reported `SKIP` and does not fail
the run. Use `SETTINGS_AUDIT_FIXTURE_DIR=<dir>` to short-circuit network calls in tests (loads
`<market-key>.json` from the fixture directory).

**Invocation:**

```bash
# Project audit (default: reads .claude/settings.json at the project root)
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-plugin-drift.sh"

# User audit (override target file)
CLAUDE_SETTINGS_FILE=~/.claude/settings.json \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-plugin-drift.sh"

# Plan + dry-run apply
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/fix-plugin-drift.sh"

# Apply the orphan-false removals
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/fix-plugin-drift.sh" --yes
```

**What `--yes` leaves behind:** each apply writes a `<settings>.bak.<UTC stamp>.<random>` sibling
before it replaces the file, and never prunes one. The random part comes from `mktemp -u`; the
apply is refused when anything already exists at that name, and the copy is written on one
exclusive open (bash noclobber, `O_CREAT|O_EXCL`), so no file or link at the name, planted before
or after the check, is written through. Two applies in the same second each get their own. The
backup is written under `umask 077`, so 0600 where the platform honors mode bits (Linux, macOS;
Git Bash does not). A
project that tracks `.claude/` may want `.claude/*.bak.*` ignored.

**What `--yes` refuses:** a settings path that is a symlink, because the replacement is a rename
and would replace the link rather than its target; and a path the project-root ladder inferred
that turns out to be the user settings file, which is what a session started outside a repository
resolves to. An explicit `CLAUDE_SETTINGS_FILE` at the user settings file still applies, with a
warning naming the waived guard. To apply to a settings file that is a symlink, point
`CLAUDE_SETTINGS_FILE` at the file the link resolves to.

**Env var contract:**

| Env var | Purpose | Default |
|---|---|---|
| `CLAUDE_SETTINGS_FILE` | Path to the `settings.json` to audit | `<project>/.claude/settings.json` |
| `SETTINGS_AUDIT_FIXTURE_DIR` | Test fixture directory (skips network) | unset |
| `SETTINGS_AUDIT_OUTPUT_JSON` | Path to write structured findings JSON | unset (stdout only) |

## Category F: Environment Variables

- Env vars in `settings.json` are documented Claude Code variables or justified custom vars
- Secrets (tokens, keys, passwords) are in `settings.local.json`, NOT in `settings.json`

## Category G: Skill-listing budget

Row-by-row criteria are in [audit-checklist.md](../reference/audit-checklist.md) "G. Skill-listing
budget". What governs the category:

- **State the budget, or the finding is not computable.** The listing budget is
  `skillListingBudgetFraction` of the model's context window, **default `0.01`, i.e. 1%**, and
  `SLASH_COMMAND_TOOL_CHAR_BUDGET` overrides it with a fixed character count, **documented fallback
  8,000 characters**. Each entry's combined `description` + `when_to_use` text is separately capped at
  `skillListingMaxDescChars`, **default `1536`**. For a 200K-token window, `200,000 × 4 × 0.01 = 8,000`
  characters, which is why the env var's fallback is that number. Without the constant a report can say
  "overflowed" but not "by how much", so quote it. All three are upstream-owned: confirm them in Phase
  3 against [settings-reference](https://code.claude.com/docs/en/settings-reference) and
  [env-vars](https://code.claude.com/docs/en/env-vars) before publishing a number (defaults as
  written verified 2026-08-31; recheck trigger: a Phase-3 confirm finding a moved default
  re-derives this paragraph)
- **Overflow check: an existing debug log first, then two routes, and only one of those survives
  a headless run.** The engine looks for a debug log this session already wrote, at the path
  `--debug-log` names, else `CLAUDE_CODE_DEBUG_LOGS_DIR`, else the newest file under
  `<user dir>/debug/`, and parses the over-budget warning from it: skill count, characters, and the
  budget in one line, which is everything the category needs. A log the operator named reads as
  fitting when it carries no warning; a log the engine merely found, newest-first, decides only
  when it names this project root, since the debug directory also holds other sessions' logs.
  Anything else reads as not measured, never as clean. Only then: `/doctor` estimates the
  listing's cost and its biggest contributors, and it needs an interactive TTY, so prompt the user to
  run it. When this audit runs headless, under `-p`, a spawned agent, or a background job, use the documented
  debug route instead: *"When the listing exceeds its budget, Claude Code also writes a warning to the
  debug log, visible with `--debug`"*
  ([skills](https://code.claude.com/docs/en/skills), "Skill descriptions are cut short"). Report which
  route was taken; a category that names only `/doctor` yields nothing in the harness's own headless
  mode. `/context`'s Skills row reports the listing size after the budget is applied, a second
  *interactive* reading, not a headless one. Overflow silences the least-invoked skills' trigger
  keywords (names still resolve; auto-invocation degrades silently), and repos with large skill rosters
  overflow routinely
- **Measure the roster composition before naming a lever.** Count listing entries by origin: plugin
  skills, project skills (`.claude/skills/`), user skills (`${CLAUDE_CONFIG_DIR:-~/.claude}/skills/`).
  This is the single input that decides which levers exist, and it is cheap. A run that skips it
  recommends levers the operator cannot pull
- **Levers, cheapest first, and the ordering depends on that composition:**
  - *Any origin*: trim `description` / `when_to_use` at the source, key use case first. Costs nothing
    at runtime and is the only lever that helps every roster
  - *Project and user skills*: `skillOverrides: { <skill>: "name-only" }` in a contributor's
    `settings.local.json`
  - *Plugin skills*: `skillOverrides` **does not reach them**: *"Does not apply to plugin skills,
    which are managed through `/plugin`"* (settings) and *"Plugin skills are not affected by
    `skillOverrides`. Manage those through `/plugin` instead"* (skills). So on a plugin-heavy roster
    the lever is `/plugin`, since disabling a plugin removes its skills from the listing, plus trimming
    the descriptions upstream in the plugin that owns them. Neither page documents a per-skill
    `name-only` state reachable from `/plugin`, so do not promise one
  - *Last resort, any origin*: raise `skillListingBudgetFraction` / `SLASH_COMMAND_TOOL_CHAR_BUDGET`
    in project settings. It costs context every turn, which is why it is last here even though the
    docs present it first
- **Recommend, don't apply the list.** `skillOverrides` is contributor-scoped and `/plugin` is a
  machine-level action; surface the candidate least-invoked skills, leave the actual list to the
  developer

## Category H: Model and effort settings

Row-by-row criteria are in [audit-checklist.md](../reference/audit-checklist.md) "H. Model and
effort settings". What governs the category:

- **Scope.** `effortLevel`, `fallbackModel`, `availableModels`, `enforceAvailableModels` in the
  settings files this skill already opens, `settings.local.json` included: `check-structure.sh`
  reports those four by value while keeping env and permission entries as counts, so a local-only
  misconfiguration is checkable without dumping the secrets beside it. `modelOverrides` values are
  deliberately not validated; the checklist says why
- **Fetch before reporting.** Every row rests on upstream-owned behavior, so a finding requires the
  Phase 3.3 model-config fetch, not this file's wording
- **Two authorities, and they can disagree.** The declared settings schema constrains `effortLevel`
  by `enum` and `fallbackModel` by `maxItems` (raw array length), while the harness caps the
  fallback chain after deduplication. Report a schema violation and a harness-behavior finding as
  the separate things they are
- **Per-row visibility, not a blanket claim.** Some of these are silent and some announce
  themselves (a narrowed alias shows a substitution notice). Each row states which, because it
  changes what the finding is worth to the reader
- **Placement is out of reach.** `availableModels` and `enforceAvailableModels` belong in the
  highest-precedence managed source, and admin-deployed managed sources do not merge. Nothing in the
  files this skill reads decides whether that holds, so report the value-level finding and leave
  placement to the administrator

## Category I: Deep-link registration

Row-by-row criteria are in [audit-checklist.md](../reference/audit-checklist.md) "I. Deep-link
registration". What governs the category:

- **Scope.** The single key `disableDeepLinkRegistration`, in the files this skill reads by value
  (`.claude/settings.json`, `~/.claude/settings.json`). `check-structure.sh` does not report it, so
  a `settings.local.json` or managed-settings occurrence is not inspectable rather than absent.
  No file read would close the managed gap, since server-managed delivery, MDM plist, and
  registry policy are managed sources with no file on the path this skill resolves. Whether the OS
  handler is actually registered is workstation state, not configuration, and is not audited here
- **Fetch before reporting.** The accepted value is upstream-owned, so a finding requires the
  Phase 3.1 settings fetch, the way Category F resolves environment variables against their own page
- **Two authorities, agreeing on the value only.** The declared settings schema types the key
  `"type": "string", "enum": ["disable"]`, so a schema-aware editor flags a wrong value before the
  file is loaded, the same authoring-time path two of Category H's rows have. The row stays because
  the schema is advisory and the harness still reads a file that violates it. The agreement stops at
  the value: the schema's own `description` puts registration at startup where the docs page puts it
  at the first prompt sent. Behavior is the docs page's to state, so cite it, not the schema
- **Value first, then placement.** A key that is **present** and not the string `"disable"` is a
  prevention that was never invoked (warning); gate on `has(…)`, since an absent key is a consumer
  accepting the default on purpose. Where an organization requires enforcement and the key sits with
  `"disable"` in a readable scope, the finding is that **this placement** cannot enforce it
  (warning), never that the system is unenforced, because nothing about the managed layer is
  decidable from here. Deliberately below its `enforceAvailableModels` sibling's `error`: a bypass
  is exactly what cannot be proven, and managed settings may already carry the key. Absent a
  declared enforcement requirement, user-scope placement is the documented single-machine usage and
  is not a finding
