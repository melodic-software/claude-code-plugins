# Migration playbook

How skills, hooks, and agents become reusable plugins in this marketplace. One plugin is migrated at a
time: lift it out, make it work in plugin form and in any repo, build in configuration and extensibility,
vet it against best practices, then publish.

The durable design policy is [Plugin philosophy](PLUGIN-PHILOSOPHY.md). This playbook applies that
policy to migration, validation, cutover, and release; it does not redefine the policy.

All schema and behavior claims below were verified against the official docs on 2026-06-22 (the
"Reintegration" section's marketplace-settings claims — `extraKnownMarketplaces` / `enabledPlugins` in a
project's `settings.json` — on 2026-06-29, against the discover-plugins "Configure team marketplaces"
guide; the "Extensibility contract v2.1" sections and their smoke tests on 2026-07-12 against Claude
Code 2.1.207; the Organization and Naming sections' skill-namespace and skill-listing claims on
2026-07-15, and the decomposition/trigger-continuity procedure on 2026-07-16, against the skills doc).
Re-verify fresh before acting — see `CLAUDE.md` "Fresh-docs mandate".

## Organization — one plugin per cohesive concern

The philosophy's "one cohesive capability" is also the packaging boundary: **one plugin per cohesive
concern or capability**, grouped in the catalog through `category` / `tags` rather than by splitting.
A cohesive plugin MAY hold several units — a first-party plugin bundles many skills of one concern, a
hooks plugin bundles many hooks of one concern. One-unit-per-plugin is not the norm; do not ship a
plugin per hook.

