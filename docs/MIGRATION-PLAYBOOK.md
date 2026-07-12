# Migration playbook

How skills, hooks, and agents become reusable plugins in this marketplace. One plugin is migrated at a
time: lift it out, make it work in plugin form and in any repo, build in configuration and extensibility,
vet it against best practices, then publish.

All schema and behavior claims below were verified against the official docs on 2026-06-22 (the
"Reintegration" section's marketplace-settings claims — `extraKnownMarketplaces` / `enabledPlugins` in a
project's `settings.json` — on 2026-06-29, against the discover-plugins "Configure team marketplaces"
guide; the "Extensibility contract v2.1" sections and their smoke tests on 2026-07-12 against Claude
Code 2.1.207). Re-verify fresh before acting — see `CLAUDE.md` "Fresh-docs mandate".

## Intent

The point of moving a skill/hook out of a private repo and into a plugin is **reuse and developer
experience**: it should drop into any repository and work, and a consumer should be able to customize
behavior without filing an issue or editing the plugin. If a consumer needs to change a workflow, add an
action, or adapt to their repo, that is an **extensibility point** the plugin must expose by design.

## Design charter

Every plugin is designed to these principles (named here as the bar; apply, don't recite):

- Low coupling, high cohesion
- Vertical slice architecture
- SOLID
- Clean code
- DRY / single source of truth / no duplication

Concretely for plugins: a plugin owns one cohesive capability, depends on nothing repo-specific, and
exposes its variability through declared configuration rather than internal forks.

## Organization — one plugin per cohesive concern

The charter's "one cohesive capability" is also the packaging boundary: **one plugin per cohesive
concern or capability**, grouped in the catalog through `category` / `tags` rather than by splitting.
A cohesive plugin MAY hold several units — a first-party plugin bundles many skills of one concern, a
hooks plugin bundles many hooks of one concern. One-unit-per-plugin is not the norm; do not ship a
plugin per hook.

- **Skills group by capability.** Distinct capabilities are distinct plugins; a single capability's
  always-together facets bundle (e.g. a prototyping capability's `logic` and `ui` skills ship together).
- **Hooks group by concern.** Per-hook selectivity comes from an env kill-switch
  (`HOOK_<PLUGIN>_ENABLED`), a `matcher`, or an `if` guard — author-managed control inside the bundle,
  the ecosystem norm.
- **Whole-product / vendor-brand bundles** driven by distribution are a separate, allowed shape.

**Why capability, not grab-bag.** Enabling and disabling happen at the plugin level, and the
`skillOverrides` setting explicitly *excludes* plugin skills (those are managed through `/plugin`), so
there is no clean per-skill à-la-carte toggle. Bundling several skills is therefore acceptable only
*within* one cohesive capability you would never split — it forbids lumping *distinct* capabilities into
a single plugin. Hooks differ: the env kill-switch gives clean per-hook control inside a bundle. The
discriminating axis is **silent-always-on** components (hooks — keep atomic, or toggle via env) versus
**opt-in-per-invocation** components (skills — group by capability).

## Naming

Name a plugin and its units by this precedence — an earlier rule wins on conflict:

1. **Semantic accuracy, zero confusion.** The capability is unambiguous from the name; qualify an
   overloaded generic term (a bare `audit` is collision bait).
2. **Official docs + ecosystem precedent.** kebab-case, no spaces; the namespace is the plugin's own
   `name` (not the marketplace name); mirror established Claude Code patterns.
3. **Explicit naming.** A domain-noun plugin name; no noise suffix (`-plugin` / `-tool` / `-helper`);
   no unit-type suffix (`-hook` / `-skill`) unless load-bearing; names track their semantic scope.

Applying that precedence:

- **Plugin `name` is a domain noun, kebab-case** (e.g. `feature-dev`, `pr-review-toolkit`).
- **Skill name follows its KIND.** An action / user-invoked skill reads as a **verb-phrase**
  (`create-plugin`, `review-pr`); a knowledge / model-invoked skill is a **noun-phrase**
  (`cqrs-implementation`, `agent-development`). The "reads-as-a-verb-phrase" heuristic scopes to action
  skills only — a `noun:noun` name is correct for a knowledge skill.
- **`/plugin:skill` doubling is idiomatic** (`/prototype:prototype`, first-party `/code-review:code-review`)
  — docs-blessed, not an anti-pattern. Do not contort a name solely to avoid the doubling.
- **Generic skill names are safe under namespacing** (`help`, `list`, `configure`) — the overloaded-term
  caution governs plugin *identity*, not a namespaced skill leaf.
- **Tool-scope shows up as brand-in-name, not a structural split.** A branded name signals a tool-scoped
  plugin; a plain domain-noun signals a tool-agnostic one. No marketplace separates plugins by tool-scope
  — do not formalize such a split.

## Extensibility model — what works today

These are the proven, documented mechanisms for consumer customization that do not confuse the agent.
Prefer them in this order; the earlier ones are simplest and least surprising.

| Mechanism | What it does | Use for |
|---|---|---|
| Consumer `CLAUDE.md` / `.claude/rules` | The skill reads the consuming project's own context and rules | Project-specific conventions, naming, policies — the default extension surface |
| `${CLAUDE_PROJECT_DIR}` | Path to the consumer's project root, substituted in hook/MCP/monitor commands and exported to subprocesses | Referencing project-local scripts/config |
| `userConfig` → `${user_config.KEY}` | Values Claude Code prompts for at enable time (typed: string/number/boolean/directory/file, optional sensitive). Substitutes as `${user_config.KEY}` into hook/MCP/monitor/command configs and non-sensitive values into skill/agent content; exported as `CLAUDE_PLUGIN_OPTION_<KEY>` to the plugin's own declared command subprocesses only — **not** to a Bash tool call a skill makes (see the [smoke-test record](extensibility-contract-smoke-tests.md)). Non-sensitive stored in `settings.json` under `pluginConfigs[<id>].options`; sensitive in the system keychain | Endpoints, toggles, tokens — consumer config without editing the plugin |
| `${CLAUDE_PLUGIN_ROOT}` | Path to the plugin's own installed directory | Referencing bundled scripts/assets (mandatory under cache isolation) |
| `${CLAUDE_PLUGIN_DATA}` | Persistent per-plugin directory that survives updates (`~/.claude/plugins/data/<id>/`) | Installed deps, caches, generated state |
| `hooks/hooks.json` | Event handlers the plugin ships | Behavior consumers opt into by enabling the plugin |

Design a skill so its variable parts route through the table above. "If you need to customize X, set
`userConfig` Y / add it to your project rules" — never "open an issue" or "fork the skill".

## Extensibility contract v2.1 — the four seams

The table above is the raw mechanism inventory ordered simplest-first; this contract is the **adopted**
policy for how a plugin exposes consumer variability, organizing those mechanisms into four seams. Each
seam matches a *kind* of variability — typed scalar, rich prose/rules, project convention, machine
state — not a rung on a preference ladder: choose the seam that fits the need, and within that choice
the table's simplest-first ordering still applies. Where the table's ordering and a seam's fit point
differently, **fit governs** — a typed token belongs in `userConfig` (seam 1) even though the table
lists consumer `CLAUDE.md` first. Each seam is tagged by its
authority — **[SPEC]** (documented Claude Code behavior), **[PRECEDENT]** (an official first-party
plugin does it, not written up as a spec), or **[PRECEDENT-EXTENSION]** (a documented shape extended
one increment past the precedent). Behavioral gaps the docs leave open are resolved empirically in the
[smoke-test record](extensibility-contract-smoke-tests.md).

1. **Typed scalars → `userConfig` → `pluginConfigs`. [SPEC]** Declare `string` / `number` /
   `boolean` / `directory` / `file` options (a `string` may set `multiple` for an array — there is no
   `string[]` type); mark a credential `sensitive` so it lands in the keychain, never `settings.json`.
   Non-sensitive values store under `pluginConfigs[<id>].options`. Use for endpoints, toggles, tokens,
   and single path knobs. The `directory` / `file` type is a UI hint, not a validator — a `--config`
   value is stored verbatim with no existence check and no normalization to absolute (smoke-test A).
2. **Tracked rich config under `${CLAUDE_PROJECT_DIR}`. [first-party PRECEDENT; folder form is a
   PRECEDENT-EXTENSION]** When configuration outgrows typed scalars — prose guidance, rule lists,
   threat models, structured rulesets — read a checked-in file instead of piling on `userConfig` knobs.
   The proven shape is a single tracked file `.claude/<plugin>.md` (Markdown, for model-facing
   guidance) or `.claude/<plugin>.yaml` (structured rules), each with a gitignored `*.local.*` personal
   overlay and an optional `~/.claude/<plugin>.md` user-global. The precedent is the official
   **security-guidance** plugin (<https://code.claude.com/docs/en/security-guidance>): it reads
   `.claude/claude-security-guidance.md` (project), `~/.claude/claude-security-guidance.md` (user), and
   `.claude/claude-security-guidance.local.md` (gitignored personal override), loading every location
   that exists and concatenating them. The **folder form** `.claude/<plugin>/**` (many files, one per
   concern) is the PRECEDENT-EXTENSION: the first-party precedent uses single files, so a plugin that
   needs a directory of config extends the shape by one increment, keeping the same overlay and
   resolution rules.
   - **Concern-named folder for multi-plugin-consumed config.** When a tracked-config concern is
     consumed by MORE THAN ONE plugin, name the folder by the concern, not a plugin
     (`.claude/<concern>/**`) — plugin-naming would couple the other consumers and the consumer
     repo's tracked files to one plugin's name, and plugin boundaries are the volatile axis across
     restructures. A further one-increment PRECEDENT-EXTENSION; each instance records its schema and
     resolution rules as a versioned contract under `docs/conventions/<concern>/` (template:
     `docs/conventions/hook-telemetry/`; first instance:
     [`docs/conventions/ecosystem-commands/`](conventions/ecosystem-commands/README.md)).
   - **Resolution + override semantics.** Resolve **user-global → team (project) → local overlay**,
     **additive-preferred**: a later layer adds to or refines earlier layers rather than silently
     replacing them. The first-party precedent concatenates; a plugin that genuinely must override does
     so per key, never by dropping the base layer wholesale.
   - **Recommended consumer `.gitignore`.** Ship the overlay convention with the one line the consumer
     adds: `.claude/*.local.*` (and `.claude/<plugin>/**/*.local.*` for the folder form) — personal
     overlays stay out of version control, team config stays tracked.
3. **Consumer `CLAUDE.md` / `.claude/rules` steering. [SPEC]** A plugin's skill and agent components
   run in the model's context and already read the consuming project's own rules — the default surface
   for project conventions, naming, and policy, requiring no plugin-side wiring. (Hook scripts do not
   see `CLAUDE.md`; they read env vars and file-based config only.)
4. **`${CLAUDE_PLUGIN_DATA}` for machine state only. [SPEC]** The per-plugin directory that survives
   updates — caches, installed dependencies, generated state. Never a channel for consumer
   *configuration* (it is machine-local and untracked); configuration flows through seams 1–3.

## Convention-resolution ladder

The **adopted** rule for how a plugin settles a value at runtime, applied to every seam:

1. Config present → use it.
2. Absent → explore the repo and infer, then **persist the inference** into the tracked config (seam 1
   or 2) so the next run is deterministic.
3. Cannot infer → ask the user, and offer to persist the answer.
4. Otherwise → a safe generic default.

No baked repo assumptions, ever. A plugin never hardcodes a consumer's layout; it reads a declared
value, infers-and-records, or asks — never guesses silently.

## Setup action — every configurable plugin ships one

Every plugin that carries any `userConfig` or tracked-config seam ships a re-runnable `setup` /
`configure` action (a skill) that interviews the consumer and writes the tracked config. It is
idempotent — safe to re-run to reconfigure. The Thariq `config.json` first-run pattern is **rejected**
for plugins: it is not an official mechanism, and it writes into `${CLAUDE_PLUGIN_ROOT}`, which is
replaced on every update (the plugins-reference caching note), so its state does not survive. Setup
writes to the consumer's tracked config or to `pluginConfigs` — both persist across updates.

## Shared tools and scripts seam

Separate **plugin-owned** logic from **consumer-owned** extension points:

- Plugin-owned scripts ship inside the plugin and run via `${CLAUDE_PLUGIN_ROOT}/scripts/` (or `bin/`)
  — bundled and cache-isolated, never reaching outside the plugin directory.
- Consumer-owned extension points are **declared paths**, not assumed layout: expose them through a
  `userConfig` `directory` option or a tracked-config key with a conventional default (e.g. `tools/`).
  A plugin reaches the consumer's own scripts only through a path the consumer declared or the
  convention the plugin documents — never a hardcoded repo structure.

## Version pinning and update delivery

- **A `version` bump in `plugin.json` is the only delivery vehicle.** A consumer receives a change only
  after the plugin's semver `version` increases — the version is the update cache key, so an unbumped
  plugin never delivers, even when its files changed (see "Shared code across plugins" below).
- **Consumers update deliberately** with `/plugin marketplace update <marketplace>`, which refetches
  the marketplace. There is no silent auto-push of plugin changes to a consumer.
- **Breaking-change / changelog note per plugin.** A version bump that changes behavior a consumer
  depends on — a renamed option, a moved config path, a removed action — records the change in the
  plugin's own changelog (a `CHANGELOG.md` in the plugin), so a consumer updating deliberately sees
  what shifted. A bump that adds a new trust surface additionally re-triggers the plugin-acceptance
  security review below.

## Persistence, configuration & external integration

A skill is a markdown prompt (plus optional scripts), not a compiled runtime — so ports / adapters /
CQS layering is a **category error** here. Expose variability the way real plugins and the extensibility
model above already prescribe:

- **Persistence.** Write generated state and caches to `${CLAUDE_PLUGIN_DATA}` (the per-plugin directory
  that survives updates — see the extensibility table). Choose JSON / JSONL / SQLite per need.
- **Configurable location or behavior.** One `userConfig` knob (`${user_config.KEY}`, per the
  extensibility table) with a sane default — never a consumer-bound interface. Add a knob **only** where
  a real repo-specific behavior surfaces (Rule of Three; no speculative knobs — see the design charter).
- **External systems (issue trackers and the like).** Use backend-neutral **"work item"** vocabulary
  plus either a direct CLI call (e.g. `gh`) or dependence on an **MCP server** — swapping the backend
  means swapping the MCP server, not introducing a pluggable-tracker abstraction (every official
  integration is a bare MCP wrapper).
- **Cross-skill references.** Hand off through the slash invocation when the target skill is present;
  degrade gracefully to prose when it is absent.

This is deliberately **not** ports / adapters: there is no runtime seam to invert in a prompt medium, so
a declared config surface, not an abstraction layer, is the extension point.

## MCP servers as a plugin component — carry decision

A plugin can ship MCP servers via `.mcp.json` at the plugin root (or an `mcpServers` key in
`plugin.json`), across all transports — stdio, HTTP, SSE, WS
([plugins-reference](https://code.claude.com/docs/en/plugins-reference), MCP servers). Those servers
**auto-connect when the plugin is enabled** (managed through plugin install, not a second `/mcp`
approval) and appear as standard tools. The connect cost differs by transport: a **stdio** server
costs a **local process spawn on every session that enables the plugin**, used or not; an **HTTP/SSE/WS**
server spawns no local process but still auto-connects (its trust prompt + tool-schema context cost).
Tool-search deferral hides the tool *schema* from context until first use but does **not** defer the
stdio spawn or the connect. That auto-start cost is why the default is **not** to ship MCP: exactly
one marketplace plugin ships one (`miro`, the dedicated Miro board capability — below), and the
discriminator below keeps it rare, reserved for a plugin genuinely useless without its server. A
credentialed SHIP additionally ships `defaultEnabled: false`, so its server does not auto-start for
consumers who never opt in.

**Uniform discriminator — apply to every server, no exemptions:**

1. **CLI covers the skill's need → CLI-first.** The plugin **depends on** the CLI (with documented
   install/setup — the binary is on PATH, not bundled: e.g. `npm install -g ctx7`,
   `npm install -g firecrawl-cli`, `playwright-cli`) and drops the MCP dependency; a CLI-first
   migration MUST carry that install guidance or the plugin breaks on a machine without the CLI.
   Token-economics precedent (results pipe to disk instead of flooding context): context7 (`ctx7`),
   playwright (`playwright-cli` — Microsoft-recommended, ~4× fewer tokens), firecrawl
   (`firecrawl-cli`), ccusage (`ccusage daily|monthly|session|blocks --json` — same token/cost
   breakdown as the MCP, [ccusage json-output](https://ccusage.com/guide/json-output)).
2. **No CLI + plugin is *useless* without the server → SHIP.** Bundle it and map each secret to
   `userConfig` `sensitive` (below). "Useless" is a high bar met by a **dedicated** server-wrapper
   plugin (its entire capability *is* the server); a plugin that runs in a reduced mode without the
   server is *degraded-but-functional* (rule 3), not a SHIP. A stdio SHIP owns its spawn: an `npx`
   command needs a `cmd /c` wrapper on Windows (#58510 below), so prefer invoking a bundled
   `node <server>` — it sidesteps #58510 entirely. Two bundling mechanisms, ratified by the `miro`
   SHIP (the first instance, below):
   - **Single self-contained bundle (preferred).** An [esbuild](https://esbuild.github.io/) bundle
     of the TypeScript source and every runtime dependency into one `dist/index.min.js` — no shipped
     `node_modules`, so no `NODE_PATH`. The source is the source of truth; the `.min.js` is committed
     generated output (plugin install runs no build step), and a CI lane rebuilds it from source with
     the pinned toolchain, fails on drift, and runs the artifact over stdio so a bundle that compiles
     but cannot serve MCP is caught in CI. `.min.` keeps the generated bundle out of the
     text-quality lanes (typos, editorconfig).
   - **Committed `node_modules` under `${CLAUDE_PLUGIN_DATA}` (fallback).** For a server that cannot
     be single-file bundled, ship its `node_modules` and set
     `env.NODE_PATH: "${CLAUDE_PLUGIN_DATA}/node_modules"` (the persist-deps example in
     [plugins-reference](https://code.claude.com/docs/en/plugins-reference)) or it fails at startup
     with `MODULE_NOT_FOUND`.

   A SHIP that connects to a **credentialed external service** ships `defaultEnabled: false` — it
   installs disabled and the consumer opts in, so enabling the marketplace does not auto-start a
   credentialed server for users who never asked for it.
3. **No CLI + plugin is *degraded-but-functional* without it → STAY repo-level.** The skill NAMES the
   dependency and the consumer provides the server in their own `.mcp.json`; the skill degrades
   gracefully or loads the tool via `ToolSearch` when present. This is the extensibility model's
   "swap the MCP server, not a pluggable abstraction" — declare the dependency, don't fork.
4. **Medley-/infra-bound server (no general-purpose plugin, or repo-coupled identity) → STAY
   repo-level.** Not a plugin concern.

**Secrets → `userConfig` `sensitive` seam.** A SHIP declares each secret as a `userConfig` entry with
`sensitive: true` (masked input, system-keychain storage) and substitutes it as `${user_config.KEY}`
— but **where** it goes depends on transport: a **stdio** server takes it in `.mcp.json` `env`, while
a **remote HTTP/SSE/WS** server takes it in `headers` / `headersHelper` (`env` only reaches a spawned
stdio process, so an HTTP key placed in `env` never authenticates). medley's own config shows the
split: `context7`/`ref` are HTTP and pass their key via `headers` (`x-api-key` / `x-ref-api-key`),
whereas a stdio server like `perplexity` uses `env`. Keychain storage is shared with OAuth tokens
(~2 KB total) — keep values small. Mapping for the credentialed servers below: `MIRO_API_TOKEN` →
`miro_api_token` (stdio, `env`), `PERPLEXITY_API_KEY` → `perplexity_api_key` (stdio, `env`),
`REF_API_KEY` → `ref_api_key` (HTTP, `headers`), `CONTEXT7_API_KEY` → `context7_api_key` (HTTP,
`headers`). Infra/medley-bound secrets (`AZURE_*`, `AZURE_DEVOPS_PAT`, `GITHUB_EVENTS_SECRET`) do not
map — those servers stay repo-level.

**The medley launcher stack — only its Node-pinning layer is medley-local.** medley's
`fnm exec + tools/mcp-launcher/launcher.js` stack solves two problems that generalize differently:

- **GUI-host Node PATH via `.nvmrc` pinning — medley-local.** A plugin does not need it; bundle
  assets via `${CLAUDE_PLUGIN_ROOT}` (+ `${CLAUDE_PLUGIN_DATA}` for a built server's `node_modules`).
- **Windows bare-`npx` `spawn ENOENT` — a general plugin problem, still open.** Plugin-shipped stdio
  MCPs that spawn `npx` fail on native Windows until wrapped with `cmd /c`
  ([anthropics/claude-code#58510](https://github.com/anthropics/claude-code/issues/58510) — OPEN; the
  LSP spawn fix #17312 never reached the MCP spawn path). Do **not** assume the plugin runtime wraps
  `npx` for you: a SHIP that runs `npx` must ship its own `cmd /c` wrapper, while a SHIP that runs a
  bundled `node <server>` sidesteps the bug entirely.

So the `.nvmrc`/fnm layer stays medley-bound, but the Windows-`npx` concern travels with any
`npx`-spawning SHIP.

**Decision table — medley `.mcp.json` (14 servers, audited 2026-07-12).** Verdict is *plugin-carry*,
not "is the server useful". `enabled`/`disabled` = medley `.claude/settings.json`
`enabledMcpjsonServers`/`disabledMcpjsonServers` at audit time.

| Server | Transport | Secret | Verdict | Basis |
|---|---|---|---|---|
| miro | stdio (bundled) | `miro_api_token` (`sensitive`) | **SHIP (cutover+bundle)** | Owner-confirmed 2026-07-12: ships as a **dedicated** `miro` plugin whose whole capability *is* the Miro board server, so it is *useless without the server* (rule 2), not event-storming's optional dependency (event-storming stays degraded-but-functional and ships no server, consuming miro only when connected). The server's TypeScript **relocates** out of `mcp-servers/miro/node` into `plugins/miro` (single source of truth, no copy left behind), bundled to one `dist/index.min.js` invoked as `node ${CLAUDE_PLUGIN_ROOT}/dist/index.min.js` (sidesteps #58510); `MIRO_API_TOKEN` → `userConfig` `miro_api_token` (`sensitive`, keychain); `defaultEnabled: false` so it never auto-starts unasked. First instance of the SHIP convention |
| aspire | stdio (`aspire` native) | — | STAY | medley .NET Aspire orchestration; no general-purpose plugin; infra-bound |
| azure | stdio | `AZURE_CLIENT_SECRET`… | STAY (disabled) | Infra opt-in; disabled (auth-isolation issues); not a plugin concern |
| azure-devops | stdio | `AZURE_DEVOPS_PAT` | STAY (disabled) | Infra opt-in PAT workflow; disabled; work-item tooling uses `gh`, not ADO |
| ccusage | stdio | — | STAY | Live consumer `/claude-ops:claude-observability`; CLI covers the need (rule 1) and claude-ops is multi-skill — shipping would spawn it for changelog/troubleshooting sessions. CLI-first is the preferred future direction |
| chrome-devtools | stdio | — | STAY | Ad-hoc browser/debug; stateful; no migrating plugin structurally requires it (degraded-but-functional) |
| context7 | http | `CONTEXT7_API_KEY` | STAY (CLI-first) | context7 plugin ships `ctx7`; HTTP MCP kept repo-level as fallback |
| github-events | stdio (repo-built) | `GITHUB_EVENTS_SECRET` | STAY | Repo-local broker; stateful `activeFilter`; repo identity via `CLAUDE_PROJECT_DIR` — not repo-agnostic |
| microsoft-learn | http | — | STAY | `/research` + .NET docs; no plugin structurally requires it; degrades to WebSearch/WebFetch |
| nuget | stdio (`dotnet dnx`) | — | STAY | `/packages` + .NET; no dotnet/packages plugin in the locked slugs; .NET-scoped |
| openai-developer-docs | http | — | STAY | codex/OpenAI research; degraded-but-functional |
| perplexity | stdio | `PERPLEXITY_API_KEY` | STAY | `/research` + ai-briefing; multi-consumer, degrades gracefully — shipping would auto-spawn for all discovery sessions |
| playwright | stdio | — | STAY (CLI-first, disabled) | playwright plugin ships `@playwright/cli`; MCP disabled in medley in its favor |
| ref | http | `REF_API_KEY` | STAY | `/research` doc search; degraded-but-functional |

**SHIP: 1. STAY: 13. DROP: 0** — only `miro` clears the SHIP bar, and only once reframed as its own
dedicated plugin (rule 2). The other 13 are CLI-first, degraded-but-functional (their consumer plugin
already runs without them), or infra-bound. Every STAY server has a live consumer; the three disabled
entries are deliberate documented opt-ins, not dead servers. firecrawl already migrated to
`firecrawl-cli` (absent from `.mcp.json`) — it confirms rule 1 rather than being a 15th row.

miro was the closest call and initially landed STAY when weighed as event-storming's optional
dependency. The owner's 2026-07-12 direction reframed it: the Miro board capability becomes a
**dedicated** `miro` plugin, and a dedicated server-wrapper plugin is useless without its server
(rule 2 → SHIP). The original STAY objection — that bundling would auto-start a credentialed MCP for
every event-storming session — is dissolved by `defaultEnabled: false` (the plugin installs disabled;
event-storming keeps its structured-markdown default and consumes miro only when a consumer opts in).
The mechanism is **cutover + bundle**: relocate the server's source into the plugin (the playbook's
reintegration end-state — the repo drops its in-repo copy), single-file esbuild bundle, `node <server>`
over stdio — no npm/registry publish, no consumer token wall, no `npx` (#58510).

**§2 first-party trust accept (miro SHIP).** Recorded here as the single SSOT per the security review:

- **Vendor / provenance.** First-party — a thin wrapper (authored in-house) over Miro's official REST
  API client (`@mirohq/miro-api`); `plugin.json` `author` = Melodic Software. Not a third-party remote
  MCP (Miro's own `mcp.miro.com` was rejected — no board-delete tool, and a third-party remote-egress
  acceptance the playbook denies by default).
- **Transport.** Local `stdio` — a per-session `node dist/index.min.js` process; no listening port, no
  auto-connect to any remote MCP host.
- **Data egress.** Only the Miro REST calls the consumer's own tool invocations make, to
  `api.miro.com`, authenticated by the consumer's own token. No telemetry, no other outbound network.
- **Token scope.** `MIRO_API_TOKEN` → `userConfig` `miro_api_token`, `sensitive` (system keychain,
  never `settings.json`); the consumer supplies and scopes it. The server exits at startup if unset.
- **Opt-in.** `defaultEnabled: false` — installs disabled; the consumer enables it deliberately.

## Plugin-form caveats (works in-repo, breaks as a plugin)

Catalog these per migration; they are the usual failures when an in-repo skill becomes a plugin.

- **Cache isolation.** Installed plugins are copied to `~/.claude/plugins/cache`. Any reference to files
  outside the plugin directory (`../../tools/...`, `.claude/rules/...`) breaks. Fix: bundle dependencies
  inside the plugin and reference them via `${CLAUDE_PLUGIN_ROOT}`; persist state via `${CLAUDE_PLUGIN_DATA}`.
- **Namespacing.** Components are namespaced by the plugin's own `name`, not the marketplace name —
  an in-repo `/foo` becomes `/<plugin-name>:foo`. Internal cross-references to the bare name break —
  update them.
- **Agent shadowing.** Project/user `.claude/agents/` override same-named plugin agents. A leftover
  in-repo copy masks the plugin version until removed from the source repo.
- **Headless registration.** `extraKnownMarketplaces` auto-registration requires the interactive trust
  dialog; CI/headless/cloud must run `claude plugin marketplace add` explicitly or pre-seed via
  `CLAUDE_CODE_PLUGIN_SEED_DIR`.

## Per-plugin migration gate

For each skill/hook/agent being migrated:

1. **Research fresh.** WebFetch the official docs for every component involved (see `CLAUDE.md`).
2. **Scope one capability.** One cohesive plugin; no grab-bags.
3. **De-couple from the source repo.** Remove hardcoded paths/names; route project-specifics to the
   consumer's context.
4. **Bundle + isolate.** Move required assets inside the plugin; reference via `${CLAUDE_PLUGIN_ROOT}`.
5. **Expose extensibility.** Declare `userConfig` for consumer choices; document each option.
6. **Strip PII / secrets.** Hard gate — before the first commit.
7. **Idempotent, modular, extensible.** Re-running is safe; pieces compose; variability is declared.
8. **Validate.** `claude plugin validate`; test with `--plugin-dir` in a clean repo that is NOT the
   source repo (proves repo-agnosticism).
9. **Version.** Set an explicit semver `version` in `plugin.json`. A later bump that changes behavior a
   consumer depends on records the change in the plugin's changelog — see "Version pinning and update
   delivery" above.
10. **Publish.** Add the entry to `.claude-plugin/marketplace.json` — the plugin `source` is the
    `./`-prefixed relative path (e.g. `./plugins/<name>`). Bare names fail `claude plugin validate --strict`
    even with `metadata.pluginRoot` set, despite the marketplaces-doc example to the contrary (verified
    2026-06-23). Then run `claude plugin validate --strict <repo-root>` to validate the **catalog manifest
    itself** — a bad entry surfaces only there, not in per-plugin validation. Document the plugin in the README.

## Migration order, PRs & parallelization

**Seams first** (Fowler's Branch by Abstraction). Establish the shared foundations — the conventions in
this playbook, the shared `lib/` source of truth (see "Shared code across plugins"), and the
persistence/config pattern above — in one small sequential PR *before* fanning out. Everything downstream
builds on those seams.

**Per-unit atomic PRs, authored in parallel.** One PR per cohesive migratable unit: small changesets
review faster and more thoroughly, and the per-unit acceptance gate makes each one atomic and
rollback-safe. Parallelize with one worktree (or worker) per unit — **conflict-free by design**, because
each plugin is an isolated `plugins/<name>/` directory, so N units become N concurrent PRs with no merge
conflicts. Group units into one PR only when they are hard-coupled, or when the change is a single
mechanical bulk edit.

**Expect one shared-file conflict, resolved at merge.** The two files parallel PRs all touch are the
catalog manifest (`.claude-plugin/marketplace.json`) and the README catalog table. Those conflicts are
expected — resolve them by **serializing the final merges**, not by serializing authorship.

**Gate every unit before publish.** Each unit clears its parity / acceptance gate — the per-plugin
migration gate and the plugin-acceptance security review below — before it ships.

**Sequence heuristic.** Order lowest-coupling units first (clean, self-contained units with graceful
degradation). Defer risky units (hard external dependencies, no graceful degradation) and any
license-gated units to per-item triage rather than a blanket hold. The ordering is reversible.

## Plugin-acceptance security review

A plugin runs code on the consumer's machine and can wire Claude to external systems. **Every plugin accepted
here — new, or a version bump that adds a trust surface — passes this review** in addition to the migration
gate above (whose step 6 gates PII/secrets). **Deny by default** any surface below that can't be justified.
Facts verified against the plugins/MCP reference 2026-07-09; re-verify per the `CLAUDE.md` fresh-docs mandate.

1. **Code execution — hooks & scripts.** A hook command runs shell on the consumer's machine on matched events,
   with `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`, `${user_config.*}`, and any
   `${ENV_VAR}` interpolated in. Check: which binaries it spawns; whether it mutates files in place and is
   **advisory** (exits 0, never blocks) vs gating; no `eval` / `curl … | sh` / outbound network; untrusted
   input (file contents, tool args, PR/issue text) never flows unquoted into a shell; a kill switch
   (`HOOK_<PLUGIN>_ENABLED`) exists.
2. **MCP servers — `.mcp.json` / inline in `plugin.json`.** `miro` is the **only** plugin that ships one
   (local `stdio`, bundled — see its §2 trust accept above); no plugin ships a **remote** MCP server, which
   remains the higher-scrutiny case. A plugin's MCP server **starts automatically when the plugin is enabled**
   (subject to per-server approval), unless it ships `defaultEnabled: false`. Check: the server host/URL and who runs it (first-party vs a third party you're delegating trust
   to); transport (local `stdio` vs remote `http`/`sse`/`ws`); **what data leaves the machine** — a remote
   server receives whatever Claude sends and, if it returns external content, is a prompt-injection vector
   (official guidance: "Verify you trust each server before connecting it"); auth shape (header/Bearer/OAuth)
   with any token sourced from `userConfig` `sensitive` or an env var, **never hardcoded**; a stated reason the
   capability can't be a local `stdio` server. **Do not accept a third-party remote MCP server** without an
   explicit recorded trust decision naming the vendor, the data egress, and the token scope.
3. **Consumer config — `userConfig`.** Any credential/token option MUST set `"sensitive": true` — that masks
   input and stores the value in the system keychain (or `~/.claude/.credentials.json`), **not** `settings.json`.
   Non-sensitive values land in `settings.json` under `pluginConfigs[<id>].options` and are readable — never put
   a secret there. Endpoints and toggles are fine as non-sensitive. Every option is documented.
4. **Cache isolation — no reach-outs.** References only files inside the plugin via `${CLAUDE_PLUGIN_ROOT}`;
   persists state in `${CLAUDE_PLUGIN_DATA}`. No `../` reach-outs, no absolute paths, no reading consumer files
   outside `${CLAUDE_PROJECT_DIR}`.
5. **Data egress — telemetry & network.** Any telemetry (e.g. `HOOK_TELEMETRY_SINK`) is opt-in (unset = exact
   no-op), never writes to the hook's stdout/`additionalContext` channel, and emits only the declared envelope —
   no payload beyond the documented schema. Name any other outbound network call and justify it.
6. **Provenance & third-party trust.** Verify authorship (does `plugin.json` `author` match who actually
   submitted the PR?), license, and that the source is what it claims. A plugin that promotes or wires a
   third-party SaaS is a trust delegation — record accept/deny with rationale. Note the platform already blocks
   plugin-shipped **agents** from declaring `hooks` / `mcpServers` / `permissionMode` "for security reasons" —
   don't design around that.

Record accept/deny + rationale for any plugin touching surfaces 2, 5, or 6; a later version bump that
introduces a new surface re-triggers this review.

## Local development loop

For a plugin that already ships here, iterate against your local clone without re-publishing and
without changing any consumer's marketplace registration. `--plugin-dir` loads a plugin straight from
a directory; when its `name` matches an installed marketplace plugin, **the local copy takes
precedence for that session**, so you exercise working-tree edits against the installed copy without
uninstalling it (verified 2026-06-24).

```shell
# from this repo root — point at the plugin directory, not the marketplace root
claude --plugin-dir ./plugins/<name>
```

- **Edit, then `/reload-plugins`** to pick up changes without restarting — it reloads skills, agents,
  hooks, and plugin MCP/LSP servers, reading the files on disk, so no commit or reinstall is needed.
- **Session-scoped and non-destructive.** The override lasts only for that session and never edits a
  consumer's `extraKnownMarketplaces`; the published registration stays on its GitHub remote. The lone
  exception: `--plugin-dir` cannot override a plugin that *managed* settings force-enable or
  force-disable.
- **Trust.** A locally loaded plugin carries the same trust considerations as any source — only load
  directories you control.
- **Then ship.** Run `claude plugin validate` before opening a PR; after merge, consumers pull the
  change with `/plugin marketplace update melodic-software`, gated by the `version` bump in `plugin.json`.

## Fresh-consumer onboarding

Reintegration (below) covers a repo that already ran an in-repo copy and now switches to the plugin. A
**brand-new** repo adopting the marketplace for the first time follows this checklist:

1. **Register the marketplace — checked in for clones.** Interactive: the trust dialog on first
   `/plugin` use registers the marketplace and installs enabled plugins. For project-wide adoption,
   declare the marketplace in the project's checked-in `.claude/settings.json` `extraKnownMarketplaces`
   (headless: `claude plugin marketplace add <repo> --scope project`). A bare `claude plugin marketplace
   add <repo>` writes to *user* settings, so a fresh clone or CI agent on another machine would carry the
   enabled plugin but have no registered marketplace to resolve it from — mirror the Reintegration
   cutover, which pairs both fields in the project settings.
2. **Enable at project scope** so every clone inherits it — declare `enabledPlugins` in the same
   checked-in `.claude/settings.json` (choose user scope instead for machine-wide, not per-repo).
3. **Install and seed config on one fresh install.** `--config` is accepted only on a fresh install
   (smoke-test C), so pass every option on the install command, never a later call: `claude plugin
   install <plugin>@<marketplace> --scope project --config KEY=VALUE …` (repeatable, schema-validated).
   Non-sensitive options land in the **user** `settings.json` `pluginConfigs` regardless of the enable
   scope; a sensitive value still routes to the keychain (smoke-tests A and C). Interactively, install
   prompts for scope, then each configurable plugin's setup action (or `/plugin configure`) writes the
   tracked config.
4. **Headless prompting caveat.** Install never prompts non-interactively — a required `userConfig`
   option left unset does **not** block the install; it stays advisory until set (smoke-test C). Seed
   every required option on the install command so the plugin does not run unconfigured.

## Reintegration — a consumer adopts the published plugin

The forward migration (above) ends at *publish*. The lifecycle closes when the source repo stops running
its in-repo copy and instead **consumes the published plugin** — one source of truth, and the repo
dogfoods the marketplace. Reintegration is a *consumer-side* change: adapt through the documented
extension points, never by teaching the plugin a consumer's specifics.

**The plugin is generic; the consumer's own seams restore its specifics.** Map each behavior the
in-repo hook had that the generalized plugin dropped to one of these, in order:

- **Kill switch / toggles** → the plugin's own env var, set in the consumer's `settings.json` `env`
  (the name changes from the in-repo `HOOK_<OLD>_ENABLED` to the plugin's `HOOK_<PLUGIN>_ENABLED`).
- **Project conventions** → for a hook plugin, the consumer's own tool config files that the hook already
  reads (`biome.json`, `.shellcheckrc`, `.editorconfig`, …) — that is where these plugins pick up project
  conventions, **not** `CLAUDE.md`. (`CLAUDE.md` / `.claude/rules` reach only a plugin's *skill/agent*
  components, which run in Claude's model context; hook scripts see only env vars and file-based config.)
- **Telemetry / observability** → the consumer's own **telemetry sink**. This is the key seam: the
  plugin emits the generic telemetry envelope contract to `HOOK_TELEMETRY_SINK`, and the consumer's sink
  script translates that envelope into the consumer's local observability shape. A consumer whose prior
  hook emitted a different status or hook-identity (e.g. `status=error` on a surfaced violation, or a
  legacy hook name) restores that contract **in its own sink**, by remapping the plugin's native envelope
  (`status=ok` + populated `findings`) — not by changing the plugin. Before remapping, verify how the
  consumer's observability actually keys events (e.g. on `status` vs a derived `exit_code`/findings count),
  so the remap preserves the real contract rather than a guessed one.

If a genuine specific has **no** seam, that is a real plugin gap → add a declared extension
(`userConfig`, or a new env var consistent with the plugin's existing ones) — but only when it carries
real behavior, not cosmetic prose a consumer's `CLAUDE.md` already establishes. Resist adding config
surface to a published plugin for a single consumer's low-value nicety.

**Cutover checklist:**

1. Register the marketplace in the consumer's `extraKnownMarketplaces` and enable the plugin in
   `enabledPlugins` (project `settings.json`, so clones inherit it on trust — the interactive trust prompt
   both registers and installs the enabled plugin). Headless/CI has no such prompt, and registering a
   marketplace does not install its plugins, so do both explicitly: `claude plugin marketplace add <repo>`
   then `claude plugin install <plugin>@<marketplace> --scope project` — otherwise the marketplace is known
   but the plugin is absent, and step 3's verify edit would run with no plugin hook.
2. Rewire the kill-switch env var to the plugin's name; keep the `HOOK_TELEMETRY_SINK` wiring and the
   sink script (the bridge), adapting the sink for any observability-contract divergence.
3. **Verify before retiring** the old hook (blue-green — keep it recoverable, but never run both on the
   same edit). Matching `PostToolUse` hooks run concurrently, so leaving both registered would race two
   formatters on the just-edited file (last-writer-wins clobbering, plus doubled telemetry and context) —
   idempotence only makes *serial* re-runs converge, not concurrent writes safe. So **exactly one is
   active at a time**: disable the in-repo hook by setting its kill-switch env var to `"false"` (or, if it
   has none, removing its registration entry — `settings.json` is JSON, so toggling the value or removing
   the entry is the edit, never a `//` comment). With the old hook off and the plugin enabled, edit a
   governed file and confirm: the plugin formats/lints and surfaces findings, the telemetry sink receives
   the expected envelope (so a broken remap is caught now, not when observability is next needed), and the
   consumer's hard gate (commit hooks, CI) is untouched — those are independent of the edit-time hook. If
   verification fails, **disable the plugin first, then re-enable the old hook** (always flip one off as you
   turn the other on) and debug before retrying — so the two never run together and there is never a
   no-hook gap.
4. Only once verified, remove the in-repo hook's `settings.json` registration and delete the hook script
   **and its test**.

**Bootstrap-direction caveat.** While a repo is still the harvest *source* (its hooks are mid-migration
out), reintegrating one plugin makes it consume one plugin while still running the rest in-repo — a mixed
state. Flip a repo from source to consumer deliberately, not incidentally, and ideally once the repo's
ported plugins can move together.

## Shared code across plugins — decision record (2026-07-04)

Decided when four plugins carried byte-identical `hooks/hook-utils.sh` copies — the Rule-of-Three
threshold below, exceeded. The mechanism is **single source of truth at authoring time, plain copies
at runtime**:

- `lib/hook-utils.sh` is the only copy to edit. `scripts/sync-hook-utils.sh` propagates it into every
  carrying plugin; a plugin opts in by committing an initial `hooks/hook-utils.sh` copy.
- CI (`hook-utils-sync` lane) fails a PR when any plugin copy drifts from the source, and when the lib
  changed but a carrying plugin's manifest version did not — the plugin `version` is the update cache
  key, so an unbumped plugin never delivers the change to consumers.
- Runtime is untouched: each installed plugin stays self-contained under cache isolation, with no
  cross-plugin coupling and no change to the one-plugin install UX.

Alternatives weighed (docs verified 2026-07-03):

- **Dependency plugin carrying the lib — rejected as not viable.** A hook sees only its own
  `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`; no variable or documented mechanism exposes a
  *dependency's* install path, and cache directories are per-version (with a commit-SHA suffix for
  tag-resolved dependencies), so computing the path is unsupported by design (plugins-reference
  "Plugin caching and file resolution"; plugin-dependencies guide). Revisit iff Claude Code ships a
  documented dependency-path variable — that would also allow sharing the lib beyond this marketplace.
- **Marketplace-internal symlinks — deferred.** Documented mechanism: a symlink from a plugin to a
  file elsewhere in the same marketplace is dereferenced at install, copying the target's content into
  the cache — native SSOT with no sync script (plugins-reference "Share files within a marketplace
  with symlinks"). Deferred because such symlinks are *skipped* for `--plugin-dir` / local-path
  installs (breaking the local development loop above) and are fragile to author and clone on Windows,
  the primary environment on both the authoring and consuming side. Revisit if the dev loop stops
  depending on `--plugin-dir` or the Windows constraint lifts.
- **Copies with only a byte-identity CI gate — subsumed.** The chosen shape is that gate plus a
  canonical source and one sync script, removing the edit-×N-by-hand step at negligible cost.

The lib's unit tests live beside the source as one consolidated suite (`lib/hook-utils.test.sh`,
run by the same CI lane) rather than as per-plugin copies — byte-identity of the copies means
testing the source covers them. Plugins keep only their own black-box hook contract tests.

## What to wait on / avoid for now

- Don't pre-build cross-plugin `dependencies` graphs until two plugins genuinely share a need.
- Don't abstract a shared library before a second consumer exists (Rule of Three); at the threshold,
  the shared-code decision record above is the settled shape — extend it rather than re-deciding.
- Don't rely on any mechanism not confirmed from current docs this session — if a customization need has
  no proven native path yet, record it here as a gap and keep the workaround in the consumer's repo until
  the native mechanism is verified.

## Deferred surfaces — decision record (2026-07-12)

Three general-purpose surfaces in the harvest-source repo (`melodic-software/medley`) are held out of this
wave's plugin migration deliberately, each with an explicit revisit trigger — recorded here so the deferral
is a decision, not a silent omission. The medley side carries a thin pointer back to this record at each
surface (the workflow-engine authoring rule, the `onboard` skill, and the `gh-bot.sh` bot-identity
convention), so a contributor who touches a deferred surface finds the trigger without leaving that repo.

- **Workflow engines** (`code-review.js`, `codebase-review.js`, `deep-research.js`,
  `research-deep-fanout.js`, `skills-audit.js`, `skills-evals.js`, `skills-remediate.js`): not a plugin
  component per current docs — the `Workflow` tool loads an engine script from disk and a plugin manifest
  has no native slot to ship one, so these may be removed entirely rather than migrated. **Revisit
  trigger:** the engines survive the next usage review (still earning their keep) → package as a plugin
  skill that dispatches the engine through the `Workflow` tool's `scriptPath`, resolved under
  `${CLAUDE_PLUGIN_ROOT}`, with a smoke test specced for that dispatch path before packaging.
- **`onboard` skill:** repo-specific today — its phase gates encode this repo's exact runtime, linter, and
  tooling pins. **Revisit trigger:** a second repo needs environment-prerequisite auditing → extract a
  generic core through the extensibility-contract seams (the convention-resolution ladder infers or asks
  for the per-repo pins), leaving repo specifics in tracked config rather than baked into the skill.
- **`tools/github-auth` (`gh-bot.sh`):** hardcodes the org's bot App / installation identity. **Revisit
  trigger:** a second repo needs bot-actor GitHub operations → parameterize org / App / installation
  through the seams (`userConfig` scalars, `sensitive` for the key) instead of standing up a second
  hardcoded wrapper.

## Unused official plugin components — decision record (2026-07-12)

Three official plugin components the marketplace does not yet use, evaluated for adoption against the
enforcement hierarchy (default **REJECT** unless the value is concrete and not already covered by an
existing mechanism). Facts verified fresh 2026-07-12 per `CLAUDE.md` "Fresh-docs mandate". Verdict for
all three: **REJECT now**, each with an explicit revisit trigger — no implementation issues emitted (zero
accepted).

- **Monitors** (`monitors/monitors.json` / `experimental.monitors`) — **REJECT.** Both candidates are
  either already covered or not concrete: a PR/CI watch duplicates `/source-control:pull-request monitor`
  and a consumer's channel-mode PR watch (no gap), and a claude-ops collector-health watch carries no
  concrete recurring pain that outweighs adopting an `experimental.*` component whose manifest schema may
  change between releases (and which is skipped on the hosts / telemetry-disabled configs where the
  Monitor tool is unavailable). **Revisit trigger:** monitors leave the `experimental` key AND a concrete
  recurring in-session watch need surfaces for a shipped plugin, scoped via the documented `when:
  "on-skill-invoke:<skill-name>"` monitor field so it starts only on demand rather than at session
  start. Upstream:
  <https://code.claude.com/docs/en/plugins-reference#monitors>,
  <https://code.claude.com/docs/en/tools-reference#monitor-tool>.
- **`bin/`** (executables added to the Bash tool `PATH`) — **REJECT** as a marketplace-wide adoption.
  Plugin-owned scripts already ship via `${CLAUDE_PLUGIN_ROOT}/scripts/` invoked by full path (the
  established pattern — see "Shared tools and scripts seam" above); `bin/` adds only bare-command-on-`PATH`
  invocation, which risks name collisions with the consumer's own commands, so it earns its place only
  where a script is meant to be run as a bare command by the consumer. The one live candidate — the
  knowledge plugin's extraction tooling — is owned by its publish issue #1373; the `bin/`-vs-`scripts/`
  call belongs there, not duplicated here. **Revisit trigger:** a shipped plugin has a script the consumer
  invokes as a bare command (not an internal helper). Upstream:
  <https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout>.
- **`subagentStatusLine`** (plugin `settings.json`) — **REJECT.** Purely cosmetic: it re-formats the
  subagent panel row with no functional capability, so it does not clear the default-REJECT bar; its
  richest inputs (per-row model + context-window size for a context percentage) additionally require a
  recent Claude Code minimum. Candidate home was claude-ops. **Revisit trigger:** a concrete operational
  need for custom subagent-row data during orchestration, not a presentation preference. Upstream:
  <https://code.claude.com/docs/en/statusline#subagent-status-lines>,
  <https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout>.
