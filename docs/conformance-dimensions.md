# Conformance dimensions

The registry of what the plugin conformance audit checks. Each row names one dimension, the doc
that owns its rule, the lane that checks it, and the existing checks it composes. The owner doc
carries the rule; this table only points at it.

The skill that runs every lane is not built yet. Until it is, a `judgment:` lane is a question a
reviewer asks by hand, and a command lane runs as written. The approved plan for the skill, and for
the gates it adds, is [the conformance audit plan](https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/plugin-conformance-audit-plan.md). Its
design decisions are in [the design threads](https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/plugin-conformance-design-threads.md).

Columns:

- `id`: stable dimension id. `dim-8`, `dim-9` and `dim-11` keep the meaning fleet hook scripts and
  convention docs already give them; the rest are numbered after them.
- `owner`: `path#Heading text`, the section that states the rule.
- `lane`: what the audit runs for this row. A command runs as written; `judgment:` is the question
  handed to a fresh subagent. A plugin-scope row whose script takes no plugin argument names how its
  output is narrowed.
- `checks`: the existing scripts and skills the lane composes, or `judgment` when none exists.
- `ci`: `yes` when `.github/workflows/ci.yml` runs every script named in `checks`, `indirect` when a
  CI step reaches them through another script, `no` otherwise.
- `scope`: `plugin` runs once per audited plugin; `fleet` runs once per audit run.

`scripts/check-conformance-registry.sh --check` fails a row whose owner heading, path or skill does
not resolve, or whose lane or checks cell is empty.

| id | concern | owner | lane | checks | ci | scope |
|---|---|---|---|---|---|---|
| dim-8 | A plugin that declares `userConfig`, an external prerequisite or non-trivial configuration ships a check-centric setup skill | docs/plugin-philosophy.md#Setup is explicit and repeatable | `node scripts/validate-plugin-contracts.mjs`, findings filtered to `plugins/<plugin>/`; then judgment: does this plugin meet the setup criteria, and if so does its setup skill offer `check` and `apply`, idempotent and safe to rerun? | `scripts/validate-plugin-contracts.mjs`, judgment | yes | plugin |
| dim-9 | Hook status, failure and skip paths are visible: `statusMessage` on every handler, a `systemMessage` on every missing-prerequisite skip (the owner section states the cadence) | docs/conventions/hook-observability/README.md#Conformance | judgment: for each wired hook in `plugins/<plugin>/hooks/hooks.json`, does it meet every bullet of the owner section? | judgment | no | plugin |
| dim-11 | Every cross-plugin reference is presence-gated with a stated fallback, with no marketplace qualification outside an install recipe | docs/conventions/seam-phrasing/README.md#Conformance | judgment: list each reference this plugin makes to another plugin's skill or agent and say whether the gate and fallback are present | judgment | no | plugin |
| dim-12 | The plugin's category fits the taxonomy and the plugin is one cohesive capability | docs/catalog-taxonomy.md#Assignment principle | `bash scripts/check-plugin-manifest-presence.sh`, findings filtered to `plugins/<plugin>/`; then judgment: does the subject-wins-if-salient test pick this category, is the plugin one capability, and has any trigger in the Trigger register fired? | `scripts/check-plugin-manifest-presence.sh`, `scripts/validate-plugins.sh`, judgment | yes | plugin |
| dim-13 | Skill names are imperative verb phrases with the fixed verb meanings; leaf collisions are registered | docs/plugin-philosophy.md#Naming | `bash scripts/check-skill-leaf-names.sh`, findings filtered to this plugin; then judgment: does any skill use a word another plugin uses with a different meaning (check `docs/glossary.md`)? | `scripts/check-skill-leaf-names.sh`, judgment | yes | plugin |
| dim-14 | A natural request reaches the right skill and no other skill catches it too | docs/plugin-philosophy.md#Naming | judgment: in a fresh subagent given only the skill descriptions of this plugin and of every plugin in the same category, which skill does each of five natural requests for this plugin reach, and does a second skill claim it? | `/claude-ops:audit-native-overlap`, judgment | no | plugin |
| dim-15 | A skill is a process; artifacts and external tools sit behind ports with a native default adapter | docs/plugin-philosophy.md#Skills are processes | judgment: for each output the plugin writes and each external tool it drives, name the port, its native default adapter, and whether any other adapter is presence-gated | judgment | no | plugin |
| dim-16 | Every dependency is declared and has a verdict: port, `userConfig`, presence-gated, documented, or fix | docs/plugin-philosophy.md#Prerequisites and failure behavior | `bash scripts/check-skill-portability.sh` and `bash scripts/check-shell-portability.sh`, findings filtered to `plugins/<plugin>/`; then judgment: assign a verdict to each dependency the plugin has | `scripts/check-skill-portability.sh`, `scripts/check-shell-portability.sh`, `scripts/check-hook-userconfig-argv.sh`, judgment | yes | plugin |
| dim-17 | Code reads each value from one owner; docs cite the owner | docs/plugin-philosophy.md#One owner per value | `bash scripts/check-cross-plugin-source-drift.sh`, findings filtered to this plugin; then judgment: for each value stated in more than one file of the plugin, name its owner and each copy | `scripts/check-cross-plugin-source-drift.sh`, `/docs-hygiene:extract-ssot`, `/code-metrics:audit-duplication`, judgment | yes | plugin |
| dim-18 | Manifests validate and every skill meets the skill layout contract | docs/plugin-philosophy.md#Evidence and validation | `bash scripts/validate-plugins.sh`, output filtered to this plugin; `bash plugins/skill-quality/scripts/check-skill.sh plugins/<plugin>/skills` | `scripts/validate-plugins.sh`, `plugins/skill-quality/scripts/check-skill.sh` | indirect | plugin |
| dim-19 | Every Component stances row marked Wait or experimental still holds against current upstream docs | docs/plugin-philosophy.md#Component stances | judgment: fetch each cited page for rows marked Wait or experimental and say whether the stance and its date still hold | judgment | no | fleet |
| dim-20 | A second plugin needing teardown first moves the shared teardown shape into an owner doc | docs/plugin-philosophy.md#Setup is explicit and repeatable | judgment: which plugins ship an `apply remove` or other teardown operation, and if two or more do, does an owner doc define the shared shape? | judgment | no | fleet |
| dim-21 | A plugin that adopts a registered convention conforms to its owner doc; a convention two plugins share has an owner doc | docs/plugin-philosophy.md#Convention registry | judgment: for each Convention registry row this plugin adopts, does it meet the owner doc's Conformance section? | judgment | no | plugin |
| dim-22 | Interactive HTML artifacts carry the reply affordance | docs/finding-your-unknowns.md#Reply-affordance convention | judgment: do this plugin's interactive HTML templates carry the structured capture and reply template the owner section requires? (applies to `prototype`) | judgment | no | plugin |
| dim-23 | Every guardrails hook fix pins its over-fire as a stay-quiet test case | docs/conventions/hook-precision/README.md#Conformance | judgment: for each hook under `plugins/guardrails/hooks/`, does its co-located test carry a stay-quiet case for each over-fire fix? (applies to `guardrails`) | judgment | no | plugin |
| dim-24 | No plugin states a pre-PR step order that conflicts with the canonical one | docs/conventions/pre-pr-ordering/README.md#Conformance | judgment: does any surface in this plugin list pre-PR steps, and if so does it cite the sequence instead of re-listing it in another order? | judgment | no | plugin |
