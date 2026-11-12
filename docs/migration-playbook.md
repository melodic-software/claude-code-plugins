# Migration playbook

## Contents

- [Organization: one plugin per cohesive concern](#organization-one-plugin-per-cohesive-concern)
- [Naming](#naming)
- [Extensibility model: what works today](#extensibility-model-what-works-today)
- [Extensibility contract v2.1: the four seams](#extensibility-contract-v21-the-four-seams)
- [Convention-resolution ladder](#convention-resolution-ladder)
- [Setup action: required iff the criteria hold](#setup-action-required-iff-the-criteria-hold)
- [Upstream sync: every upstream-sourced plugin ships an update path](#upstream-sync-every-upstream-sourced-plugin-ships-an-update-path)
- [Evals: warrant policy and consumer-verify recipe](#evals-warrant-policy-and-consumer-verify-recipe)
- [Shared tools and scripts seam](#shared-tools-and-scripts-seam)
- [Version pinning and update delivery](#version-pinning-and-update-delivery)
- [Retiring a published plugin](#retiring-a-published-plugin)
- [Persistence, configuration & external integration](#persistence-configuration--external-integration)
- [MCP servers as a plugin component: carry decision](#mcp-servers-as-a-plugin-component-carry-decision)
- [Plugin-form caveats (works in-repo, breaks as a plugin)](#plugin-form-caveats-works-in-repo-breaks-as-a-plugin)
- [Per-plugin migration gate](#per-plugin-migration-gate)
- [Migration order, PRs & parallelization](#migration-order-prs--parallelization)
- [Plugin-acceptance security review](#plugin-acceptance-security-review)
- [Marketplace schema positions](#marketplace-schema-positions)
- [Local development loop](#local-development-loop)
- [Fresh-consumer onboarding](#fresh-consumer-onboarding)
- [Reintegration: a consumer adopts the published plugin](#reintegration-a-consumer-adopts-the-published-plugin)
- [What to wait on / avoid for now](#what-to-wait-on--avoid-for-now)
- [Decision records](#decision-records)

How skills, hooks, and agents become reusable plugins in this marketplace. One plugin is migrated at a
time: lift it out, make it work in plugin form and in any repo, build in configuration and extensibility,
vet it against best practices, then publish.

The durable design policy is [Plugin philosophy](plugin-philosophy.md). This playbook applies that
policy to migration, validation, cutover, and release; it does not redefine the policy.

All schema and behavior claims below were verified against the official docs on 2026-06-22 (the
"Reintegration" section's marketplace-settings claims, `extraKnownMarketplaces` / `enabledPlugins` in a
project's `settings.json`, on 2026-06-29, against the discover-plugins "Configure team marketplaces"
guide; the "Extensibility contract v2.1" sections and their smoke tests on 2026-07-12 against Claude
Code 2.1.207; the Organization section's skill-listing claims on 2026-07-15, and the decomposition/trigger-continuity procedure on 2026-07-16, against the skills doc).
Re-verify fresh before acting, per
[a date is never authority](contracts/upstream-drift/README.md#a-date-is-never-authority). Recheck a
section when a Claude Code release note changes the plugin schema, skill-listing, or
marketplace-settings behavior it states.

## Organization: one plugin per cohesive concern

The philosophy's "one cohesive capability" is also the packaging boundary: **one plugin per cohesive
concern or capability**, grouped in the catalog through `category` / `tags` rather than by splitting.
A cohesive plugin MAY hold several units: a first-party plugin bundles many skills of one concern, a
hooks plugin bundles many hooks of one concern. One-unit-per-plugin is not the norm; do not ship a
plugin per hook.

- **Skills group by capability.** Distinct capabilities are distinct plugins; a single capability's
  always-together facets bundle (e.g. a prototyping capability's `logic` and `ui` skills ship together).
- **A skill splits only on distinct discovery intent, never per subcommand.** Two skills are
  warranted when their trigger vocabularies differ, because a user reaching for each says different
  things; a capability's subcommands stay action arguments of one skill. The restraint has a
  context-cost basis: the listing of skill names and descriptions loads into every session, and each
  entry's combined description text is truncated there at a per-entry cap (the figure and its
  source record: `/playbooks:skill-authoring` `## Descriptions`). Every extra skill is an
  always-paid context line. The standing exception is the `setup` lane, always its own skill with
  `disable-model-invocation: true`. See the philosophy's "Setup is explicit and repeatable".
- **Hooks group by concern.** Per-hook selectivity comes from a `userConfig` toggle (read through
  the hook-process `CLAUDE_PLUGIN_OPTION_<KEY>` mirror), a `matcher`, or an `if` guard, all
  author-managed control inside the bundle.
- **Whole-product / vendor-brand bundles** driven by distribution are a separate, allowed shape.

### Decompose an oversized skill before packaging it

Migration is the point to correct a mega-skill boundary, not preserve it accidentally. Apply this
procedure before choosing plugin and skill directories:

1. **Inventory the source contract.** Record each responsibility, output, supporting asset,
   cross-skill reference, eval, and auto-invocation phrase from `description` plus `when_to_use`.
   Claude Code uses that listing text to decide whether to load a skill, so trigger phrases are
   behavior, not marketing copy
   ([skills](https://code.claude.com/docs/en/skills), fetched 2026-07-16; recheck when that page
   stops saying the listing text decides whether a skill loads).
2. **Classify the split points by discovery intent.** Facets of one capability stay in one plugin but
   may become focused sibling skills when users reach for them with different vocabulary. Capabilities
   with independent purpose, lifecycle, or trust surface become separate plugins. Subcommands and
   depth variants remain arguments; they are not split points.
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
   the checker deliberately skips them. The cross-skill migration table and focused routing evals
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
*within* one cohesive capability you would never split. It forbids lumping *distinct* capabilities into
a single plugin. Hooks differ: a per-hook `userConfig` toggle gives clean per-hook control inside a
bundle. The discriminating axis is **silent-always-on** components (hooks, kept atomic or toggled via
`userConfig`) versus **opt-in-per-invocation** components (skills, grouped by capability).

**Buckets are catalog metadata, never structure.** Category grouping lives in `marketplace.json`
`category` / `tags` and catalog docs only: the disk layout stays flat (`plugins/<name>`, no
`plugins/<bucket>/<name>` nesting), and a bucket never appears in a plugin name or namespace.
Namespaces name capability domains; categories are curation.

**Boundaries are defended by design arguments, never incumbency.** A plugin's shape is justified by
change-together, useful-alone, and distinct discovery intent, not by the fact that it already ships
that way ("current state is evidence, never justification", `melodic-software/standards`
`standards/engineering/engineering-philosophy.md`).

## Naming

Naming policy, from plugin and namespace names through skill families and built-in collisions, is
[plugin philosophy § Naming](plugin-philosophy.md#naming). Apply it when choosing a migrated
plugin's name and skill directories.

## Extensibility model: what works today

These are the proven, documented mechanisms for consumer customization that do not confuse the agent.
Prefer them in this order; the earlier ones are simplest and least surprising.

| Mechanism | What it does | Use for |
|---|---|---|
| Consumer `CLAUDE.md` / `.claude/rules` | The skill reads the consuming project's own context and rules | Project-specific conventions, naming, policies: the default extension surface |
| `${CLAUDE_PROJECT_DIR}` | Path to the consumer's project root, substituted in hook/MCP/monitor commands and exported to subprocesses | Referencing project-local scripts/config |
| `userConfig` → `${user_config.KEY}` | Values Claude Code prompts for at enable time (typed: string/number/boolean/directory/file, optional sensitive). Substitutes as `${user_config.KEY}`; hook processes receive every value as `CLAUDE_PLUGIN_OPTION_<KEY>`, and a Bash tool call made by a skill does not (see the [smoke-test record](extensibility-contract-smoke-tests.md)). Which fields substitute or reject it, where values are stored, and which settings files are read: [plugin-philosophy.md § Configuration ownership and scope](plugin-philosophy.md#configuration-ownership-and-scope) | Endpoints, toggles, tokens: personal or administrator-supplied config without editing the plugin |
| `${CLAUDE_PLUGIN_ROOT}` | Path to the plugin's own installed directory | Referencing bundled scripts/assets (mandatory under cache isolation) |
| `${CLAUDE_SKILL_DIR}` | Path to the current skill's subdirectory within the plugin (not the plugin root); substituted in skill and agent content per the [skills reference](https://code.claude.com/docs/en/skills#available-string-substitutions) | Pre-compute blocks and `allowed-tools` paths that must resolve to skill-local scripts without hardcoding the plugin root |
| `${CLAUDE_PLUGIN_DATA}` | Persistent per-plugin directory that survives updates (`~/.claude/plugins/data/<id>/`) | Installed deps, caches, generated state |
| `hooks/hooks.json` | Event handlers the plugin ships | Behavior consumers opt into by enabling the plugin |

Design a skill so its variable parts route through the table above. "If you need to customize X, set
`userConfig` Y / add it to your project rules", never "open an issue" or "fork the skill".

## Extensibility contract v2.1: the four seams

The table above is the raw mechanism inventory ordered simplest-first; this contract is the **adopted**
policy for how a plugin exposes consumer variability, organizing those mechanisms into four seams. Each
seam matches a *kind* of variability (typed scalar, rich prose/rules, project convention, machine
state), not a rung on a preference ladder: choose the seam that fits the need, and within that choice
the table's simplest-first ordering still applies. Where the table's ordering and a seam's fit point
differently, **fit governs**: a typed token belongs in `userConfig` (seam 1) even though the table
lists consumer `CLAUDE.md` first. Each seam is tagged by its
authority: **[SPEC]** (documented Claude Code behavior), **[PRECEDENT]** (an official first-party
plugin does it, not written up as a spec), or **[PRECEDENT-EXTENSION]** (a documented shape extended
one increment past the precedent). Behavioral gaps the docs leave open are resolved empirically in the
[smoke-test record](extensibility-contract-smoke-tests.md).

1. **Typed scalars → `userConfig` → `pluginConfigs`. [SPEC]** Declare `string` / `number` /
   `boolean` / `directory` / `file` options (a `string` may set `multiple` for an array, since there is no
   `string[]` type); mark a credential `sensitive` so it lands in Claude Code's secure credential
   storage, never `settings.json`.
   Storage and the settings files read are in
   [plugin-philosophy.md § Configuration ownership and scope](plugin-philosophy.md#configuration-ownership-and-scope).
   Use for endpoints, toggles, tokens, and personal path knobs. The `directory` /
   `file` type is a UI hint, not a validator: a `--config` value is stored verbatim with no existence
   check and no normalization to absolute (smoke-test A).
2. **Tracked rich config under `${CLAUDE_PROJECT_DIR}`. [first-party PRECEDENT; folder form is a
   PRECEDENT-EXTENSION]** When configuration outgrows typed scalars, whether prose guidance, rule
   lists, threat models, or structured rulesets, read a checked-in file instead of piling on
   `userConfig` knobs.
   The proven shape is a single tracked file `.claude/<plugin>.md` (Markdown, for model-facing
   guidance) or `.claude/<plugin>.yaml` (structured rules), each with a gitignored `*.local.*` personal
   override and an optional `~/.claude/<plugin>.md` user-global. The precedent is the official
   **security-guidance** plugin (<https://code.claude.com/docs/en/security-guidance>): it reads
   `.claude/claude-security-guidance.md` (project), `~/.claude/claude-security-guidance.md` (user), and
   `.claude/claude-security-guidance.local.md` (gitignored personal override), loading every location
   that exists and concatenating them. The **folder form** `.claude/<plugin>/**` (many files, one per
   concern) is the PRECEDENT-EXTENSION: the first-party precedent uses single files, so a plugin that
   needs a directory of config extends the shape by one increment, keeping the same personal override and
   resolution rules.
   - **Concern-named folder for multi-plugin-consumed config.** When a tracked-config concern is
     consumed by MORE THAN ONE plugin, name the folder by the concern, not a plugin
     (`.claude/<concern>/**`). Plugin-naming would couple the other consumers and the consumer
     repo's tracked files to one plugin's name, and plugin boundaries are the volatile axis across
     restructures. A further one-increment PRECEDENT-EXTENSION; each instance records its schema and
     resolution rules as a versioned contract under `docs/conventions/<concern>/` (template:
     `docs/contracts/hook-telemetry/`; first instance:
     [`docs/contracts/ecosystem-commands/`](contracts/ecosystem-commands/README.md)).
   - **Profiled folder for audience/deployment variants.** When ONE plugin's tracked config varies by
     *audience* or *deployment*, meaning a different framing, ranking lens, or branding per team /
     client / context, add a profile axis to the folder form. Files at `.claude/<plugin>/` are the **default
     profile**; each `.claude/<plugin>/<profile-name>/` subfolder is a **named profile** that overlays
     the default per key (the same additive semantics the layering contract below fixes: a named profile
     refines the root, absent keys fall through). A single-config consumer never nests: its files sit at
     the root, which *is* the default profile, so growing a profile later is additive (drop a sibling
     subfolder), never a reorg, and there is no reserved `default/`/`team/` name to collide with. Pick
     the active profile by the convention-resolution ladder: exactly one named profile subfolder present
     → use it; several → an `active_profile` `userConfig` scalar (seam 1) or a per-invocation
     `--profile <name>` argument selects; none → the root default. This is a one-increment PRECEDENT-EXTENSION of the folder
     form, for a plugin that could ever profile: ship the **folder** form, since the single-file form
     cannot grow a profile without a file→folder reorg. Distinct from the concern-named folder above: that
     splits config across *plugins* (concern axis); this splits it across *audiences* within one plugin
     (profile axis), and the two compose (`.claude/<concern>/<profile-name>/`). Reference adopter:
     [`ai-briefing`](adr/0094-split-ai-briefing-into-an-engine-plugin-and-named-profiles.md).
   - **Resolution + override semantics, personal override naming, and the recommended consumer `.gitignore`
     line** are owned by [`docs/contracts/config-cascade/`](contracts/config-cascade/README.md).
     The layering axis is cross-cutting, so it is contracted once there rather than restated per
     seam. A surface declares its own keys and schema here or in its own owner doc, and points there
     for how its layers merge.
3. **Consumer `CLAUDE.md` / `.claude/rules` steering. [SPEC]** A plugin's skill and agent components
   run in the model's context and already read the consuming project's own rules. That is the default
   surface for project conventions, naming, and policy, requiring no plugin-side wiring. (Hook scripts
   do not see `CLAUDE.md`; they read env vars and file-based config only.)
4. **`${CLAUDE_PLUGIN_DATA}` for machine state only. [SPEC]** The per-plugin directory that survives
   updates: caches, installed dependencies, generated state. Never a channel for consumer
   *configuration* (it is machine-local and untracked); configuration flows through seams 1–3.

## Convention-resolution ladder

The **adopted** rule for how a plugin settles a value at runtime, applied to every seam:

1. Config present → use it. For a surface expressed as a **convention doc** (config-cascade
   § Expression doctrine), "present" means the convention home resolves from the root file's
   pointer line and the topic's doc exists there; the doc's prose is read as untrusted input.
2. Absent → explore the repo and **infer the house style** from repo evidence (existing docs, the
   consumer's own conventions, ambient instruction files), then **persist the inference**,
   *gated*: the inference is proposed and the operator confirms before anything is written, so
   discovery happens once and never silently. For a dedicated-file surface (seam 2) persist into
   tracked project config; for a convention-doc surface persist the pointer line (and, on request,
   a stub doc at the home). For a personal scalar (seam 1), direct the user to Claude Code's native
   plugin configuration instead.
3. Cannot infer → ask the user, and offer to persist the answer.
4. Otherwise → a safe generic default.

No baked repo assumptions, ever. A plugin never hardcodes a consumer's layout; it reads a declared
value, infers-and-records (gated), or asks. It never guesses silently. Nothing hardcodes
`docs/conventions/`: the home is whatever the pointer line names.

### Retired conventions: the detection and cleanup mechanism

When a plugin retires a consumer-facing convention (a config file moves to a convention doc, a
gitignore line is superseded, a directory is renamed), the old artifact left in consumer repos is
detected and cleaned by one shared mechanism, never by bespoke prose per plugin: the plugin appends
a record to its `retirements.yaml` (shipped inside the plugin, never in consumer
repos). Records are never deleted and identity/detection fields stay frozen; the `status`
demotion field may flip `active` to `report-only` (and back). The shared deterministic helper
`lib/check-retirements.sh` (canonical at the repo root,
generated into each carrying plugin by `scripts/sync-shared-copies.sh`)
evaluates every record against the consumer repo. Detection is one fixed step in setup `check`;
cleanup is per-record and operator-gated in `apply`; judgment-bearing `migrate` content stays with
the model per the record's `successor` prose. No new setup verb. The owner doc
`docs/contracts/retired-conventions/README.md` carries the schema, the helper contract, and the
two fixed setup lines; this playbook only names the mechanism. Schema is repository-scope only:
machine-scope files under `~/.claude/` stay outside it (ADR 0018).

This ladder is the runtime application of the durable convention posture owned by
[plugin-philosophy.md § Two-lane convention posture](plugin-philosophy.md): a pre-prescribed
convention is a hardcoded dependency, so a plugin ships a default only in lane 1 (a good-practice
value that cannot conflict in any consuming repo) and otherwise takes lane 2, where its setup discovers
the consumer's convention and externalizes it as an extensibility point the ladder then resolves.

## Setup action: required iff the criteria hold

Whether a plugin needs a `setup` skill, and the uniform contract it follows (`setup` name,
`disable-model-invocation: true`, `check` + `apply` actions, non-interactive completion), is owned
by [plugin-philosophy.md § Setup is explicit and repeatable](plugin-philosophy.md). Migration work
applies it as-is. Playbook-specific additions: the Thariq `config.json` first-run pattern is
**rejected** for plugins: it is not an official mechanism, and it writes into
`${CLAUDE_PLUGIN_ROOT}`, which is replaced on every update (the plugins-reference caching note), so
its state does not survive. Setup writes only the consumer configuration the plugin owns; Claude
Code's native configuration surface collects `userConfig` and owns `pluginConfigs`, and a setup skill
never edits that key directly.

## Upstream sync: every upstream-sourced plugin ships an update path

A plugin that vendors or distills an upstream source, whether a docs site, a third-party playbook, or
a tool's own documentation, carries a drift-check/update path: either an inline maintainer `update` action on
its skill or a dedicated update skill. A self-authored pack has no upstream to drift from; its update
path states "no upstream" and names the regeneration trigger instead (e.g. a model-version change).

## Evals: warrant policy and consumer-verify recipe

Evals are model-graded behavior cases. A new case is a `claude plugin eval` suite case at
`plugins/<plugin>/evals/<case>/case.yaml` whose one-line `tags: [...]` list, in `case.yaml` or in
`prompt.md`'s frontmatter, holds the directory name of the skill it covers, checked with no model call by `/evals:validate`. Per-skill `plugins/<plugin>/skills/<skill>/evals/evals.json`
files (schema `plugins/skill-quality/reference/evals.schema.json`) are legacy: existing ones stay
until `plugins/evals/skills/plugin-eval/scripts/convert-evals-json.py` converts them, and no new one
is added. Evals are **warranted, not mandatory**: a skill ships them only when they earn their keep.

**Warrant rule.** A skill **warrants** evals when it carries a judgment-bearing behavioral contract
that could silently regress: how it triggers, how it routes an ambiguous request, when it refuses,
or the shape of what it emits. A skill is an explicit **skip** when it is pure-reference (answers
from a knowledge corpus with no decision contract, such as `playbooks:fable-5` or `tdd`). A **hook**
plugin is a skip only in the case its rationale actually describes: deterministic, silent-always-on,
guarded by `.test.sh`, **no skill carrying a judgment-bearing contract**. The condition is the
absence of that contract, not the invocation mode. Stating it by invocation mode does not work: a
`setup` skill sets `disable-model-invocation: true`, so "no model-invoked skill" is satisfied by a
plugin that ships one, admitting as a skip the very plugin the rest of this rule excludes. A `setup` skill makes interview and write-config decisions that can
silently regress, which is precisely the contract the skip exists to excuse the absence of. The
plugin's shape does not exempt it: a `setup` skill *is* warrantable (the `codebase-health/setup`
eval is the model). Gray-zone skills (thin mechanical wrappers, reference-ish
routers) are **author-confirm**: re-check the warrant against the live `SKILL.md` at authoring time
and record an explicit skip verdict if it dissolves, because a satisfied "looks covered" is not a warrant.
This section is the policy; current coverage is verified on demand. Read the `tags:` of
`plugins/*/evals/*/case.yaml` and of each case's `prompt.md` frontmatter (where
`convert-evals-json.py` writes them), and glob the legacy `plugins/*/skills/*/evals/evals.json` across the
tree, and read the result against the warrant rule above, never from a checked-in snapshot that
decays the moment a skill lands.

**The gate honors a recorded skip.** `scripts/check-changed-skills.sh` passes `--require-evals` for
every skill whose `SKILL.md` is new or modified, and `plugins/skill-quality/scripts/check-skill.sh`
then hard-FAILs unless a case in the skill's plugin `evals/` tags its directory name, the skill still ships a legacy
`evals/evals.json`, or the skill is listed in `scripts/evals-warrant-exemptions.txt`. A skip
becomes a reviewed, diffable line rather than an implicit absence; anything unlisted still fails
closed. The file is stale-guarded: a row whose
skill is gone, or that now ships `evals/evals.json`, fails the gate so the list can only shrink.
This is the Exit A decision from #3135: the warrant rule above and the CI gate now agree.

Whatever the format, aim to cover trigger/routing, the happy path, at least one refusal/guardrail,
and one anti-pattern the skill must not do.

**Legacy rich form.** Each case in an existing `evals.json` carries `id`, a kebab-case `name`, a
`prompt`, an `expected_output` description, optional `files` fixtures, and an `expectations` array
of objectively-verifiable checks (the field may equivalently be named `assertions`, the name
skill-creator upstream uses).

When an existing file gains a case, give it a slug `id`, the same kebab-case text as its `name`,
never the next integer: two pull requests that each take the next number collide on merge. The schema accepts integer and
string ids and the quality lint requires only that they are unique, so existing integer ids stay.

**Method source.** The methodology behind this policy is Anthropic's "Define success criteria and
build evaluations" ([indexed in official-docs.md](official-docs.md#evaluation-guidance-platform-docs);
the `evals` plugin distills it). The rich form is that guidance's eval anatomy with the golden
answer in its rubric-instructions form (`expected_output` + `expectations` are what a grader is
told to look for), and every case must carry one. The schema rejects a case with no
`expected_output`, `expectations`, or `assertions`, because a case that cannot be graded is not an
eval. Two deliberate divergences from the guidance hold for this corpus, and the adoption record
below says why a shipped runner does not close them: nothing grades an `evals/evals.json` case in
this repository, so case volume stays low (the guidance's volume-over-polish principle assumes
cheap automated grading) and grading is a human judgment pass (the method the guidance ranks last).
New cases use the `claude plugin eval` suite format instead, which the command runs and grades.

**Adoption record: `claude plugin eval`, and which eval format is which.** Two Anthropic-owned eval
formats exist and they are not the same. The one this per-skill corpus uses is **`skill-creator`'s**:
`evals/evals.json` inside the skill directory, cases carrying `id` / `prompt` / `expected_output` /
`files` / `expectations`, which is why the schema's own `description` notes that upstream names that
last field `assertions`. It is the ecosystem-wide shape: a public code search returns thousands of
`evals.json` files in that form against a handful in any other. **`claude plugin eval` consumes a
different layout**: a plugin's `evals/` tree of `<case>/prompt.md` plus `graders/*.md`, or
`<case>/case.yaml`, with `experimental.evals` naming a directory elsewhere.

**What shipped.** The command shipped in Claude Code 2.1.269 on 2026-09-11 and this marketplace
has adopted it.
Before this adoption the binary answered `plugin eval is currently in early access` and refused to
run, which is why taking on the format would then have traded a corpus CI checks on every PR for one
nobody here could execute. That reason is spent, so the deferral is reopened.
`melodic-software/medley#1418` is the tracker that carried it and stays open on its own terms: this
record supersedes the deferral, it does not close the ticket. The adopted surface is the `evals`
plugin, whose `/evals:plugin-eval` guides a run of the command and whose `/evals:validate` checks
case files with no model call, over the pilot suite at `plugins/evals/evals/`.

**The suite format is the default for new cases.** The per-skill `evals/evals.json` corpus is
legacy: `scripts/check-changed-skills.sh` still accepts it in place of a tagging suite case,
`/skill-quality:check validate-evals` schema-checks it on every PR, and `convert-evals-json.py`
converts it into plugin suite cases. A suite runs on demand rather than in CI, because every run
and every judge grader is a metered model call, and its only static gate here is `/evals:validate`.
**For a legacy `evals.json` case:** nothing in *this* CI executes
that prompt, since the gates only lint and schema-check it, so a case must be
readable and followable by a human or an agent working by hand, and must not depend on a runner
having been invoked. That is not the same as no runner existing: a consumer with Anthropic's
`skill-creator` installed can run these suites, which is the format's own runner and which stages a
case's `files[]` for it. So use `files[]` to declare fixtures and reference them by their documented
path; do not hand-roll staging inside the `prompt` string. A prompt that builds its own workspace is
neither followable by hand nor compatible with the runner that would otherwise stage it.

**Consumer-verify recipe: "verify this plugin in MY repo".** Steps 1-2 are static:
`skill-quality` only checks presence and schema, and it resolves
skills under `${user_config.skills_root}` → `${CLAUDE_PROJECT_DIR}/.claude/skills` only. It does
**not** discover an installed marketplace plugin's skills by plugin name. So the static checks below run
against the plugin's **source tree**, not against a bare `/plugin install`; the exercise step is the
part that runs against the plugin as you actually enabled it.

Steps 1-2 are **source-tree verification**: run them against a checkout of this marketplace with
`<root>` = `plugins/<plugin>/skills`. This is the source, not necessarily the version you have
*enabled*: installed plugins are copied to a version-keyed cache under `~/.claude/plugins/cache`
(cache isolation; see "Cache isolation" and "Local development loop" below and the official plugins
reference "plugin caching and file resolution"), so after a marketplace update the source `evals.json`
can differ from the enabled copy. Step 3 (exercise) is the definitive as-enabled check because it runs
against the plugin you actually invoked. Then:

1. **Presence.** Confirm a case under `plugins/<plugin>/evals/` tags the skill, or, for a skill not
   yet converted, that `<root>/<skill>/evals/evals.json` exists. The static gate is only a
   partial signal: `/skill-quality:check <skill>` (`check` is both the skill's leaf name and its
   default action, run with `skills_root` pointed at `<root>` via `/skill-quality:setup`) flags a
   *missing* eval file only for action-router-shaped skills, because its check fires on a `## Actions`
   heading, so a warranted non-router skill (e.g. `debug`) passes `check` without flagging the gap. Rely on the
   direct file check or the coverage snapshot, not a green `check`, to confirm presence.
2. **Schema + quality lint.** `/evals:validate plugins/<plugin>/evals` checks suite cases. For a
   legacy file, `/skill-quality:check validate-evals <skill>` (same `skills_root`)
   validates `evals/evals.json` against the bundled schema, then runs the deterministic
   eval-quality lint (`check-evals-quality.sh`: duplicate case ids/names, unresolvable `files`
   fixtures, empty or vague grading criteria, advisory set-coverage warnings). Still static: it
   does not run the cases, and it treats an absent file as "not a failure", so it is a
   schema-and-content gate, not a presence gate.
3. **Exercise, the real consumer check.** For a plugin that ships a `claude plugin eval` suite, this
   step is the validator plus the command: `/evals:validate <plugin>/evals` checks the case files
   with no model call, then `/evals:plugin-eval` prices the suite, runs it with the plugin and again
   with nothing loaded, and reports the delta. Point it at the directory you actually enabled and it
   is the definitive as-enabled check; `claude plugin eval init` writes a suite for a plugin that has
   none. For a plugin whose only cases are per-skill `evals/evals.json` files, the exercise is still
   a hand pass, because that format has no runner here: enable the plugin (`/plugin install
   <plugin>@<marketplace>`), then read the cases **from the copy you actually enabled**, not from
   `<root>`, since the enabled version lives in the version-keyed cache under
   `~/.claude/plugins/cache` and a drifted source checkout would exercise different prompts and
   fixtures. To use the source evals *as* the enabled plugin instead, load that source directory with
   `--plugin-dir` (the local copy then takes session precedence; see "Local development loop" below).
   Paste each case's `prompt` into a fresh session and read the result against its `expected_output`
   / `expectations`; cases with a `files` list need those fixtures present relative to the skill
   directory.

## Shared tools and scripts seam

Separate **plugin-owned** logic from **consumer-owned** extension points:

- Plugin-owned scripts ship inside the plugin and run via `${CLAUDE_PLUGIN_ROOT}/scripts/`,
  bundled and cache-isolated, never reaching outside the plugin directory.
- Consumer-owned extension points are **declared paths**, not assumed layout: expose them through a
  `userConfig` `directory` option or a tracked-config key with a conventional default (e.g. `tools/`).
  A plugin reaches the consumer's own scripts only through a path the consumer declared or the
  convention the plugin documents, never a hardcoded repo structure.

## Version pinning and update delivery

- **A new `version` in `plugin.json` is the only delivery vehicle for copied installs.** A consumer
  who installed from a Git-hosted marketplace receives a change only after the plugin's semver
  `version` increases. The version is the update cache key, so an unreleased change never delivers,
  even when its files changed (see
  [ADR 0019](adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)).
- **A pull request records the release in a changelog fragment, not in the version.** For a plugin
  listed in `scripts/fragment-plugins.txt`, a pull request adds
  `.changes/<plugin>/<branch-slug>-<8 hex>.md` with `scripts/new-changelog-fragment.sh <plugin>
  <bump>` and leaves `plugin.json` and `CHANGELOG.md` alone; the release pull request turns pending
  fragments into one version bump and one `CHANGELOG.md` entry per plugin
  ([ADR 0048](adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)).
  One edit that reaches several plugins, such as a shared library under `lib/`, takes one command:
  `scripts/new-changelog-fragment.sh --stdin --carriers-of lib/<file> patch` writes the same body
  into a fragment for every carrier in fragment mode. A plugin not yet on the list still bumps its
  `version` and adds its `CHANGELOG.md` entry in the pull request.
- **Consumers update deliberately** with `/plugin marketplace update <marketplace>`, which refetches
  the marketplace. Auto-update is off by default for a third-party marketplace such as this one, so
  a consumer gets no change they did not ask for unless they turned `autoUpdate` on
  ([Which marketplaces and plugins auto-update](https://code.claude.com/docs/en/plugins/loading#which-marketplaces-and-plugins-auto-update),
  as of 2026-10-30; recheck when that list changes the default for other marketplaces or the
  `autoUpdate` key).
- **Breaking-change / changelog note per plugin.** A change to behavior a consumer depends on, such
  as a renamed option, a moved config path, or a removed action, is described in the fragment (or,
  for a plugin not yet in fragment mode, the `CHANGELOG.md` entry), and the release writes it into
  the plugin's own `CHANGELOG.md`, so a consumer updating deliberately sees what shifted. A change
  that adds a new trust surface additionally re-triggers the plugin-acceptance security review below.

**The marketplace carries no `renames` map.** A plugin rename is a clean breaking change carried
by a version bump and a changelog note. An install that still names an old id gets
`Plugin "<name>" not found in marketplace`, and the consumer re-enables the plugin under its new
name. Plugin splits and file moves are not renames.

A rename or retirement migrates every consumer in this repository in the same change, with no
deprecation shim, alias, or pointer to the old name: no stub catalog entry, no redirecting skill,
no second spelling a consumer can keep using. Consumers outside this repository (the fleet list,
dotfiles, user-scope `enabledPlugins`) migrate from their own repositories.

### Same-version commit drift (copied installs)

How a later commit under an unchanged `version` reaches an installed plugin depends on whether
Claude Code loads the plugin in place or from a copy
([Plugin loading reference](https://code.claude.com/docs/en/plugins/loading#in-place-and-copied-plugins),
fetched 2026-10-04; recheck when that section changes which sources load in place):

- **A marketplace added from a local path** (`claude plugin marketplace add <clone>`, or a
  `directory` source in checked-in settings): every plugin here has a relative-path source
  (`./plugins/<name>`), and such a plugin loads in place from the clone. Edits take effect at the
  next session start or `/reload-plugins` with no version change. Claude Code still writes a
  `cache/<marketplace>/<plugin>/<version>/` entry and a `gitCommitSha` in `installed_plugins.json`,
  but `claude plugin list --json` reports the clone as `readFromFolder` (measured on Claude Code
  2.1.289 with a throwaway local marketplace). No drift.
- **A Git-hosted marketplace** (`melodic-software/claude-code-plugins` from GitHub, the normal
  consumer install): Claude Code copies the plugin into `cache/<marketplace>/<plugin>/<version>/`
  and loads the copy. The manifest `version` comes first when it computes the version, so a later
  commit under the same version does not replace the copy, and
  `claude plugin update <name>@<marketplace>` reports "already at the latest version" and copies
  nothing ([How Claude Code computes the version](https://code.claude.com/docs/en/plugins/loading#how-claude-code-computes-the-version)).
  A fragment merged to main is such a commit: it changes the plugin's files and not its version
  until the release pull request merges.

For a copied install:

- **Ship a release** when the merged result must reach consumers: a fragment, then the release pull
  request (or a version bump, for a plugin not yet in fragment mode). It is the only delivery
  vehicle (see bullets above).
- **Force a fresh copy:** `claude plugin uninstall <name>@<marketplace> --keep-data` then
  `install` again, then `enable`. `uninstall` drops enabled state, so skipping `enable` leaves
  the plugin silently absent rather than silently stale. `--keep-data` keeps
  `${CLAUDE_PLUGIN_DATA}` only; uninstall still drops the stored `pluginConfigs`
  entry, so options return to manifest defaults on reinstall. Omitting the flag
  would also destroy the data directory.
- **Local iteration:** `claude --plugin-dir ./plugins/<name>` loads the working tree and takes
  session precedence over the installed copy (see "Local development loop" below), so no reinstall
  is needed for same-session edits after `/reload-plugins`.

## Retiring a published plugin

Creation and update delivery are above; this is the third move. Retirement is **one PR that removes
both halves at once**: the plugin's `.claude-plugin/marketplace.json` catalog entry and its whole
`plugins/<name>/` directory. The symmetry is not a convention to remember:
`scripts/check-plugin-manifest-presence.sh` runs FORWARD (a catalog entry whose directory has no
readable `plugin.json`) and INVERSE (a `plugins/*/` directory no catalog entry names), so removing
either half alone fails the gate. Regenerate the derived surfaces in the same PR
(`node scripts/generate-catalog.mjs`, `node scripts/generate-cheatsheet.mjs`) and sweep the repo for
references to the dead plugin id.

The plugin's `CHANGELOG.md` goes with its directory. `check-changelog-parity.sh --check-preserved`
deliberately exempts a changelog whose directory is also gone, reading it as a removal rather than
an absorbed section, so **the retirement is recorded in the PR body**, not in a changelog nobody
can read afterward. A final version bump is pointless: there is no artifact left to deliver.

Consumer guidance to state in that PR body:

- Installed copies keep working. The install is a version-keyed local snapshot, the same property
  "Same-version commit drift" documents above, so a consumer who already installed the plugin
  keeps it until they uninstall; retirement removes future installs and updates, not the copy on
  disk.
- Consumers should drop the plugin's `enabledPlugins` entry, which now names a plugin the
  marketplace no longer publishes.
- No tombstone and no `renames` entry (see "Version pinning and update delivery" above). If the
  capability moved into another plugin, say which one in the PR body and in the surviving plugin's
  changelog.

## Persistence, configuration & external integration

A skill is a markdown prompt (plus optional scripts), not a compiled runtime, so ports / adapters /
CQS layering is a **category error** here. Expose variability the way real plugins and the extensibility
model above already prescribe:

- **Persistence.** Write generated state and caches to `${CLAUDE_PLUGIN_DATA}` (the per-plugin directory
  that survives updates, per the extensibility table). Choose JSON / JSONL / SQLite per need.
- **Configurable location or behavior.** One `userConfig` knob (`${user_config.KEY}`, per the
  extensibility table) with a sane default, never a consumer-bound interface. Add a knob **only** where
  a real repo-specific behavior surfaces (Rule of Three; no speculative knobs, per the design charter).
- **External systems (issue trackers and the like).** Use backend-neutral **"work item"** vocabulary
  plus either a direct CLI call (e.g. `gh`) or dependence on an **MCP server**. Swapping the backend
  means swapping the MCP server, not introducing a pluggable-tracker abstraction (every official
  integration is a bare MCP wrapper).
- **Cross-skill references.** Hand off through the slash invocation when the target skill is present;
  degrade gracefully to prose when it is absent.

This is deliberately **not** ports / adapters: there is no runtime interface to invert in a prompt medium, so
a declared config file, not an abstraction layer, is the extension point.

## MCP servers as a plugin component: carry decision

A plugin can ship MCP servers via `.mcp.json` at the plugin root (or an `mcpServers` key in
`plugin.json`), across all transports: stdio, HTTP, SSE, WS
([MCP servers](https://code.claude.com/docs/en/plugins/components#mcp-servers)). Those servers
**auto-connect when the plugin is enabled** (managed through plugin install, not a second `/mcp`
approval) and appear as standard tools. The connect cost differs by transport: a **stdio** server
costs a **local process spawn on every session that enables the plugin**, used or not; an **HTTP/SSE/WS**
server spawns no local process but still auto-connects (its trust prompt + tool-schema context cost).
Tool-search deferral hides the tool *schema* from context until first use but does **not** defer the
stdio spawn or the connect. That auto-start cost is why the default is **not** to ship MCP: exactly
one marketplace plugin ships one (`miro`, the dedicated Miro board capability, per
[ADR 0092](adr/0092-carry-only-the-miro-mcp-server-in-a-plugin.md)), and the
discriminator below keeps it rare, reserved for a plugin genuinely useless without its server. A
credentialed SHIP additionally ships `defaultEnabled: false`, so its server does not auto-start for
consumers who never opt in.

**Uniform discriminator, applied to every server with no exemptions:**

1. **CLI covers the skill's need → CLI-first.** The plugin **depends on** the CLI (with documented
   install/setup, since the binary is on PATH, not bundled: e.g. `npm install -g ctx7`,
   `npm install -g firecrawl-cli`, `playwright-cli`) and drops the MCP dependency; a CLI-first
   migration MUST carry that install guidance or the plugin breaks on a machine without the CLI.
   Token-economics precedent (results pipe to disk instead of flooding context): context7 (`ctx7`),
   playwright (`playwright-cli`, Microsoft-recommended, ~4× fewer tokens), firecrawl
   (`firecrawl-cli`), ccusage (`ccusage daily|monthly|session|blocks --json`, the same token/cost
   breakdown as the MCP, [ccusage json-output](https://ccusage.com/guide/json-output)).
2. **No CLI + plugin is *useless* without the server → SHIP.** Bundle it and map each secret to
   `userConfig` `sensitive` (below). "Useless" is a high bar met by a **dedicated** server-wrapper
   plugin (its entire capability *is* the server); a plugin that runs in a reduced mode without the
   server is *degraded-but-functional* (rule 3), not a SHIP. A stdio SHIP owns its spawn: an `npx`
   command needs a `cmd /c` wrapper on Windows (#58510 below), so prefer invoking a bundled
   `node <server>`, which sidesteps #58510 entirely. Two bundling mechanisms, ratified by the `miro`
   SHIP (the first instance):
   - **Single self-contained bundle (preferred).** An [esbuild](https://esbuild.github.io/) bundle
     of the TypeScript source and every runtime dependency into one `dist/index.min.js`, with no shipped
     `node_modules`, so no `NODE_PATH`. The source is the source of truth; the `.min.js` is committed
     generated output (plugin install runs no build step), and a CI lane rebuilds it from source with
     the pinned toolchain, fails on drift, and runs the artifact over stdio so a bundle that compiles
     but cannot serve MCP is caught in CI. `.min.` keeps the generated bundle out of the
     text-quality lanes (typos, editorconfig).
   - **Committed `node_modules` under `${CLAUDE_PLUGIN_DATA}` (fallback).** For a server that cannot
     be single-file bundled, ship its `node_modules` and set
     `env.NODE_PATH: "${CLAUDE_PLUGIN_DATA}/node_modules"` (the persist-deps example in
     [Install dependencies into the data directory](https://code.claude.com/docs/en/plugins/components#install-dependencies-into-the-data-directory)) or it fails at startup
     with `MODULE_NOT_FOUND`.

   A SHIP that connects to a **credentialed external service** ships `defaultEnabled: false`. It
   installs disabled and the consumer opts in, so enabling the marketplace does not auto-start a
   credentialed server for users who never asked for it.
3. **No CLI + plugin is *degraded-but-functional* without it → STAY repo-level.** The skill NAMES the
   dependency and the consumer provides the server in their own `.mcp.json`; the skill degrades
   gracefully or loads the tool via `ToolSearch` when present. This is the extensibility model's
   "swap the MCP server, not a pluggable abstraction": declare the dependency, don't fork.
4. **Medley-/infra-bound server (no general-purpose plugin, or repo-coupled identity) → STAY
   repo-level.** Not a plugin concern.

**Secrets go through `userConfig` `sensitive`.** A SHIP declares each secret as a `userConfig` entry with
`sensitive: true` (masked input, stored as
[Configuration ownership and scope](plugin-philosophy.md#configuration-ownership-and-scope) states)
and substitutes it as `${user_config.KEY}`.
But **where** it goes depends on transport: a **stdio** server takes it in `.mcp.json` `env`, while
a **remote HTTP/SSE/WS** server takes it in `headers` / `headersHelper` (`env` only reaches a spawned
stdio process, so an HTTP key placed in `env` never authenticates). medley's own config shows the
split: `context7`/`ref` are HTTP and pass their key via `headers` (`x-api-key` / `x-ref-api-key`),
whereas a stdio server like `perplexity` uses `env`. Keychain storage is shared with OAuth tokens
(~2 KB total), so keep values small.

**The medley launcher stack: only its Node-pinning layer is medley-local.** medley's
`fnm exec + tools/mcp-launcher/launcher.js` stack solves two problems that generalize differently:

- **GUI-host Node PATH via `.nvmrc` pinning, medley-local.** A plugin does not need it; bundle
  assets via `${CLAUDE_PLUGIN_ROOT}` (+ `${CLAUDE_PLUGIN_DATA}` for a built server's `node_modules`).
- **Windows bare-`npx` `spawn ENOENT`, a general plugin problem, still open.** Plugin-shipped stdio
  MCPs that spawn `npx` fail on native Windows until wrapped with `cmd /c`
  ([anthropics/claude-code#58510](https://github.com/anthropics/claude-code/issues/58510), OPEN; the
  LSP spawn fix #17312 never reached the MCP spawn path). Do **not** assume the plugin runtime wraps
  `npx` for you: a SHIP that runs `npx` must ship its own `cmd /c` wrapper, while a SHIP that runs a
  bundled `node <server>` sidesteps the bug entirely.

So the `.nvmrc`/fnm layer stays medley-bound, but the Windows-`npx` concern travels with any
`npx`-spawning SHIP.

The verdicts for medley's 14 servers, audited 2026-07-12 against this discriminator, and the
miro SHIP reasoning are
[ADR 0092](adr/0092-carry-only-the-miro-mcp-server-in-a-plugin.md).

**Consuming a sibling plugin's MCP tools (first instance: `event-storming` → `miro`).** When plugin A's
skill drives plugin B's bundled MCP server, three rules hold:

- **Namespaced tool names.** A plugin-bundled server's tools are callable as
  `mcp__plugin_<plugin>_<server>__<tool>`, so for `miro` that is `mcp__plugin_miro_miro__miro_create_board`
  ([mcp reference](https://code.claude.com/docs/en/mcp)). A bare `miro_*` name, or a bare-server-key
  `mcp__miro__…`, does **not** resolve for a plugin-bundled server. Any *declarative* reference
  (a skill's `allowed-tools`, a permission rule, a subagent `tools` field, a hook matcher) MUST use the
  full prefixed form; a matcher against the bare server key never fires. In model-facing prose the
  runtime resolves the tool the model actually calls, so a skill may name tools by their bare
  conceptual `<tool>` **provided it states once** that those names denote the provider's tools under
  the `mcp__plugin_<plugin>_<server>__` prefix (`simulation` does this in its availability gate).
- **Availability gate probes the prefixed form.** The consumer detects the capability by checking a
  prefixed tool (`mcp__plugin_miro_miro__miro_list_boards`), not a bare name. Otherwise the gate can
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
- **Namespacing.** Components are namespaced by the plugin's own `name`, not the marketplace name, so
  an in-repo `/foo` becomes `/<plugin-name>:foo`. Internal cross-references to the bare name break, so
  update them.
- **Agent shadowing.** Project/user `.claude/agents/` override same-named plugin agents. A leftover
  in-repo copy masks the plugin version until removed from the source repo.
- **Headless registration.** Distinguish the marketplace **source** from the session shape:
  - **Remote or git-sourced catalogs** (GitHub repo, URL, npm, …) in CI or other non-interactive
    runs: no interactive trust dialog, so run `claude plugin marketplace add` explicitly or pre-seed via
    `CLAUDE_CODE_PLUGIN_SEED_DIR` ([Manage plugins for your organization, "Seed containers and CI"](https://code.claude.com/docs/en/plugins/org#seed-containers-and-ci),
    as of 2026-10-07; recheck when that section drops the seed variable).
  - **`directory` / `file` source with a relative path in checked-in project `.claude/settings.json`:**
    the path [resolves against the repository's main checkout](https://code.claude.com/docs/en/plugins/org#require-plugins-per-repository),
    so every git worktree shares it, with no separate `marketplace add` step. The marketplace
    registers only in a folder the collaborator trusted: after the trust dialog in an interactive
    session and, in a `-p` run, only in a folder already trusted. A cloud session
    [doesn't load the plugins the repository's settings turn on](https://code.claude.com/docs/en/plugins/install#install-a-plugin)
    (Cloud session tab).
    See [`docs/cloud-sessions.md`](cloud-sessions.md) "Plugins in sessions on this repo".

## Per-plugin migration gate

For each skill/hook/agent being migrated:

1. **Research fresh.** Read the official docs for every component involved, by the
   [fetch route](contracts/upstream-drift/README.md#reading-the-basis-the-fetch-route).
2. **Scope one capability.** One cohesive plugin; no grab-bags. If the source is oversized, run
   "Decompose an oversized skill before packaging it" and retain its trigger-migration evidence.
3. **De-couple from the source repo.** Remove hardcoded paths/names; route project-specifics to the
   consumer's context.
4. **Bundle + isolate.** Move required assets inside the plugin; reference via `${CLAUDE_PLUGIN_ROOT}`.
5. **Expose extensibility.** Declare `userConfig` for consumer choices; document each option. Apply
   the userConfig full-potential criterion and the exec-form hook rule from
   [plugin-philosophy.md § Configuration ownership and scope](plugin-philosophy.md): no custom
   config channel where the native schema fits, and no `${user_config.*}` in shell-form hooks.
6. **Strip PII / secrets.** Hard gate, before the first commit.
7. **Check component stances.** Every component the plugin ships conforms to the component stance
   table in [plugin-philosophy.md](plugin-philosophy.md): no `commands/`, no unjustified
   `settings.json` `agent`, wait-listed components absent; setup criteria applied per its setup
   section; runtime prerequisites degrade per its failure-behavior rules.
8. **Idempotent, modular, extensible.** Re-running is safe; pieces compose; variability is declared.
9. **Validate.** `claude plugin validate`; test with `--plugin-dir` in a clean repo that is NOT the
   source repo (proves repo-agnosticism).
10. **Version.** Set an explicit semver `version` in `plugin.json`. A later bump that changes behavior a
   consumer depends on records the change in the plugin's changelog. See "Version pinning and update
   delivery" above.
11. **Publish.** Set `keywords` and `metadata.category` (from [catalog-taxonomy.md](catalog-taxonomy.md))
    in `plugin.json`, add an entry with `name` and `source` to `.claude-plugin/marketplace.json`, and run
    `node scripts/generate-marketplace.mjs`, which writes the entry's `category` and `tags`. The plugin `source` is the
    `./`-prefixed relative path (e.g. `./plugins/<name>`). Bare names fail `claude plugin validate --strict`
    even with `metadata.pluginRoot` set, despite the marketplaces-doc example to the contrary (verified
    2026-06-23). Then run `claude plugin validate --strict <repo-root>` to validate the **catalog manifest
    itself**: a bad entry surfaces only there, not in per-plugin validation. The catalog page
    (`docs/catalog.md`) regenerates from the manifests, so run `node scripts/generate-catalog.mjs`.

## Migration order, PRs & parallelization

**Foundations first** (Fowler's Branch by Abstraction). Establish the shared foundations, meaning the
conventions in this playbook, the shared `lib/` source of truth
([ADR 0019](adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)), and
the persistence/config pattern above, in one small sequential PR *before* fanning out. Everything
downstream builds on those conventions.

**Per-unit atomic PRs, authored in parallel.** One PR per cohesive migratable unit: small changesets
review faster and more thoroughly, and the per-unit acceptance gate makes each one atomic and
rollback-safe. Parallelize with one worktree (or worker) per unit, **conflict-free by design**, because
each plugin is an isolated `plugins/<name>/` directory, so N units become N concurrent PRs with no merge
conflicts. Group units into one PR only when they are hard-coupled, or when the change is a single
mechanical bulk edit.

**Expect one shared-file conflict, resolved at merge.** The two files parallel PRs all touch are the
catalog manifest (`.claude-plugin/marketplace.json`) and the generated catalog page (`docs/catalog.md`). Those conflicts are
expected: resolve them by **serializing the final merges**, not by serializing authorship.

**Gate every unit before publish.** Each unit clears its parity / acceptance gate, the per-plugin
migration gate and the plugin-acceptance security review below, before it ships.

**Sequence heuristic.** Order lowest-coupling units first (clean, self-contained units with graceful
degradation). Defer risky units (hard external dependencies, no graceful degradation) and any
license-gated units to per-item triage rather than a blanket hold. The ordering is reversible.

**Swim-lane execution (orchestrated fan-out).** When an orchestrator drives several units to merge in
one effort, each unit is a **swim lane**: a dedicated worktree (created under the same
identity-scoped directory root as the primary checkout, so the repo's commit/push identity applies,
never a sibling path outside it), a feature branch named `<type>/<issue>-<slug>`, its own atomic PR
that closes exactly one issue, driven independently through CI to a clean merge, then post-merge
cleanup (delete the branch, remove the worktree). A **foundations-first** unit whose contract binds
downstream lanes lands and merges **before** the dependent lanes open, so they build on the merged
contract rather than rediscovering it. Independent lanes run concurrently; lanes sharing a
contract-blocking dependency wait on its merge. The shared-file conflicts above are still resolved by
serializing the final merges, not authorship.

## Plugin-acceptance security review

A plugin runs code on the consumer's machine and can wire Claude to external systems. **Every plugin accepted
here, whether new or a version bump that adds a trust surface, passes this review** in addition to the migration
gate above (whose step 6 gates PII/secrets). **Deny by default** any surface below that can't be justified.
Facts verified against the plugins/MCP reference 2026-07-09 and re-verified against the plugins,
plugins-reference, and hooks pages 2026-07-17; re-verify per
[a date is never authority](contracts/upstream-drift/README.md#a-date-is-never-authority).
Recheck when a Claude Code release note changes hook command substitution, `userConfig`
interpolation, or what a plugin may bundle.

1. **Code execution: hooks & scripts.** A hook command runs on the consumer's machine on matched events,
   with `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`, and any `${ENV_VAR}`
   interpolated in. Which hook forms take `${user_config.*}`, and why ours use none, is in
   [plugin-philosophy.md § Configuration ownership and scope](plugin-philosophy.md#configuration-ownership-and-scope).
   Check: which binaries it spawns; whether it mutates files in place and is
   **advisory** (exits 0, never blocks) vs gating; no `eval` / `curl … | sh` / outbound network; untrusted
   input (file contents, tool args, PR/issue text) never flows unquoted into a shell; a kill switch
   (a per-hook `userConfig` boolean with a `default` of `true`) exists.
   - **A skill's frontmatter `allowed-tools` is a prompt-free execution grant, and workspace trust does
     not gate it.** Measured on Claude Code 2.1.225: a marketplace-installed skill's `allowed-tools`
     entry takes effect at **user scope** in a **never-trusted** workspace, under `-p` where no trust
     dialog can appear: the covered command ran without a prompt, the uncovered one blocked with
     `This command requires approval`, and a no-grant baseline confirmed that shape blocks. Bounds on
     the measurement: a local-directory marketplace, and user scope only.
     **Consequence: the install-time plugin trust prompt is the only gate in front of such a grant.
     There is no second, per-workspace one.** Review every `allowed-tools` entry with the scrutiny a
     hook command gets, and deny by default anything broader than the specific command the skill's own
     scripts invoke. A wildcard interpreter grant (`Bash(python*)`, `Bash(*)`, bare `Bash`) is a deny
     outright: it is arbitrary code execution in a workspace the consumer never trusted.
     `harness-config:audit-permission-grants` check P1 detects exactly these shapes and is the
     mechanical half of this criterion.
2. **MCP servers: `.mcp.json` / inline in `plugin.json`.** `miro` is the only plugin that ships a
   **local** `stdio`, bundled server (its record in
   [ADR 0093](adr/0093-record-plugin-acceptance-security-reviews.md)); no plugin ships a **remote**
   server, which remains the higher-scrutiny case. A plugin's MCP server **starts automatically when the plugin is enabled**
   (subject to per-server approval), unless it ships `defaultEnabled: false`. Check: the server host/URL and who runs it (first-party vs a third party you're delegating trust
   to); transport (local `stdio` vs remote `http`/`sse`/`ws`); **what data leaves the machine**, since a remote
   server receives whatever Claude sends and, if it returns external content, is a prompt-injection vector
   (official guidance: "Verify you trust each server before connecting it"); auth shape (header/Bearer/OAuth)
   with any token sourced from `userConfig` `sensitive` or an env var, **never hardcoded**; a stated reason the
   capability can't be a local `stdio` server. **Do not accept a third-party remote MCP server** without an
   explicit recorded trust decision naming the vendor, the data egress, and the token scope.
3. **Consumer config: `userConfig`.** Any credential/token option MUST set `"sensitive": true`, which masks
   input and keeps the value out of `settings.json`. Non-sensitive values are readable, so never put a
   secret there; storage and read scope are in
   [plugin-philosophy.md § Configuration ownership and scope](plugin-philosophy.md#configuration-ownership-and-scope).
   Endpoints and toggles are fine as non-sensitive. Every option is documented.
4. **Cache isolation: no reach-outs.** References only files inside the plugin via `${CLAUDE_PLUGIN_ROOT}`;
   persists state in `${CLAUDE_PLUGIN_DATA}`. No `../` reach-outs, no constructed absolute paths, no reading
   **consumer repository** files outside `${CLAUDE_PROJECT_DIR}`.
   - **The operator's own `~/.claude/` is not consumer repository data.** Reading a documented user-global
     config file there is sanctioned rather than a reach-out: criterion 3 above already stores consumer
     credentials at `~/.claude/.credentials.json`, and seam 2 mandates an optional `~/.claude/<plugin>.md`
     user-global layer, so a criterion that forbade the read would contradict both. Read only the documented
     path for the plugin's own declared config; anything broader is a reach-out again. What this criterion
     targets is a plugin wandering out of the repository it was pointed at, not the operator's own Claude
     Code home.
5. **Data egress: telemetry & network.** Any telemetry (e.g. `HOOK_TELEMETRY_SINK`) is opt-in (unset = exact
   no-op), never writes to the hook's stdout/`additionalContext` channel, and emits only the declared envelope,
   with no payload beyond the documented schema. Name any other outbound network call and justify it.
6. **Provenance & third-party trust.** Verify authorship (does `plugin.json` `author` match who actually
   submitted the PR?), license, and that the source is what it claims. A plugin that promotes or wires a
   third-party SaaS is a trust delegation, so record accept/deny with rationale. Note the platform already blocks
   plugin-shipped **agents** from declaring `hooks` / `mcpServers` / `permissionMode` "for security reasons".
   Don't design around that.
   - **An `archive` marketplace entry MUST carry its `sha256` pin.** A catalog entry may set
     `"source": "archive"` with a `url` and a `sha256` pin the platform treats as optional, installing the
     plugin from a zip downloaded over HTTPS with no git or npm on the consumer's machine. The platform
     checks only the transport (an `https://` URL that is not a loopback, link-local or cloud-metadata
     host); content identity rests on the pin alone, so an unpinned entry lets the same URL serve
     different bytes on every install with nothing to detect it. That is a mutable-remote-artifact
     surface, which criterion 6 denies by default, so **this review requires the pin**: an `archive`
     entry without `sha256` is a deny, whether this repository publishes it or accepts a plugin that
     depends on it. Two follow-ons to record when accepting one: the digest doubles as the plugin's
     version when neither `plugin.json` nor the entry declares one, so a repinned archive with a fixed
     `version` still needs that `version` bumped before users leave the cached copy; and organization
     sync through claude.ai settings accepts only some source types, so check its list before relying
     on `archive` there. Pointers: [archive plugin source](https://code.claude.com/docs/en/plugins/marketplace-reference#archive-plugin-source)
     (version floor in the [plugin sources](https://code.claude.com/docs/en/plugins/marketplace-reference#plugin-sources)
     table), [How Claude Code computes the version](https://code.claude.com/docs/en/plugins/loading#how-claude-code-computes-the-version),
     and [Distribute through organization settings](https://code.claude.com/docs/en/plugins/host-marketplace#distribute-through-organization-settings).
     As of 2026-10-07. Recheck when the archive section makes `sha256` required or changes the URL
     rules, or when organization sync starts accepting `archive`. Enforced by `scripts/validate-plugin-contracts.mjs`
     over `.claude-plugin/marketplace.json`. This marketplace publishes every plugin as a relative path
     (`"source": "./plugins/<name>"`), so no entry uses `archive` today; the rule governs the first that
     does.
7. **Main-thread and PATH surfaces.** A plugin `settings.json` `agent` entry takes over the
   consumer's main thread, and is prohibited by default per the component stance table in
   [plugin-philosophy.md](plugin-philosophy.md); an exception requires the documented justification
   the stance demands, reviewed here. A top-level `bin/` is not accepted (the component stance table and
   `scripts/check-plugin-manifest-presence.sh` carry the reason); executables live under
   `scripts/`, and each one's provenance is reviewed like any hook script.

Record accept/deny + rationale for any plugin touching surfaces 2, 5, 6, or 7; a later version bump
that introduces a new surface re-triggers this review. Each record is a dated section amending
[ADR 0093](adr/0093-record-plugin-acceptance-security-reviews.md).

## Marketplace schema positions

Positions on upstream marketplace-schema features this catalog should not improvise (#3616).
Verdicts are adopt / defer / reject. Gotchas that are upstream behavior, not a choice, are
constraints to design around. Re-fetch the cited pages before acting; the as-of date is not
authority.

| Feature | Position | Rationale |
|---|---|---|
| `strict` per entry | adopt default (`true`; omit the field) | No entry in `.claude-plugin/marketplace.json` sets `strict`. Every plugin here ships `plugin.json`. Default `strict: true` keeps that file the component authority. `strict: false` with entry component fields is rejected: that is marketplace-entry-as-definition, which this catalog does not use. Source: [strict mode](https://code.claude.com/docs/en/plugins/marketplace-reference#strict-mode). |
| `renames` | reject | `.claude-plugin/marketplace.json` carries no `renames` map. A rename is a clean break: an old-name install gets `Plugin "<name>" not found in marketplace` and the consumer re-enables the new name. Source: [migrate users with a renames map](https://code.claude.com/docs/en/plugins/host-marketplace#migrate-users-with-a-renames-map). |
| `userConfig` | adopt | Sanctioned mechanism for tokens, paths, and toggles. Declare `sensitive: true` for credentials. Already in use. Source: [user configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration). |
| `channels` | defer | Component-stances Wait: no fleet gap. Re-verify before a plugin binds a message channel. Source: the Channels row of [Component stances](plugin-philosophy.md#component-stances). |
| Relative-path sources vs a URL marketplace add | design-around | Relative `./plugins/<name>` sources resolve only when Claude Code has the marketplace files (`github`, `git`, `file`, `directory`). A marketplace `url` fetch of `marketplace.json` alone cannot resolve them. This catalog stays a GitHub git marketplace; do not publish it as a JSON URL. Source: [relative path plugin source](https://code.claude.com/docs/en/plugins/marketplace-reference#relative-path-plugin-source) for the source types and [avoid relative-path entries in a URL-hosted marketplace](https://code.claude.com/docs/en/plugins/host-marketplace#avoid-relative-path-entries-in-a-url-hosted-marketplace), as of 2026-10-30; recheck when either section changes which marketplace sources resolve relative paths. |
| `command` plugin source | reject | None in this catalog. Claude Code shows the user the command and runs it only once they accept it, then runs it at every install and update and once per session; an administrator blocks the source with `disableCommandPluginSources`. Source: [command plugin source](https://code.claude.com/docs/en/plugins/marketplace-reference#command-plugin-source) and, for accepting the command, [install from your shell](https://code.claude.com/docs/en/plugins/install#install-from-your-shell), as of 2026-10-30; recheck when either section changes how the command is accepted or when it runs. |
| `headersHelper` | reject | Requires `strict: false` on the entry and takes effect only on an `archive` source. Background auto-update skips it. This catalog is relative-path, not archive. Sources, as of 2026-10-30: [add a headersHelper to a plugin entry](https://code.claude.com/docs/en/plugins/host-marketplace#add-a-headershelper-to-a-plugin-entry) for `strict: false`, [validation messages](https://code.claude.com/docs/en/plugins/marketplace-reference#validation-messages) for the `archive`-only effect, and [which marketplaces and plugins auto-update](https://code.claude.com/docs/en/plugins/loading#which-marketplaces-and-plugins-auto-update) for the skip. Recheck when one of those sections changes the fact cited from it. |
| Version computation | adopt as constraint | Rung order: `plugin.json` `version`, then the entry `version`, then source-type (git SHA, archive digest, or unknown). This catalog pins `version` in every `plugin.json` so updates are explicit. Do not omit it to track SHA. Source: [how Claude Code computes the version](https://code.claude.com/docs/en/plugins/loading#how-claude-code-computes-the-version). |
| `bin/` under org-managed distribution | adopt as constraint: no plugin ships a top-level `bin/` | Documented constraint ([host a marketplace](https://code.claude.com/docs/en/plugins/host-marketplace#distribute-through-organization-settings), fetched 2026-09-29; repeated on [sync your organization's plugins](https://claude.com/docs/plugins/org-sync#keep-executables-out-of-the-top-level-bin-directory)): "**Top-level `bin/` directory**: claude.ai rejects a plugin that has one and syncs the rest of the marketplace. The error message starts with `Plugin contains a top-level bin/ directory`. Keep executables in another directory, such as `scripts/`, and reference them as `${CLAUDE_PLUGIN_ROOT}/scripts/<name>` from your hooks or MCP server configs". The `source-control` wrappers live under `plugins/source-control/scripts/` and `babysit-prs` invokes them by their `${CLAUDE_PLUGIN_ROOT}/scripts/` paths, so no divergence remains, and `scripts/check-plugin-manifest-presence.sh` fails any plugin that adds a `bin/`. |
| Submit plugins to `claude-community` | reject | This repository is the distribution channel. `claude-community` is Anthropic's third-party catalog with a separate submission bar. Forks may list there; this fleet does not. This is a decision, not a permanent ban: revisit it if a specific plugin gets outside demand. Source: [Anthropic's marketplaces](https://code.claude.com/docs/en/plugins/anthropic-marketplaces#anthropic%E2%80%99s-marketplaces). |

- **Claim:** the table records the marketplace's stance on each named schema feature and gotcha.
  The rows record the fleet's positions; no `marketplace.json` field changes in this record.
- **Basis:** #3616. Fetched 2026-09-28:
  [marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference)
  (strict, sources, `renames`, `headersHelper`),
  [plugin loading](https://code.claude.com/docs/en/plugins/loading) (version order, auto-update),
  [host a marketplace](https://code.claude.com/docs/en/plugins/host-marketplace)
  (bulk/auto-update skip of `headersHelper` / command sources; top-level `bin/` under
  organization settings),
  [sync your organization's plugins](https://claude.com/docs/plugins/org-sync)
  (`bin/` rule; fetched 2026-09-29),
  [Anthropic's marketplaces](https://code.claude.com/docs/en/plugins/anthropic-marketplaces)
  (`claude-plugins-official` vs `claude-community`).
- **As of:** 2026-09-28; the `bin/` row and the two pages it cites, 2026-09-29.
- **Recheck:** a Claude Code release note, or a change to a row's linked page, alters the
  `strict` default, relative-path resolution under a `url` marketplace source, command-source
  bulk behavior, the version rung order, the community submission bar, or the top-level `bin/`
  rule; a maintainer revisits the `claude-community` reject (for example, outside demand for one plugin);
  or the `renames` reject changes.

## Local development loop

For a plugin that already ships here, iterate against your local clone without re-publishing and
without changing any consumer's marketplace registration. `--plugin-dir` loads a plugin straight from
a directory; when its `name` matches an installed marketplace plugin, **the local copy takes
precedence for that session**, so you exercise working-tree edits against the installed copy without
uninstalling it (verified 2026-06-24; recheck when the plugins reference changes how
`--plugin-dir` resolves a name that matches an installed plugin).

```shell
# from this repo root: point at the plugin directory, not the marketplace root
claude --plugin-dir ./plugins/<name>
```

- **Edit, then `/reload-plugins`** to pick up changes without restarting. It reloads skills, agents,
  hooks, and plugin MCP/LSP servers, reading the files on disk, so no commit or reinstall is needed.
- **Multiple plugins at once.** Pass the plugins folder, `claude --plugin-dir ./plugins`, when you
  want the whole working tree in the session; repeat the flag for only the plugins you are changing,
  `claude --plugin-dir ./plugins/<a> --plugin-dir ./plugins/<b>`, when the rest should stay on the
  installed copies.
  `--plugin-dir` also accepts a `.zip` archive (Claude Code v2.1.128+). See
  [Create plugins](https://code.claude.com/docs/en/plugins/create#from-a-directory-or-zip) "From a directory or `.zip`".
  - **Pointer**: when choosing between the folder and per-plugin forms, fetch
    [plugin commands: flags that load a plugin for one session](https://code.claude.com/docs/en/plugins/cli-reference#flags-that-load-a-plugin-for-one-session)
    live.
  - **As of**: 2026-10-10
  - **Recheck trigger**: that section changes what a folder of plugins loads.
- **Session-scoped and non-destructive.** The override lasts only for that session and never edits a
  consumer's `extraKnownMarketplaces`; the published registration stays on its GitHub remote. The lone
  exception: `--plugin-dir` cannot override a plugin that *managed* settings force-enable or
  force-disable.
- **Trust.** A locally loaded plugin carries the same trust considerations as any source, so only load
  directories you control.
- **Then ship.** Run `claude plugin validate` before opening a PR; after merge, consumers pull the
  change with `/plugin marketplace update melodic-software`, gated by the `version` bump in `plugin.json`.

## Fresh-consumer onboarding

Reintegration (below) covers a repo that already ran an in-repo copy and now switches to the plugin. A
**brand-new** repo adopting the marketplace for the first time follows this checklist:

1. **Register the marketplace, checked in for clones.** Interactive: the trust dialog on first
   `/plugin` use registers the marketplace and installs enabled plugins. For project-wide adoption,
   declare the marketplace in the project's checked-in `.claude/settings.json` `extraKnownMarketplaces`
   (headless: `claude plugin marketplace add <repo> --scope project`). A bare `claude plugin marketplace
   add <repo>` writes to *user* settings, so a fresh clone or CI agent on another machine would carry the
   enabled plugin but have no registered marketplace to resolve it from. Mirror the Reintegration
   cutover, which pairs both fields in the project settings.
2. **Enable at project scope** so every clone inherits it: declare `enabledPlugins` in the same
   checked-in `.claude/settings.json` (choose user scope instead for machine-wide, not per-repo).
3. **Install and seed config.** Pass every option on the install command: `claude plugin
   install <plugin>@<marketplace> --scope project --config KEY=VALUE …` (repeatable, schema-validated).
   Where the values are stored, whatever the enable scope, is in
   [Configuration ownership and scope](plugin-philosophy.md#configuration-ownership-and-scope).
   Re-running that command later against an already-installed plugin prints `already installed`
   **and still writes the value** (smoke-test C), so a headless reconfiguration is another `--config`
   install rather than an uninstall/reinstall. The verified-version record, which covers a
   same-scope `--scope project` rerun of a `string` option, lives in the
   [plugin-reconfiguration convention](contracts/plugin-reconfiguration/README.md#verified-version-record).
   A rejected value still exits 0, so read the stored value back rather than assuming the write
   landed. For a non-sensitive option, read it
   from where that storage rule puts it, not from the project
   settings this command names; a `sensitive` value is absent from settings entirely (smoke-test A)
   and cannot be verified this way. Interactively, `/plugin configure` owns personal
   `userConfig`; an explicit setup skill owns any separate tracked project configuration declared by
   the plugin.
4. **Headless prompting caveat.** Install never prompts non-interactively, and a required `userConfig`
   option left unset does **not** block the install; it stays advisory until set (smoke-test C). Seed
   every required option on the install command so the plugin does not run unconfigured.

## Reintegration: a consumer adopts the published plugin

The forward migration (above) ends at *publish*. The lifecycle closes when the source repo stops running
its in-repo copy and instead **consumes the published plugin**: one source of truth, and the repo
dogfoods the marketplace. Reintegration is a *consumer-side* change: adapt through the documented
extension points, never by teaching the plugin a consumer's specifics.

**The plugin is generic; the consumer's own extension points restore its specifics.** Map each behavior the
in-repo hook had that the generalized plugin dropped to one of these, in order:

- **Kill switch / toggles** → the plugin's own `userConfig` toggles (`/plugin configure`
  interactively, `claude plugin install --config` headless), which are user-scoped, replacing the in-repo
  `HOOK_<OLD>_ENABLED` env var. Per-repo control is the plugin's `enabledPlugins` entry; a genuinely
  project-scoped per-hook need is a plugin gap (below), not an env var.
- **Project conventions** → for a hook plugin, the consumer's own tool config files that the hook already
  reads (`biome.json`, `.shellcheckrc`, `.editorconfig`, …). That is where these plugins pick up project
  conventions, **not** `CLAUDE.md`. (`CLAUDE.md` / `.claude/rules` reach only a plugin's *skill/agent*
  components, which run in Claude's model context; hook scripts see only env vars and file-based config.)
- **Telemetry / observability** → the consumer's own **telemetry sink**. This is the key extension point: the
  plugin emits the generic telemetry envelope contract to `HOOK_TELEMETRY_SINK`, and the consumer's sink
  script translates that envelope into the consumer's local observability shape. A consumer whose prior
  hook emitted a different status or hook-identity (e.g. `status=error` on a surfaced violation, or a
  legacy hook name) restores that contract **in its own sink**, by remapping the plugin's native envelope
  (`status=ok` + populated `findings`), not by changing the plugin. Before remapping, verify how the
  consumer's observability actually keys events (e.g. on `status` vs a derived `exit_code`/findings count),
  so the remap preserves the real contract rather than a guessed one.

If a genuine specific has **no** extension point, that is a real plugin gap → add a declared extension
(`userConfig`, or a tracked consumer-project config key), but only when it carries
real behavior, not cosmetic prose a consumer's `CLAUDE.md` already establishes. Resist adding config
surface to a published plugin for a single consumer's low-value nicety.

**Cutover checklist:**

1. Register the marketplace in the consumer's `extraKnownMarketplaces` and enable the plugin in
   `enabledPlugins` (project `settings.json`, so clones inherit it on trust, and the interactive trust prompt
   both registers and installs the enabled plugin for **local** collaborators). **Headless CI** and other
   non-interactive runs with **remote/git-sourced** catalogs have no such prompt, and registering a
   marketplace does not install its plugins, so do both explicitly at project scope: `claude plugin
   marketplace add <repo> --scope project` then `claude plugin install <plugin>@<marketplace> --scope
   project --config KEY=VALUE …`, seeding every
   non-default `userConfig` toggle on that install command. Re-running it later against an
   already-installed plugin prints `already installed` **and still writes the value** (smoke-test C),
   so a headless reconfiguration is another `--config` install, not an uninstall/reinstall. The
   verified-version record, which covers a same-scope `project` rerun of a `string` option (the
   scope this step uses), lives in the
   [plugin-reconfiguration convention](contracts/plugin-reconfiguration/README.md#verified-version-record).
   A rejected value still exits 0, so read the stored value back before reporting a
   project-scope reconfiguration as applied. For a non-sensitive option, read it from where
   [Configuration ownership and scope](plugin-philosophy.md#configuration-ownership-and-scope) puts it whatever the enable
   scope, not from the project settings this command names; a
   `sensitive` value is absent from settings entirely (smoke-test A) and cannot be verified this way.
   **Exception:** a `directory`/`file` relative-path entry in checked-in project settings resolves
   against the repo checkout (cloud sessions included). See
   [`docs/cloud-sessions.md`](cloud-sessions.md). Otherwise the marketplace is known but the plugin is absent, and step 3's
   verify edit would run with no plugin hook.
2. Interactively, `/plugin configure` adjusts `userConfig` toggles at any time; keep the
   `HOOK_TELEMETRY_SINK` wiring and the sink script (the bridge), adapting the sink for any
   observability-contract divergence.
3. **Verify before retiring** the old hook (blue-green: keep it recoverable, but never run both on the
   same edit). Matching `PostToolUse` hooks run concurrently, so leaving both registered would race two
   formatters on the just-edited file (last-writer-wins clobbering, plus doubled telemetry and context).
   Idempotence only makes *serial* re-runs converge, not concurrent writes safe. So **exactly one is
   active at a time**: disable the in-repo hook by setting its kill-switch env var to `"false"` (or, if it
   has none, removing its registration entry: `settings.json` is JSON, so toggling the value or removing
   the entry is the edit, never a `//` comment). With the old hook off and the plugin enabled, edit a
   governed file and confirm: the plugin formats/lints and surfaces findings, the telemetry sink receives
   the expected envelope (so a broken remap is caught now, not when observability is next needed), and the
   consumer's hard gate (commit hooks, CI) is untouched, since those are independent of the edit-time hook. If
   verification fails, **disable the plugin first, then re-enable the old hook** (always flip one off as you
   turn the other on) and debug before retrying, so the two never run together and there is never a
   no-hook gap.
4. Only once verified, remove the in-repo hook's `settings.json` registration and delete the hook script
   **and its test**.

**Bootstrap-direction caveat.** While a repo is still the harvest *source* (its hooks are mid-migration
out), reintegrating one plugin makes it consume one plugin while still running the rest in-repo, a mixed
state. Flip a repo from source to consumer deliberately, not incidentally, and ideally once the repo's
ported plugins can move together.

**Cross-surface caveat: a repo-built `stdio` MCP server declared on more than the Claude Code surface.**
The checklist above assumes a hook plugin, whose only consumer is Claude Code. A marketplace plugin is
Claude-Code-only, so **a marketplace-plugin cutover replaces the Claude Code surface only.** A repo-built
`stdio` MCP server, however, is often declared on additional surfaces: Cursor (`.cursor/mcp.json`), Codex
(`.codex/config.toml`), and Claude Desktop (a `tools/desktop-mcp` installer), none of which can consume a
Claude Code marketplace plugin. When such a server also has **no npx/registry publish** (the playbook's
`stdio` (repo-built), "No CLI" class), those other surfaces have no path to the plugin at all, so deleting
the in-repo build strands the server on every non-CC surface. Compounding this, the MCP-parity CI gates
enforce **exact equality** across `.mcp.json` / `.cursor/mcp.json` / `.codex/config.toml`, so removing the
server from only the CC surface breaks parity. So **resolve cross-surface consumption before deleting the
in-repo server**, picking one:

- **Clean-delete.** Confirm (with the owner) the other surfaces do not need the server, then remove its
  entry from **all** surfaces at once. Parity stays trivially satisfied and no new machinery is needed.
- **Parity exemption.** Keep the in-repo server for Cursor/Codex/Desktop while only the CC surface adopts
  the plugin; this requires an exemption in the parity gates (an `.mcp.json`-only removal otherwise fails
  them) plus a follow-up track for a genuine cross-surface distribution.
- **Defer.** Hold the cutover until the server has a cross-surface distribution path (e.g. repoint the
  other surfaces at the plugin's on-disk bundle, or a shared build), then re-scope.

## What to wait on / avoid for now

- Don't pre-build cross-plugin `dependencies` graphs until two plugins genuinely share a need.
- Don't abstract a shared library before a second consumer exists (Rule of Three); at the threshold,
  [ADR 0019](adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md) is the settled
  shape, so extend it rather than re-deciding.
- Don't rely on any mechanism not confirmed from current docs this session. If a customization need has
  no proven native path yet, record it here as a gap and keep the workaround in the consumer's repo until
  the native mechanism is verified.

## Decision records

Decisions that shaped this playbook live in [`adr/`](adr/), one file each, and are not restated
here. Read the record when you are about to reopen the decision it settled, not while following the
playbook:

- [ADR 0019](adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md), sharing code
  across plugins (2026-07-04).
- [ADR 0020](adr/0020-defer-three-medley-surfaces-with-explicit-recheck-triggers.md), deferred
  surfaces (2026-07-12).
- [ADR 0021](adr/0021-reject-the-three-unused-official-plugin-components.md), unused official plugin
  components (2026-07-12).
- [ADR 0022](adr/0022-consume-the-knowledge-corpus-from-a-separate-repository.md), knowledge-corpus
  consuming repo and integration flow (2026-07-13).
- [ADR 0023](adr/0023-scope-skill-quality-to-the-generic-static-checker.md), `skill-quality`
  retrofit scope (2026-07-13).
- [ADR 0024](adr/0024-decline-forgery-prone-human-ratification-gates.md), convention
  ratification and the shared-identity limitation (2026-07-23).
- [ADR 0092](adr/0092-carry-only-the-miro-mcp-server-in-a-plugin.md), the MCP carry verdicts for
  medley's servers (2026-07-12).
- [ADR 0093](adr/0093-record-plugin-acceptance-security-reviews.md), the plugin-acceptance
  security review records (2026-07-12 onward).
