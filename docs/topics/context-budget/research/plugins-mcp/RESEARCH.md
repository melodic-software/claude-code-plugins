# RESEARCH — plugins & MCP servers as a context-budget lever

## Task restatement

Research **enabling and disabling Claude Code plugins and MCP servers as a context-budget lever** —
scopes, precedence, measurement, prompt-cache effects, and what `/doctor` already does about unused
ones. Commissioned to inform the design of a new marketplace skill that inventories and trims a
session's fixed startup context payload; the output is for that skill's author, a Claude Code plugin
maintainer. The decision it feeds is **where the new skill must delegate to the bundled `/doctor`
skill rather than duplicate it.**

Run date **2026-08-17**, against installed **Claude Code v2.1.232** and docs fetched the same day.
Budget: full depth, official-docs-first. Nested spawning unavailable — all phases ran sequentially in
one context.

## Sidecars

| Section | Abstract | File | Anchor |
|---|---|---|---|
| Plugin enablement scopes (Q1) | Plugins are enabled/disabled by the single key `enabledPlugins` at four scopes (managed/user/project/local) with precedence managed > CLI > local > project > user, falling back to the plugin's own `defaultEnabled`. | [`RESEARCH-plugin-enablement-scopes.md`](RESEARCH-plugin-enablement-scopes.md) | `#q1--every-scope-a-plugin-can-be-enableddisabled-at` |
| Plugin payload components (Q2) | Of a plugin's seven component types only skills/commands and agents cost always-loaded context (listing text only); hooks, monitors, themes and LSP cost zero model context, and MCP tool schemas are deferred. | [`RESEARCH-plugin-payload-components.md`](RESEARCH-plugin-payload-components.md) | `#q2--what-one-enabled-plugin-contributes-to-the-always-loaded-payload` |
| MCP enablement & deferral (Q3) | MCP has two unrelated enable/disable key pairs — `enabledMcpjsonServers`/`disabledMcpjsonServers` (settings, .mcp.json approval) and `enabledMcpServers`/`disabledMcpServers` (~/.claude.json, per-project connection toggle) — and tools are deferred by default so a disabled server usually saves no context. | [`RESEARCH-mcp-enablement-deferral.md`](RESEARCH-mcp-enablement-deferral.md) | `#q3--mcp-servers-enabledisable-keys-scopes-and-deferral` |
| Prompt-cache invalidation (Q4) | Enabling or disabling a plugin never invalidates the prompt cache except through its MCP servers, and even then only when those tools load into the prefix rather than being deferred. | [`RESEARCH-prompt-cache-invalidation.md`](RESEARCH-prompt-cache-invalidation.md) | `#q4--prompt-cache-invalidation` |
| The `/doctor` delegation seam (Q5) | The bundled /doctor skill (a full setup checkup since v2.1.205) already owns finding unused skills/MCP servers/plugins versus their context cost and disabling them, so a new skill must delegate that check and can only differentiate on scope, headlessness, per-plugin attribution and CI use. | [`RESEARCH-doctor-delegation-seam.md`](RESEARCH-doctor-delegation-seam.md) | `#q5--the-bundled-doctor-skill-what-it-claims-what-it-doesnt-and-the-delegation-seam` |
| Native inventory surface (Q6) | Of the native inventory surfaces only /context and /mcp run under claude -p; the other six slash commands are interactive-only, so a headless skill must fall back to claude plugin/mcp subcommands. | [`RESEARCH-native-inventory-surface.md`](RESEARCH-native-inventory-surface.md) | `#q6--the-wider-native-inventory-surface` |
| Methodology | Fetch log, artifact-ladder walk, conflicts, recency verdict and outcome-gate result for the plugins/MCP context-budget research run. | [`RESEARCH-methodology.md`](RESEARCH-methodology.md) | `#methodology-fetch-log-conflicts-and-gate-result` |

Coverage ledger: [`research-checklist.md`](research-checklist.md) — 32 rows, bounded corpus,
enumerated from the docs `sitemap.xml`, the `claude --help` subcommand tree, and the release stream.

## Next-stage handoff

### Settled facts the skill can build on

1. **One key, four scopes, one precedence order.** `enabledPlugins` (object, `"name@marketplace":
   bool`); managed > CLI > local > project > user; `defaultEnabled` is the fallback. There is no
   `disabledPlugins`. The CLI can write only user/project/local. **Writing `false` at a scope below
   the one that set `true` is a silent no-op** — the skill must resolve the winning scope first.