- **Skills group by capability.** Distinct capabilities are distinct plugins; a single capability's
  always-together facets bundle (e.g. a prototyping capability's `logic` and `ui` skills ship together).
- **A skill splits only on distinct discovery intent, never per subcommand.** Two skills are
  warranted when their trigger vocabularies differ — a user reaching for each says different things;
  a capability's subcommands stay action arguments of one skill. The restraint has a context-cost
  basis: the listing of skill names and descriptions loads into every session, and each entry's
  combined description text is truncated at 1,536 characters in that listing
  ([skills](https://code.claude.com/docs/en/skills), fetched 2026-07-15) — every extra skill is an
  always-paid context line. The standing exception is the `setup` lane, always its own skill with
  `disable-model-invocation: true` — see the philosophy's "Setup is explicit and repeatable".
- **Hooks group by concern.** Per-hook selectivity comes from a `userConfig` toggle (read through
  the hook-process `CLAUDE_PLUGIN_OPTION_<KEY>` mirror), a `matcher`, or an `if` guard —
  author-managed control inside the bundle.
- **Whole-product / vendor-brand bundles** driven by distribution are a separate, allowed shape.

### Decompose an oversized skill before packaging it

Migration is the point to correct a mega-skill boundary, not preserve it accidentally. Apply this
procedure before choosing plugin and skill directories:

1. **Inventory the source contract.** Record each responsibility, output, supporting asset,
   cross-skill reference, eval, and auto-invocation phrase from `description` plus `when_to_use`.
   Claude Code uses that listing text to decide whether to load a skill, so trigger phrases are
   behavior, not marketing copy
   ([skills](https://code.claude.com/docs/en/skills), fetched 2026-07-16).
2. **Classify the seams by discovery intent.** Facets of one capability stay in one plugin but may
   become focused sibling skills when users reach for them with different vocabulary. Capabilities
   with independent purpose, lifecycle, or trust surface become separate plugins. Subcommands and
   depth variants remain arguments; they are not decomposition seams.
3. **Name the focused skills by KIND.** Action skills take focused action verbs; knowledge skills
   take focused noun phrases. When the split is facets-of-one-capability, keep the parent concept as
   the plugin name and move only the focused leaves below it. `prototype` is the worked precedent:
   one throwaway-prototyping capability, distinct `logic` and `ui` discovery intents, shared
   discipline at plugin scope.
4. **Preserve common policy once.** Put genuinely shared instructions/assets at plugin scope and
   have each sibling skill cite them. Do not duplicate a former mega-skill preamble into every leaf.
5. **Prove trigger continuity.** Build a migration table mapping every old trigger phrase to one
   successor skill's quoted `Use when:` phrase. Add explicit negative routing boundaries where sibling
   intent could overlap. Run `/skill-quality:check` with `CHECK_SKILL_BASE_REF` for every same-path
   rewrite; check 3 fails when a quoted trigger disappears. A rename or split creates new paths, so
   the checker deliberately skips them — the cross-skill migration table and focused routing evals
   are the required evidence that the union of successor descriptions still covers the source.
6. **Update callers and exercise routing.** Rewrite slash references for the new namespaced leaves,
   validate every manifest and eval file, then exercise both automatic invocation and explicit slash
   invocation from a clean consumer repo. Do not retire the source skill until each mapped trigger
   routes to its intended successor and ambiguous prompts choose the correct facet.

The result is a smaller loading surface per invocation without losing discovery behavior. Do not
split merely to shorten a file: progressive disclosure into supporting files handles size when the
skill still has one discovery intent.

**Why capability, not grab-bag.** Enabling and disabling happen at the plugin level, and the
`skillOverrides` setting explicitly *excludes* plugin skills (those are managed through `/plugin`), so
there is no clean per-skill à-la-carte toggle. Bundling several skills is therefore acceptable only
*within* one cohesive capability you would never split — it forbids lumping *distinct* capabilities into
a single plugin. Hooks differ: a per-hook `userConfig` toggle gives clean per-hook control inside a
bundle. The discriminating axis is **silent-always-on** components (hooks — keep atomic, or toggle via
`userConfig`) versus **opt-in-per-invocation** components (skills — group by capability).

**Buckets are catalog metadata, never structure.** Category grouping lives in `marketplace.json`
`category` / `tags` and catalog docs only: the disk layout stays flat (`plugins/<name>`, no
`plugins/<bucket>/<name>` nesting), and a bucket never appears in a plugin name or namespace.
Namespaces name capability domains; categories are curation.

**Boundaries are defended by design arguments, never incumbency.** A plugin's shape is justified by
change-together, useful-alone, and distinct discovery intent — not by the fact that it already ships
that way ("current state is evidence, never justification" — `melodic-software/standards`
`conventions/engineering/engineering-philosophy.md`).

## Naming

Name a plugin and its units by this precedence — an earlier rule wins on conflict:

1. **Semantic accuracy, zero confusion.** The capability is unambiguous from the name; qualify an
   overloaded generic term (a bare `audit` is collision bait).
2. **Official docs + ecosystem precedent.** kebab-case, no spaces; the namespace is the plugin's own
   `name` (not the marketplace name); mirror established Claude Code patterns.
3. **Explicit naming.** A domain-noun plugin name; no noise suffix (`-plugin` / `-tool` / `-helper`);
   no unit-type suffix (`-hook` / `-skill`) unless load-bearing; names track their semantic scope.

Applying that precedence, the grammar of an invocation is `/<namespace>:<skill>`:

- **The namespace (plugin `name`) is a noun, kebab-case — never a bare verb.** A **gerund** for an
  activity domain (`planning`, `debugging`, `testing`); a **plain noun** for a subject domain
  (`source-control`, `architecture`, `work-items`). Semantic accuracy binds the whole namespace:
  the noun must be true of *every* skill under it.
- **Skill name follows its KIND.** An action / user-invoked skill is an **action verb**
  (`create-plugin`, `review-pr`); a knowledge / model-invoked skill may be a **noun-phrase**
  (`principles`, `methodology`). The verb heuristic scopes to action skills only — a `noun:noun`
  invocation is correct for a knowledge skill.
- **`/name:name` doubling is a naming defect, not idiomatic.** A stutter means one of the two names
  is failing at its job — the namespace is not naming the domain, or the skill is not naming its
  action. Fix it by, in preference order: rename the skill to its real action verb; rename the
  plugin to its domain noun; decompose, when the single skill actually hides distinct discovery
  intents (per the Organization section's split rule above). Two exemptions:
  **root-echo** — the domain's core action shares the domain's root word
  (`implementation:implement`, `code-tidying:tidy`, `work-items:work`) — and
  **wrapper-echo** — a single-skill vendor-CLI wrapper whose one router skill repeats the tool
  name (`firecrawl:firecrawl`, `playwright:playwright`), per the philosophy's Naming section.
  Both are honest naming, not true doubling, and are accepted.
- **Skill families order base-concept-first.** Sibling skills sharing a base concept put the base
  first (`design`, `design-handoff`, `implement`, `implement-dispatch`) so prefix typeahead and
  sorted listings group the family. A standalone skill keeps natural English order (`batch-simplify`, `quality-gate`).
  A structural variant earns a new sibling name; a depth/intensity variant takes an argument, never
  a sibling. **Execution tier counts as structural:** a variant that changes execution *topology* — an
  isolated forked subagent (`context: fork`) or a heavier dispatch tier (workflow engine, forked
  subagent, or inline fallback) — is fixed in frontmatter and cannot be a runtime argument, so it earns
  a sibling. `discovery`'s `explore-deep` (a `context: fork` variant of `explore`) and `research-deep`
  (a dispatch variant of `research`) are siblings on this axis; the `-deep` suffix names that isolation
  tier, not a depth knob on the same execution path — a true effort knob on one execution path still
  takes an argument.
- **A vendor-CLI plugin that decomposes names its skills after the vendor's own CLI verbs.** When a
  tool-scoped plugin splits into multiple skills, it mirrors that CLI's verb vocabulary —
  `/playwright:test` would mirror `npx playwright test`; a firecrawl decomposition would use
  `scrape` / `crawl` / `map` per `firecrawl-cli` — the consumer already knows the vendor's verbs.
  While it remains a single-skill router, the wrapper-echo exemption above applies instead.
- **Generic skill names are safe under namespacing** (`help`, `list`, `update`) — the overloaded-term
  caution governs plugin *identity*, not a namespaced skill leaf.
- **Tool-scope shows up as brand-in-name, not a structural split.** A branded name signals a tool-scoped
  plugin; a plain domain-noun signals a tool-agnostic one. No marketplace separates plugins by tool-scope
  — do not formalize such a split.

**Built-in collisions never force a plugin skill's name.** "Plugin skills use a
`plugin-name:skill-name` namespace, so they cannot conflict with other levels"
([skills](https://code.claude.com/docs/en/skills), fetched 2026-07-15) — a shadow-dodge name is never
*required*. The catalog's historical dodge names (`quality-gate`, `fanout`,
`batch-simplify`, `research-deep`) stand or evolve on their own merits, not out of collision fear.
The one residual caution is model-side: avoid a skill leaf name *identical* to a bundled skill's
(auto-invocation ambiguity when the model matches descriptions); similarity alone is fine.

**That namespace guarantee covers invocation, not the slash-command listing.** The picker labels a
row with the skill's short name and keeps the namespaced form as a hidden alias, so a leaf name
shared across plugins reads identically in the list even though each is separately invocable; the
plugin name reaches the reader through the description, which renders as `(<plugin-name>)
<description>`. See the philosophy's Naming section for the full display contract. Two consequences
for this playbook: prefix typeahead groups a family by its **leaf** name, which is what the
base-concept-first rule above is buying; and a deliberately shared leaf name (`setup` across every
plugin that ships one) is legible only if each description's first clause names its object.

## Extensibility model — what works today

These are the proven, documented mechanisms for consumer customization that do not confuse the agent.
Prefer them in this order; the earlier ones are simplest and least surprising.

| Mechanism | What it does | Use for |
|---|---|---|
| Consumer `CLAUDE.md` / `.claude/rules` | The skill reads the consuming project's own context and rules | Project-specific conventions, naming, policies — the default extension surface |
| `${CLAUDE_PROJECT_DIR}` | Path to the consumer's project root, substituted in hook/MCP/monitor commands and exported to subprocesses | Referencing project-local scripts/config |
| `userConfig` → `${user_config.KEY}` | Values Claude Code prompts for at enable time (typed: string/number/boolean/directory/file, optional sensitive). Substitutes as `${user_config.KEY}` in MCP/LSP configs and exec-form hook commands; non-sensitive values also substitute into skill/agent content. Shell-form hook commands, monitor commands, and MCP `headersHelper` reject this substitution. Hook processes receive every value as `CLAUDE_PLUGIN_OPTION_<KEY>`; a Bash tool call made by a skill does not (see the [smoke-test record](extensibility-contract-smoke-tests.md)). Non-sensitive values are stored under `pluginConfigs[<id>].options` in user settings and read from user, `--settings`, or managed settings; project/local entries are ignored. Sensitive values use the macOS Keychain or `~/.claude/.credentials.json` where no supported keychain exists | Endpoints, toggles, tokens — personal or administrator-supplied config without editing the plugin |
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
   `string[]` type); mark a credential `sensitive` so it lands in Claude Code's secure credential
   storage, never `settings.json`.
   Non-sensitive values store under `pluginConfigs[<id>].options` in user settings and are read from
   user settings, `--settings`, or managed settings only; project and local entries are ignored since
   Claude Code 2.1.207. Use for endpoints, toggles, tokens, and personal path knobs. The `directory` /
   `file` type is a UI hint, not a validator — a `--config` value is stored verbatim with no existence
   check and no normalization to absolute (smoke-test A).
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
     [`docs/conventions/ecosystem-commands/`](conventions/ecosystem-commands/README.md); second
     instance: [`docs/conventions/topic-docs/`](conventions/topic-docs/README.md)).
   - **Profiled folder for audience/deployment variants.** When ONE plugin's tracked config varies by
     *audience* or *deployment* — a different framing, ranking lens, or branding per team / client /
     context — add a profile axis to the folder form. Files at `.claude/<plugin>/` are the **default
     profile**; each `.claude/<plugin>/<profile-name>/` subfolder is a **named profile** that overlays
     the default per key (the same additive semantics the layering contract below fixes — a named profile
     refines the root, absent keys fall through). A single-config consumer never nests: its files sit at
     the root, which *is* the default profile, so growing a profile later is additive (drop a sibling
     subfolder), never a reorg — and there is no reserved `default/`/`team/` name to collide with. Pick
     the active profile by the convention-resolution ladder: exactly one named profile subfolder present
     → use it; several → an `active_profile` `userConfig` scalar (seam 1) or a per-invocation
     `--profile <name>` argument selects; none → the root default. This is a one-increment PRECEDENT-EXTENSION of the folder
     form, for a plugin that could ever profile — ship the **folder** form, since the single-file form
     cannot grow a profile without a file→folder reorg. Distinct from the concern-named folder above: that
     splits config across *plugins* (concern axis); this splits it across *audiences* within one plugin
     (profile axis) — the two compose (`.claude/<concern>/<profile-name>/`). Reference adopter:
     [`ai-briefing`](ai-briefing-design.md).
   - **Resolution + override semantics, overlay naming, and the recommended consumer `.gitignore`
     line** are owned by [`docs/conventions/config-cascade/`](conventions/config-cascade/README.md)
     — the layering axis is cross-cutting, so it is contracted once there rather than restated per
     seam. A surface declares its own keys and schema here or in its own owner doc, and points there
     for how its layers merge.
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
2. Absent → explore the repo and infer, then **persist the inference** into tracked project config
   (seam 2) so the next run is deterministic. For a personal scalar (seam 1), direct the user to Claude
   Code's native plugin configuration surface instead.
3. Cannot infer → ask the user, and offer to persist the answer.
4. Otherwise → a safe generic default.

No baked repo assumptions, ever. A plugin never hardcodes a consumer's layout; it reads a declared
value, infers-and-records, or asks — never guesses silently.

This ladder is the runtime application of the durable convention posture owned by
[PLUGIN-PHILOSOPHY.md § Two-lane convention posture](PLUGIN-PHILOSOPHY.md): a pre-prescribed
convention is a hardcoded dependency, so a plugin ships a default only in lane 1 (a good-practice
value that cannot conflict in any consuming repo) and otherwise takes lane 2 — its setup discovers
the consumer's convention and externalizes it as an extensibility point the ladder then resolves.

## Setup action — required iff the criteria hold

Whether a plugin needs a `setup` skill, and the uniform contract it follows (`setup` name,
`disable-model-invocation: true`, `check` + `apply` actions, non-interactive completion), is owned
by [PLUGIN-PHILOSOPHY.md § Setup is explicit and repeatable](PLUGIN-PHILOSOPHY.md). Migration work
applies it as-is. Playbook-specific additions: the Thariq `config.json` first-run pattern is
**rejected** for plugins — it is not an official mechanism, and it writes into
`${CLAUDE_PLUGIN_ROOT}`, which is replaced on every update (the plugins-reference caching note), so
its state does not survive. Setup writes only the consumer configuration the plugin owns; Claude
Code's native configuration surface collects `userConfig` and owns `pluginConfigs` — a setup skill
never edits that key directly.

## Upstream sync — every upstream-sourced plugin ships an update path

A plugin that vendors or distills an upstream source — a docs site, a third-party playbook, a tool's
own documentation — carries a drift-check/update path: either an inline maintainer `update` action on
its skill or a dedicated update skill. A self-authored pack has no upstream to drift from; its update
path states "no upstream" and names the regeneration trigger instead (e.g. a model-version change).

## Evals — warrant policy and consumer-verify recipe

Evals are model-graded behavior fixtures at `plugins/<plugin>/skills/<skill>/evals/evals.json`,
schema `plugins/skill-quality/reference/evals.schema.json`. They are **warranted, not mandatory** —
a skill ships them only when they earn their keep.

**Warrant rule.** A skill **warrants** evals when it carries a judgment-bearing behavioral contract
that could silently regress — how it triggers, how it routes an ambiguous request, when it refuses,
or the shape of what it emits. A skill is an explicit **skip** when it is pure-reference (answers
from a knowledge corpus with no decision contract — `playbooks:fable-5`, `tdd`, …) or lives in a **hook** plugin
(deterministic, silent-always-on, guarded by `.test.sh`, no model-invoked skill). A `setup`
skill *is* warrantable — it makes interview and write-config decisions (the
`codebase-health/setup` eval is the model). Gray-zone skills (thin mechanical wrappers, reference-ish
routers) are **author-confirm**: re-check the warrant against the live `SKILL.md` at authoring time
and record an explicit skip verdict if it dissolves — a satisfied "looks covered" is not a warrant.
This section is the policy; current coverage is verified on demand — a live glob of
`plugins/*/skills/*/evals/evals.json` against the tree, read against the warrant rule above — never a
checked-in snapshot that decays the moment a skill lands.

**Rich form.** Each case carries `id`, a kebab-case `name`, a `prompt`, an `expected_output`
description, optional `files` fixtures, and an `expectations` array of objectively-verifiable checks
(the field may equivalently be named `assertions` — skill-creator upstream uses that name). Aim to
cover trigger/routing, the happy path, at least one refusal/guardrail, and one anti-pattern the skill
must not do.

**Consumer-verify recipe — "verify this plugin in MY repo".** There is **no first-party command that
executes model-graded evals today** — automated eval *running* is a deferred surface (owned by
`melodic-software/medley#1418`); `skill-quality` only checks presence and schema, and it resolves
skills under `${user_config.skills_root}` → `${CLAUDE_PROJECT_DIR}/.claude/skills` only — it does
**not** discover an installed marketplace plugin's skills by plugin name. So the static checks below run
against the plugin's **source tree**, not against a bare `/plugin install`; the exercise step is the
part that runs against the plugin as you actually enabled it.

Steps 1-2 are **source-tree verification**: run them against a checkout of this marketplace with
`<root>` = `plugins/<plugin>/skills`. This is the source, not necessarily the version you have
*enabled* — installed plugins are copied to a version-keyed cache under `~/.claude/plugins/cache`
(cache isolation; see "Cache isolation" and "Local development loop" below and the official plugins
reference "plugin caching and file resolution"), so after a marketplace update the source `evals.json`
can differ from the enabled copy. Step 3 (exercise) is the definitive as-enabled check because it runs
against the plugin you actually invoked. Then:

1. **Presence** — confirm the file `<root>/<skill>/evals/evals.json` exists. The static gate is only a
   partial signal: `/skill-quality:skill-quality check <skill>` (`check` is an action argument to the
   `skill-quality` skill, run with `skills_root` pointed at `<root>` via `/skill-quality:setup`) flags a
   *missing* eval file only for action-router-shaped skills — its check fires on a `## Actions` heading —
   so a warranted non-router skill (e.g. `debug`) passes `check` without flagging the gap. Rely on the
   direct file check or the coverage snapshot, not a green `check`, to confirm presence.
2. **Schema** — `/skill-quality:skill-quality validate-evals <skill>` (same `skills_root`) validates
   `evals/evals.json` against the bundled schema (structure only — it does not run the cases, and it
   treats an absent file as "not a failure", so it is a schema gate, not a presence gate).
3. **Exercise (manual) — the real consumer check** — enable the plugin in your repo (`/plugin install
   <plugin>@<marketplace>`), then read the eval cases **from the copy you actually enabled**, not from
   `<root>`: the enabled version lives in the version-keyed cache under `~/.claude/plugins/cache`, and
   reading cases from a source checkout that has drifted from it would exercise the installed plugin
   against a different version's prompts/fixtures. To use the source evals *as* the enabled plugin
   instead, load that source directory with `--plugin-dir` (the local copy then takes session precedence
   — see "Local development loop" below). For each case paste its `prompt` into a fresh session and read
   the result against that case's `expected_output` / `expectations`; cases with a `files` list need
   those fixtures present relative to the skill directory. This is a human judgment pass, not an
   automated pass/fail, until the deferred runner lands — at which point it becomes a single command and
   this recipe is revised.

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
`sensitive: true` (masked input; macOS Keychain storage, or `~/.claude/.credentials.json` where no
supported keychain exists) and substitutes it as `${user_config.KEY}`
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
| miro | stdio (bundled) | `miro_api_token` (`sensitive`) | **SHIP (cutover+bundle)** | Owner-confirmed 2026-07-12: ships as a **dedicated** `miro` plugin whose whole capability *is* the Miro board server, so it is *useless without the server* (rule 2), not event-storming's optional dependency (event-storming stays degraded-but-functional and ships no server, consuming miro only when connected). The server's TypeScript **relocates** out of `mcp-servers/miro/node` into `plugins/miro` (single source of truth, no copy left behind), bundled to one `dist/index.min.js` invoked as `node ${CLAUDE_PLUGIN_ROOT}/dist/index.min.js` (sidesteps #58510); `MIRO_API_TOKEN` → `userConfig` `miro_api_token` (`sensitive`, Claude secure credential storage); `defaultEnabled: false` so it never auto-starts unasked. First instance of the SHIP convention |
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
- **Token scope.** `MIRO_API_TOKEN` → `userConfig` `miro_api_token`, `sensitive` (macOS Keychain, or
  `~/.claude/.credentials.json` where no supported keychain exists;
  never `settings.json`); the consumer supplies and scopes it. The server exits at startup if unset.
- **Opt-in.** `defaultEnabled: false` — installs disabled; the consumer enables it deliberately.

**Consuming a sibling plugin's MCP tools (first instance: `event-storming` → `miro`).** When plugin A's
skill drives plugin B's bundled MCP server, three rules hold:

- **Namespaced tool names.** A plugin-bundled server's tools are callable as
  `mcp__plugin_<plugin>_<server>__<tool>` — for `miro`, `mcp__plugin_miro_miro__miro_create_board`
  ([mcp reference](https://code.claude.com/docs/en/mcp)). A bare `miro_*` name, or a bare-server-key
  `mcp__miro__…`, does **not** resolve for a plugin-bundled server. Any *declarative* reference
  (a skill's `allowed-tools`, a permission rule, a subagent `tools` field, a hook matcher) MUST use the
  full prefixed form; a matcher against the bare server key never fires. In model-facing prose the
  runtime resolves the tool the model actually calls, so a skill may name tools by their bare
  conceptual `<tool>` **provided it states once** that those names denote the provider's tools under
  the `mcp__plugin_<plugin>_<server>__` prefix (`simulation` does this in its availability gate).
- **Availability gate probes the prefixed form.** The consumer detects the capability by checking a
  prefixed tool (`mcp__plugin_miro_miro__miro_list_boards`), not a bare name — otherwise the gate can
  never fire and the consumer silently stays in its degraded default forever.
- **Soft dependency, never bundle-or-fork.** The consumer does not bundle the provider's server nor
  hard-depend on it: it keeps its no-server default (here structured-markdown), documents that the
  enhanced path requires the separately-enabled provider plugin, and degrades gracefully when the
  provider's tools are absent. This is the cross-plugin form of the "swap the MCP server, not a
  pluggable abstraction; declare the dependency, don't fork" rule above.

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
2. **Scope one capability.** One cohesive plugin; no grab-bags. If the source is oversized, run
   "Decompose an oversized skill before packaging it" and retain its trigger-migration evidence.
3. **De-couple from the source repo.** Remove hardcoded paths/names; route project-specifics to the
   consumer's context.
4. **Bundle + isolate.** Move required assets inside the plugin; reference via `${CLAUDE_PLUGIN_ROOT}`.
5. **Expose extensibility.** Declare `userConfig` for consumer choices; document each option. Apply
   the userConfig full-potential criterion and the exec-form hook rule from
   [PLUGIN-PHILOSOPHY.md § Configuration ownership and scope](PLUGIN-PHILOSOPHY.md): no custom
   config channel where the native schema fits, and no `${user_config.*}` in shell-form hooks.
6. **Strip PII / secrets.** Hard gate — before the first commit.
7. **Check component stances.** Every component the plugin ships conforms to the component stance
   table in [PLUGIN-PHILOSOPHY.md](PLUGIN-PHILOSOPHY.md) — no `commands/`, no unjustified
   `settings.json` `agent`, wait-listed components absent; setup criteria applied per its setup
   section; runtime prerequisites degrade per its failure-behavior rules.
8. **Idempotent, modular, extensible.** Re-running is safe; pieces compose; variability is declared.
9. **Validate.** `claude plugin validate`; test with `--plugin-dir` in a clean repo that is NOT the
   source repo (proves repo-agnosticism).
10. **Version.** Set an explicit semver `version` in `plugin.json`. A later bump that changes behavior a
   consumer depends on records the change in the plugin's changelog — see "Version pinning and update
   delivery" above.
11. **Publish.** Add the entry to `.claude-plugin/marketplace.json` — the plugin `source` is the
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

**Swim-lane execution (orchestrated fan-out).** When an orchestrator drives several units to merge in
one effort, each unit is a **swim lane**: a dedicated worktree (created under the same
identity-scoped directory root as the primary checkout, so the repo's commit/push identity applies —
never a sibling path outside it), a feature branch named `<type>/<issue>-<slug>`, its own atomic PR
that closes exactly one issue, driven independently through CI to a clean merge, then post-merge
cleanup (delete the branch, remove the worktree). A **seams-first** unit whose contract binds
downstream lanes lands and merges **before** the dependent lanes open, so they build on the merged
contract rather than rediscovering it. Independent lanes run concurrently; lanes sharing a
contract-blocking dependency wait on its merge. The shared-file conflicts above are still resolved by
serializing the final merges, not authorship.

## Plugin-acceptance security review

A plugin runs code on the consumer's machine and can wire Claude to external systems. **Every plugin accepted
here — new, or a version bump that adds a trust surface — passes this review** in addition to the migration
gate above (whose step 6 gates PII/secrets). **Deny by default** any surface below that can't be justified.
Facts verified against the plugins/MCP reference 2026-07-09 and re-verified against the plugins,
plugins-reference, and hooks pages 2026-07-17; re-verify per the `CLAUDE.md` fresh-docs mandate.

1. **Code execution — hooks & scripts.** A hook command runs on the consumer's machine on matched events,
   with `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`, and any `${ENV_VAR}`
   interpolated in. An exec-form hook may also use `${user_config.*}` in its arguments. A shell-form hook
   rejects that substitution and must read `CLAUDE_PLUGIN_OPTION_*` from the hook process environment.
   Check: which binaries it spawns; whether it mutates files in place and is
   **advisory** (exits 0, never blocks) vs gating; no `eval` / `curl … | sh` / outbound network; untrusted
   input (file contents, tool args, PR/issue text) never flows unquoted into a shell; a kill switch
   (a per-hook `userConfig` boolean with a `default` of `true`) exists.
2. **MCP servers — `.mcp.json` / inline in `plugin.json`.** `miro` is the only plugin that ships a
   **local** `stdio`, bundled server (see its §2 trust accept above); `dometrain` is the only plugin
   that ships a **remote** server (see its review record below), which remains the higher-scrutiny
   case. A plugin's MCP server **starts automatically when the plugin is enabled**
   (subject to per-server approval), unless it ships `defaultEnabled: false`. Check: the server host/URL and who runs it (first-party vs a third party you're delegating trust
   to); transport (local `stdio` vs remote `http`/`sse`/`ws`); **what data leaves the machine** — a remote
   server receives whatever Claude sends and, if it returns external content, is a prompt-injection vector
   (official guidance: "Verify you trust each server before connecting it"); auth shape (header/Bearer/OAuth)
   with any token sourced from `userConfig` `sensitive` or an env var, **never hardcoded**; a stated reason the
   capability can't be a local `stdio` server. **Do not accept a third-party remote MCP server** without an
   explicit recorded trust decision naming the vendor, the data egress, and the token scope.
3. **Consumer config — `userConfig`.** Any credential/token option MUST set `"sensitive": true` — that masks
   input and stores the value in the macOS Keychain or, on platforms without a supported keychain,
   `~/.claude/.credentials.json` — **not** `settings.json`.
   Non-sensitive values land in user `settings.json` under `pluginConfigs[<id>].options` and are readable —
   never put a secret there. Claude Code reads this key from user settings, `--settings`, and managed settings,
   not project or local settings. Endpoints and toggles are fine as non-sensitive. Every option is documented.
4. **Cache isolation — no reach-outs.** References only files inside the plugin via `${CLAUDE_PLUGIN_ROOT}`;
   persists state in `${CLAUDE_PLUGIN_DATA}`. No `../` reach-outs, no constructed absolute paths, no reading
   **consumer repository** files outside `${CLAUDE_PROJECT_DIR}`.
   - **The operator's own `~/.claude/` is not consumer repository data.** Reading a documented user-global
     config file there is sanctioned rather than a reach-out: criterion 3 above already stores consumer
     credentials at `~/.claude/.credentials.json`, and seam 2 mandates an optional `~/.claude/<plugin>.md`
     user-global layer — a criterion that forbade the read would contradict both. Read only the documented
     path for the plugin's own declared config; anything broader is a reach-out again. What this criterion
     targets is a plugin wandering out of the repository it was pointed at, not the operator's own Claude
     Code home.
5. **Data egress — telemetry & network.** Any telemetry (e.g. `HOOK_TELEMETRY_SINK`) is opt-in (unset = exact
   no-op), never writes to the hook's stdout/`additionalContext` channel, and emits only the declared envelope —
   no payload beyond the documented schema. Name any other outbound network call and justify it.
6. **Provenance & third-party trust.** Verify authorship (does `plugin.json` `author` match who actually
   submitted the PR?), license, and that the source is what it claims. A plugin that promotes or wires a
   third-party SaaS is a trust delegation — record accept/deny with rationale. Note the platform already blocks
   plugin-shipped **agents** from declaring `hooks` / `mcpServers` / `permissionMode` "for security reasons" —
   don't design around that.
7. **Main-thread and PATH surfaces.** A plugin `settings.json` `agent` entry takes over the
   consumer's main thread — prohibited by default per the component stance table in
   [PLUGIN-PHILOSOPHY.md](PLUGIN-PHILOSOPHY.md); an exception requires the documented justification
   the stance demands, reviewed here. `bin/` executables join the Bash tool's `PATH` while the
   plugin is enabled: names must be collision-safe (plugin-prefixed), and each binary's provenance
   is reviewed like any hook script.

Record accept/deny + rationale for any plugin touching surfaces 2, 5, 6, or 7; a later version bump
that introduces a new surface re-triggers this review.

### Review record — `github` (ACCEPT, 2026-07-21)

Recorded here as the single SSOT (miro §2 precedent). Reviewed at `0.1.0`; a version bump adding a
new trust surface re-triggers this review.

- **Code execution (1).** No hooks, no scripts wired to any event. The plugin ships prompt
  artifacts only (skills + reference markdown) plus `github.test.sh`, a repo-CI contract test
  referenced by nothing in the manifest — inert in a consumer install.
- **MCP servers (2).** None.
- **Consumer config (3).** One `userConfig` boolean (`offer_browser_automation`, non-sensitive,
  documented, default `true`). No credential options: authentication stays entirely in the
  consumer's own `gh` CLI login — the plugin never prompts for, stores, or transports a token.
  Consumer-side routing/conventions files live at the documented `.claude/github/` project layers
  and `~/.claude/github/` user-global layer (sanctioned read per criterion 4's operator-home
  carve-out).
- **Cache isolation (4).** All intra-plugin references anchor at `${CLAUDE_PLUGIN_ROOT}` (skills)
  or resolve inside the plugin directory (reference cross-links). No `../` reach-outs beyond the
  plugin root, no constructed absolute paths.
- **Data egress (5).** Three channels, all consumer-initiated, no telemetry:
  - `api.github.com` via the consumer's **own** `gh` auth. Bare invocations are read-only by
    written contract (write-capability guard: no field/input flags, no non-GET method, no GraphQL
    `mutation`); writes exist only behind `--apply` → consumer-declared routing → per-step user
    confirm naming the exact command and its doc provenance.
  - Official GitHub docs (`docs.github.com` et al.) runtime fetches for grounding — the D4
    zero-vendored-knowledge posture; read-only, with a fetch-integrity rung and a
    refuse-recall-as-grounded branch.
  - **Browser automation over the consumer's authenticated GitHub session** — the heavy surface,
    accepted with layered gates: presence-gated (claude-in-chrome tool probe / playwright
    plugin-installed seam), **never auto-fires**, each action individually offered and confirmed
    with the resolved settings URL, intended action, and mechanics provenance; post-write
    read-back verification where an API read exists; guided-manual + deep-link fallback always
    available. `offer_browser_automation: false` suppresses the offer — recorded honestly as an
    **advisory, model-honored gate layered under the per-action confirm, not a runtime-enforced
    kill switch**; the hard gate is the per-action user confirm. Accept rationale: some org-admin
    surfaces are UI-only, the session and credentials remain the user's own, and every action is
    user-in-loop; denying the surface would only push users to unassisted manual clicking with no
    provenance trail.
- **Prompt injection via ingested GitHub content (explicit item).** Everything fetched from GitHub
  (repo names, descriptions, issue/PR bodies, webhook URLs, custom property values) is declared
  **untrusted data, never instructions** as a standing instruction in both ingesting skills
  (`audit`, `advise`); an injected instruction must not trigger a write, browser action, or
  routing change. Evidence: anti-pattern eval cases (audit id 5, advise id 9). Defense in depth:
  every write path is already user-in-loop, so a successful steer still lands on a human confirm.
- **Provenance & third-party trust (6).** First-party authored (`author` = Melodic Software),
  MIT. No third-party SaaS delegation: the only vendor wired is GitHub itself, reached through the
  consumer's pre-existing `gh` relationship.
- **Main-thread / PATH (7).** No `settings.json` `agent`, no `bin/`.

**Verdict: ACCEPT** — surfaces 1/2/7 absent; 3/4 conform; 5's browser-automation channel accepted
with the layered gates above; 6 first-party.

### Review record — `dometrain` (ACCEPT, 2026-07-22)

Reviewed at `0.1.0`; a version bump adding a new trust surface re-triggers this review.

- **Code execution (1).** None — no hooks; `sync/scripts/update.sh` is not wired to any event
  and is not model-reachable: `sync/SKILL.md` carries `disable-model-invocation: true`, so it
  runs only on a maintainer's explicit `/dometrain:sync` invocation.
- **MCP servers (2).** The remote server itself: third-party (Dometrain-hosted), `http`
  transport, Bearer auth via `userConfig.dometrain_api_key` (never hardcoded), `defaultEnabled:
  false`. **Data egress / prompt-injection:** search queries and lesson IDs are sent to
  `mcp.dometrain.com`; responses are curated lesson text, which IS a genuine
  indirect-prompt-injection surface — the risk is that returned text could steer Claude's use of
  *other* tools already in the session (Bash, Write, other MCP servers), not whether Dometrain's
  own tools are mutating (they are all read-only). Mitigated the same way this repo's `github`
  plugin already accepts this class of risk (§740–745): `grounding/SKILL.md` carries a standing
  instruction treating all `search_dometrain`/`search_code`/`get_lesson` results as untrusted
  reference data, never instructions, backed by an anti-pattern eval case — an advisory,
  model-honored defense, not a runtime-enforced one, stated honestly as such rather than implied
  to be stronger than it is. Explicit trust decision: **ACCEPT**, third-party, rationale =
  read-only course-content grounding, no destructive tool surface, user's own
  paid-subscription-scoped token, `defaultEnabled: false`, standing untrusted-data instruction.
- **Consumer config (3).** One sensitive required `userConfig` string
  (`dometrain_api_key`), documented.
- **Cache isolation (4).** All skill/script paths resolve via `${CLAUDE_PLUGIN_ROOT}`-relative
  or script-own-location-relative paths (matching `context7`'s pattern); the `update.sh` upstream
  fetch reaches `raw.githubusercontent.com`, a documented, justified outbound call (criterion 5),
  not a `../` reach-out.
- **Data egress (5).** Two channels: (a) the MCP server itself, covered under (2); (b)
  `sync/scripts/update.sh`'s fetch of Dometrain's public GitHub-raw skill content — read-only,
  and never model-reachable: `sync/SKILL.md`'s `disable-model-invocation: true` means only a
  human explicitly running `/dometrain:sync` fires it, never the model on its own initiative and
  never from the installed plugin cache absent that explicit human action. No data leaves beyond
  the anonymous GET itself. No telemetry.
- **Provenance & third-party trust (6).** First-party plugin manifest/config (Melodic Software
  authored), but it wires TWO third-party trust surfaces: Dometrain's MCP server (the primary
  trust delegation, covered under (2)) and Dometrain's own public skill content as a
  vendored/reviewed text dependency (covered under (4)/(5)) — every sync is human-reviewed
  before a baseline refresh, never auto-applied, so the trust surface is bounded by that review
  gate, not blind ingestion. Note: this plugin's `grounding`/`sync` skill split is a stronger
  enforcement of that boundary than this repo's existing `context7:lookup` precedent, which
  bundles an equivalent `update` action into a model-invocable skill — a pre-existing gap flagged
  during this review, not remediated here, tracked separately.
- **Main-thread / PATH (7).** None; no `settings.json` `agent`, no `bin/`.

**Verdict: ACCEPT** — surfaces 1/7 absent; 2 accepted with the stated third-party rationale; 3/4
conform; 5 bounded to two justified, non-telemetry channels; 6 dual third-party surfaces both
gated (credential scope + human-reviewed sync).

### Review record — `context-guard` (ACCEPT, 2026-07-24)

Reviewed at `0.1.0`; a version bump adding a new trust surface re-triggers this review.

- **Code execution (1).** No hooks. Two bash scripts, neither wired to any event:
  `statusline-tee.sh` runs only when the OPERATOR wires it into their own `settings.json`
  statusline (the setup skill prints the edit, never applies it), and `context-zone.sh` runs only
  on explicit invocation. Both reviewed: no `eval`, no `curl | sh`, no outbound network; the one
  untrusted input that reaches the filesystem (`session_id` from statusline stdin) is sanitized to
  `[A-Za-z0-9_-]` before filename use; `captured_at` is format-gated to strict ISO-8601 UTC before
  being passed to `date -d`; no snapshot value is passed to `eval`, `sh -c`, or any code
  executor. Every failure path is transparent (wrapped statusline output
  and exit code unchanged). No kill-switch `userConfig` needed — nothing runs unless the operator
  wires it, and unwiring is the same one-line edit.
- **MCP servers (2).** None.
- **Consumer config (3).** No `userConfig`. The one machine file the plugin owns
  (`~/.claude/context-guard/zones.json`) is written only by the setup skill's explicit `apply`.
- **Cache isolation (4).** Skills reference bundled files via `${CLAUDE_PLUGIN_ROOT}`; no `../`
  reach-outs. Writes go only to `~/.claude/context-guard/` — the operator-home carve-out —
  deliberately outside `${CLAUDE_PLUGIN_DATA}` because the directory is a documented cross-plugin
  artifact seam (per-session snapshots + zones SSOT) that sibling-plugin sessions read by path;
  `${CLAUDE_PLUGIN_DATA}` resolves per-plugin-identity and would hide the seam. Same accepted
  pattern as `rate-limit-guard`.
- **Data egress (5).** None. No network, no telemetry. Snapshot data (context-window token
  counts + session id) never leaves the machine. Residual local-integrity limitation, stated
  honestly: the contract dir's `chmod 700` is best-effort — a no-op on filesystems without POSIX
  modes (Windows ACL volumes under Git Bash), where another local user could read or forge
  snapshots. The reader contract therefore forbids consumers from attaching security decisions to
  zone words (routing hints only), and the resolver format-gates `captured_at` and requires the
  embedded session id to match, so forgery cannot ride a lenient parser.
- **Provenance & third-party trust (6).** First-party (Melodic Software authored), MIT, no
  third-party delegation.
- **Main-thread / PATH (7).** None; no `settings.json` `agent`, no `bin/`.

**Verdict: ACCEPT** — surfaces 2/5/6/7 absent; 1 bounded to operator-wired transparent scripts
with sanitized untrusted input; 3 empty; 4 conforms under the documented operator-home seam
carve-out.

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
- **Multiple plugins at once** — repeat the flag: `claude --plugin-dir ./plugins/<a> --plugin-dir ./plugins/<b>`.
  `--plugin-dir` also accepts a `.zip` archive (Claude Code v2.1.128+). See
  [Create plugins](https://code.claude.com/docs/en/plugins) "Test your plugins locally".
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
   scope; a sensitive value still routes to secure credential storage (smoke-tests A and C).
   Interactively, `/plugin configure` owns personal `userConfig`; an explicit setup skill owns any
   separate tracked project configuration declared by the plugin.
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

- **Kill switch / toggles** → the plugin's own `userConfig` toggles (`/plugin configure`
  interactively, `claude plugin install --config` headless) — user-scoped, replacing the in-repo
  `HOOK_<OLD>_ENABLED` env var. Per-repo control is the plugin's `enabledPlugins` entry; a genuinely
  project-scoped per-hook need is a plugin gap (below), not an env var.
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
(`userConfig`, or a tracked consumer-project config key) — but only when it carries
real behavior, not cosmetic prose a consumer's `CLAUDE.md` already establishes. Resist adding config
surface to a published plugin for a single consumer's low-value nicety.

**Cutover checklist:**

1. Register the marketplace in the consumer's `extraKnownMarketplaces` and enable the plugin in
   `enabledPlugins` (project `settings.json`, so clones inherit it on trust — the interactive trust prompt
   both registers and installs the enabled plugin). Headless/CI has no such prompt, and registering a
   marketplace does not install its plugins, so do both explicitly: `claude plugin marketplace add <repo>`
   then `claude plugin install <plugin>@<marketplace> --scope project --config KEY=VALUE …`, seeding every
   non-default `userConfig` toggle on that install command — `--config` applies only on a fresh install and
   is ignored once the plugin is already installed (smoke-test C), so a headless reconfiguration later
   means uninstall/reinstall. Otherwise the marketplace is known but the plugin is absent, and step 3's
   verify edit would run with no plugin hook.
2. Interactively, `/plugin configure` adjusts `userConfig` toggles at any time; keep the
   `HOOK_TELEMETRY_SINK` wiring and the sink script (the bridge), adapting the sink for any
   observability-contract divergence.
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

**Cross-surface caveat — a repo-built `stdio` MCP server declared on more than the Claude Code surface.**
The checklist above assumes a hook plugin, whose only consumer is Claude Code. A marketplace plugin is
Claude-Code-only, so **a marketplace-plugin cutover replaces the Claude Code surface only.** A repo-built
`stdio` MCP server, however, is often declared on additional surfaces — Cursor (`.cursor/mcp.json`), Codex
(`.codex/config.toml`), Claude Desktop (a `tools/desktop-mcp` installer) — none of which can consume a
Claude Code marketplace plugin. When such a server also has **no npx/registry publish** (the playbook's
`stdio` (repo-built), "No CLI" class), those other surfaces have no path to the plugin at all, so deleting
the in-repo build strands the server on every non-CC surface. Compounding this, the MCP-parity CI gates
enforce **exact equality** across `.mcp.json` / `.cursor/mcp.json` / `.codex/config.toml` — removing the
server from only the CC surface breaks parity. So **resolve cross-surface consumption before deleting the
in-repo server**, picking one:

- **Clean-delete** — confirm (with the owner) the other surfaces do not need the server, then remove its
  entry from **all** surfaces at once. Parity stays trivially satisfied and no new machinery is needed.
- **Parity exemption** — keep the in-repo server for Cursor/Codex/Desktop while only the CC surface adopts
  the plugin; this requires an exemption in the parity gates (an `.mcp.json`-only removal otherwise fails
  them) plus a follow-up track for a genuine cross-surface distribution.
- **Defer** — hold the cutover until the server has a cross-surface distribution path (e.g. repoint the
  other surfaces at the plugin's on-disk bundle, or a shared build), then re-scope.

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

### Vendored Node packages — the `file:` + `--install-links` convention

Shared **Node** source (not a shell lib) is vendored as a plain package tree and consumed through
npm's `file:` link, because a cache-isolated plugin cannot reference a package outside its own
directory:

- The vendored package is a self-contained runtime-source copy (its own test suite, build config,
  and `node_modules` omitted). A consumer `package.json` depends on it with `"@scope/name":
  "file:<relative-path>"`.
- The skill's `setup-deps.mjs` installs it into `${CLAUDE_PLUGIN_DATA}` with
  `npm install --omit=dev --install-links <package-dir>` — `--install-links` packs the `file:`
  package as a real install (copied source) rather than a symlink back into the plugin cache, so it
  survives cache isolation. Install is idempotent: a stored fingerprint hashes `package.json` **and
  the entire vendored tree** (the packages install from source, not by version, so a source change
  with no manifest bump must still reinstall).
- Runtime resolves bare specifiers (`@scope/name/subpath`) from `${CLAUDE_PLUGIN_DATA}/node_modules`
  via an ESM resolve-hook (`run.mjs` → `register-hook.mjs`/`resolve-hook.mjs`), never a hardcoded
  path into the plugin cache.

### Intra-plugin sharing — one committed copy, no sync script

When the second consumer is **another skill in the same plugin** (not another plugin), the
cross-plugin machinery collapses: put the vendored source once at the plugin root (`vendor/`), and
point every consuming skill's `file:` link and `setup-deps.mjs` fingerprint at that single copy
(`file:../../../vendor/*` from `skills/<skill>/extraction/`). No `sync-*.sh` propagation and no
byte-drift CI gate are needed — there is only one committed copy, so nothing can drift. The
invariant that **replaces** the byte-drift gate is delivery-by-version: editing the shared source
obligates a plugin `version` bump, since the version is the update cache key. (`knowledge`'s
`repo-analysis` + `video-digestion`, shared by its `youtube-digest` and `course-digest` skills, is the
reference instance.) Reach for the cross-plugin shape above only once a *second plugin* genuinely
needs the same source.

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

## Knowledge-corpus consuming repo + integration flow — decision record (2026-07-13)

The `knowledge` plugin's ingest artifacts (transcripts, keyframes, source media, syntheses) get a
single dedicated consuming home rather than living in any one product repo, so a session can analyze
the whole corpus and fit relevant findings into *any* target repo. Decided with the owner in an
interview session against medley EPIC #1273 / wave-2 map #1369 (issue #1393); recorded here because
the wave's codification requirement puts convention decisions in tracked docs, not issue comments.

- **Repo:** `melodic-software/knowledge-corpus`, private, org-owned. Organization ownership was
  chosen because source media is retained and storage/bandwidth usage belongs with the shared corpus,
  not a personal account. Created pure-IaC via the `melodic-software/github-iac` governed registry
  (no ad-hoc `gh`, no import/drift window); the repo comes into being at the Pulumi deploy.
- **Media retention + LFS:** retain source video, keyframes, and any input useful for re-scraping or a
  fresh analysis — the corpus is the durable substrate for re-runnable synthesis, not just derived
  text. LFS-backed: a `.gitattributes` tracking media globs (mp4/mov/webm/png/jpg/jpeg/gif/pdf/epub/
  mp3/wav) plus pushed LFS objects. Git LFS is **not** expressible on the pulumi-github v6.14.0
  `Repository` resource (verified against the provider schema) → it is content-side, landing via a
  follow-up content PR to the repo, not governed in IaC. GitHub's quotas, metering, and prices change;
  verify the current account allowance, budget, and overage behavior in the
  [official Git LFS billing documentation](https://docs.github.com/en/billing/concepts/product-billing/git-lfs)
  before changing retention or ownership policy.
- **Artifact landing:** no consuming-repo name is baked into the plugin (contract v2.1 seam 1 + the
  convention-resolution ladder), so it serves any consumer unchanged. Which pipeline lands where — and
  which honor `library_dir` vs write elsewhere — is fast-moving plugin-seam state; the `knowledge`
  plugin's own skill docs are the SSOT, not recapped here.
- **Integration flow — first-class capability:** the value step is analyze-here → fit-into-any-target.
  Shape decided = a knowledge-plugin **`apply`/`integrate` skill** (a repeatable, invocable capability
  seam-consistent with contract v2.1), NOT a documented manual workflow (which would rely on operator
  memory and codify nothing). Full spec — target-repo scan, relevance ranking, how integrations are
  proposed/applied — is decomposed to a dedicated `design(knowledge-integration)` issue under #1369
  per the one-session sizing rule, rather than half-built inline.
- **Scope boundary:** the songwriting-corpus (Pat Pattison EPUBs) destination is owned by #1402, not
  decided here. How existing artifacts consolidate into this repo is operational — see #1393.

## `skill-quality` retrofit scope — decision record (2026-07-13)

The `skill-quality` plugin shipped only the generic static contract checker (`check-skill.sh`, seventeen
model-free checks) plus the `evals.schema.json` validation asset. Its held-back scope is resolved here as
**terminal exclusions** — decided out of the plugin for good, each with a permanent home, **not** deferrals
with a revisit trigger. (Contrast the "Deferred surfaces" record above, where the medley surface is held
*pending* a trigger; these are held *out*.)

- **A/B eval runner** (`tools/evals/run-skill-comparison.sh`): a headless `claude -p` skill-body A/B
  comparison driver — spins throwaway worktrees, runs fixture trials per arm, scrubs transcripts. **Not a
  plugin component; stays medley-owned in `tools/evals/`.** It is a *dynamic authoring experiment* harness,
  a distinct concern from this plugin's *static QA gate* (one cohesive capability per plugin — see the
  design charter), with a single consumer and ~29 KB of worktree / hub-safety / platform path-scrub
  surface that would be marketplace upkeep for that one consumer. **No revisit trigger:** a genuine
  second-consumer demand is a fresh publish issue, not standing debt.
- **Contract libs** (`tools/skill-contract/`: portability, encapsulation, script-contract, dispatcher):
  enforce medley-**invented** regimes — the skill public-surface / encapsulation contract, BEHAVIOR.md
  symmetry, unit-anatomy, the cleanliness-regime script contract, and a medley-specific identifier
  deny-list. **Permanent home is medley** (a de-couple-from-source-repo gate they cannot pass — every scan
  scope, exemption, and identifier is this repo's). The narrow genuinely-generic seams (machine-path /
  escape-path scanning, an encapsulation deep-cite regex, a "new script ships `--help` + a sibling test"
  assertion, a deny-list scan *mechanism* whose data is per-consumer) are net-new versus the shipped
  checks but have **no second consumer**; extracting them now is speculative generality / a pre-Rule-of-
  Three abstraction (`melodic-software/standards` `conventions/engineering/simpler-code.md`). The plugin
  can grow a machine-path check the day a real consumer needs one — as its own issue.
- **Checker hardening** (block-scalar description unfolding, an unquoted-`Use when:` warning, a
  `CHECK_SKILL_BASE_REF` post-commit audit ref for the git-backed checks, and a line-1 frontmatter-fence
  requirement): the one worker-executable slice — **landed** with this record.

## Convention-seam ratification & the shared-identity limitation — decision record (2026-07-23)

Recorded from the #1187 audit (triggered when the operator did not recall ratifying the
`consumer-config-layering` → `config-cascade` seam). All 12 `docs/conventions/*` seams are
**PR-introduced** across the repo's whole history (established from git history), so none was silently
accreted. In-doc issue/PR citation is the intended ratification signal but is **inconsistent** across
the surfaces today — some seams cite their ratifying issue in the README/CHANGELOG (`config-cascade`'s
exception class → #649), others (`hook-precision`, `seam-phrasing`) carry no in-doc reference, so an
operator auditing from the durable convention surface alone cannot always find it. Converging every
seam on an in-doc citation is a follow-up, not asserted here as already-true.

**The limitation, stated precisely — two provenance layers, only one collapses.** Distinguish:

- **Git commit metadata** (author, committer, `Co-Authored-By` trailers) **does** carry a distinct
  identity — this very record's commit is authored by `Codex <codex@openai.com>`; other agents commit
  under their own identity (e.g. a `Co-Authored-By: Claude …` trailer). So at the commit layer, agent
  work is often *visible*. But it is **soft, not proof**: an agent can set its git author to anything,
  so absence of an agent identity does not prove a human authored it.
- **GitHub gh-account actions** — PR author, PR review, merge, and the account a commit is *attributed
  to* — **all collapse to `kyle-sexton`** (the account `gh` is scoped to), whether the human or an
  agent-as-Kyle acted. At *this* layer no in-repo signal distinguishes human ratification from agent
  accretion.

So the gap is specifically at the **GitHub-account / review-and-merge layer**, which is exactly where
"ratification" is recorded — and it is a **repo-wide property**, not a defect of any one seam.

**Decision — decline forgery-prone gates; they are theater.** A `CODEOWNERS` rule or a `human-ratified`
label requiring a `kyle-sexton` review does **not** distinguish anything at the account layer: an agent
satisfies the same gate under the same identity. Commit signing already runs (`required_signatures`)
but under the shared key, so it does not separate either, and commit-author metadata is spoofable as
above. Standing up such a gate would manufacture *false* assurance — worse than naming the limitation.
So none is added.

**The only real distinguisher (flagged, not imposed).** Cryptographic separation requires an identity
agents do **not** hold — a distinct human-only GitHub account and/or a signing key kept off the agent
runners, with branch protection requiring that identity's review on `docs/conventions/**`. That is an
infrastructure change with real operator cost. **Revisit trigger:** the operator wants provable human
ratification, or a second human contributor joins (at which point identity separation exists naturally).

**Interim posture.** Ratification stays **trust-based and visible**: a convention-seam change **should
cite** a ratifying issue/PR in-doc (the norm going forward — converging existing seams on it is the
follow-up above), and the operator's explicit engagement on that thread (as in the #163434 session) is
the ratification signal. The audit trail — issue, review comments, commit-author metadata where it
carries an agent identity, and this record — is the durable account, in place of an account-layer
assurance the shared GitHub identity cannot provide.