2. **A plugin's always-loaded cost is listing text only.** Skill/command names + descriptions and
   agent descriptions. Hooks are `harness-only — no model context cost`. Themes, monitors and LSP
   carry no stated model-context cost. Bodies load on invocation.
3. **The skill listing is capped, not unbounded** (`skillListingBudgetFraction`, default 1%). Past
   the cap, adding plugins degrades *routing* (descriptions truncate to names) rather than growing
   context. On the measured session it sat at exactly 1.0% — i.e. at the cap.
4. **MCP tool schemas are deferred by default.** Only tool names + server instructions load at
   startup. `alwaysLoad`, `ENABLE_TOOL_SEARCH=false`/threshold, non-first-party
   `ANTHROPIC_BASE_URL`, older Vertex models and Foundry-on-Azure are the named exceptions.
5. **Two disjoint MCP key pairs**, and the docs say so explicitly:
   `enabledMcpjsonServers`/`disabledMcpjsonServers` (+ `enableAllProjectMcpServers`) govern
   `.mcp.json` *approval* in settings files; `enabledMcpServers`/`disabledMcpServers` live per-project
   in `~/.claude.json` and are what the `/mcp` toggle writes. `/mcp disable` is **per-project**.
6. **Cache cost of trimming is near-zero.** Six of seven plugin component types never invalidate the
   cache; only an MCP-providing plugin can, and only when its tools are prefix-loaded. Cost lands on
   the first turn *after* the change applies, so edits batch cheaply. `/reload-plugins` already warns
   and skips unless `--force` when a reload would invalidate.
7. **`/doctor` Check 1 already does unused-item detection** (usage counters + transcript scanning +
   scope-correct disable edits) and **Check 6 already summarises always-resident context**. It is
   deliberately deferral-aware and refuses to claim token savings for deferred MCP servers.
8. **Measurement primitives that run headlessly:** `claude -p "/context"` (with a distinct
   `System tools (deferred)` row), `claude plugin details <name>` (`count_tokens`-derived
   `Always-on` figure), `claude plugin list --json`, `claude mcp list`, `claude doctor`.

### The delegation seam — the answer to the commissioning question

**`/doctor` owns:** detecting unused skills / MCP servers / plugins, the usage-counter and
transcript-scanning methodology (including the `pluginUsage` seeding trap and MCP tool-name
normalisation), verdict policy, and scope-correct disable edits.

**`/doctor` structurally cannot:** be model-invoked (`disableModelInvocation: true` — the new skill
**cannot call it**, only tell the user to run it); measure live context (its own figures are
"disk-based estimates" and it defers to `/context`); use `claude plugin details`; run headlessly or
in CI; persist a diffable baseline; reason about prompt-cache cost of applying its own
recommendations; or scope a trim across projects.

**Therefore the new skill should**: instruct the user to run `/doctor` for unused-item detection,
and own *measurement, baselining, per-plugin attribution via `claude plugin details`, headless/CI
reporting, and cache-aware sequencing of the changes*.

### Open decisions for the author

- Whether to depend on `claude --safe-mode -p "/context"` (or `--bare`) as a floor measurement — the
  technique is designed here but **was not executed**, and first-run setup screens are a known
  hazard for the `CLAUDE_CONFIG_DIR` variant.
- How to handle the deferral-failure risk: issue #40314 (HTTP MCP tools not deferred, closed as not
  planned) means deferral must be **measured**, not assumed, and the skill needs a policy for what to
  report when `/context` shows prefix-loaded MCP tools.
- Whether to surface `/usage`'s per-plugin/per-MCP-server attribution (Pro/Max/Team/Enterprise only,
  headless capability unverified) as a complement to `plugin details`'s cost side.

### Ten things NOT verified

Listed with checked/unchecked source sets in
[`RESEARCH-methodology.md`](RESEARCH-methodology.md#gaps-claims-not-accepted) and in each sidecar's
"What I could NOT verify" section. The load-bearing ones for this design: `enabledPlugins`
cross-scope merge semantics, LSP always-loaded cost, plugin-shipped output styles, #40314's fix
status, and whether the six interactive-only commands are interactive-only *universally* or only
inside a nested Claude Code session.

## Verification status

`verification: pending`. Outcome-gate criteria 4 (independent corroboration) and 7 (HIGH confidence
per accepted claim) are **not self-graded** — every sidecar header carries `sources[]` with `url`,
`tier` and publishing `pool` so a fresh context can grade them off the artifact. Note the
independence caveat in the methodology sidecar: multi-page `code.claude.com` citations are **one**
pool; genuine independence in this run comes from the installed binary/CLI (Tier 0),
`raw.githubusercontent.com/anthropics/claude-code`, and live `/context` output.
