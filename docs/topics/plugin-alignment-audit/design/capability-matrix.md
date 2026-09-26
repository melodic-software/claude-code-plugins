# Plugin alignment audit: capability matrix

Phase 1 of a design session: which parts of the proposed repo-local alignment skill already exist in
this repo, so none of them is built twice. Read from the working tree of `feat/animation-plugin` on
2026-09-24. Sources: the seed notes (`.work/strategy/grouping-audit-skill-seed.md`), the worked examples
(`.work/strategy/repo-map.md`, `position-a.md`, `position-b.md`,
`docs/topics/animation-ports/design/dependency-inventory.md`), and the skills, scripts, docs and CI
cited below. "CI" means a step in `.github/workflows/ci.yml`. No lefthook, pre-commit or `package.json`
script runs any of these checks locally.

Fill kinds for each gap: **extend** (add to an existing skill or script), **new check** (a new
deterministic script), **judgment** (a model-judgment step in the new skill).

## 1. Grouping and taxonomy fit (category, plugin boundary, trigger register)

Existing:

| Implementation | Checks | Kind | CI |
|---|---|---|---|
| `scripts/generate-catalog.mjs:67-102` | The category list matches the Vocabulary tables in `docs/catalog-taxonomy.md`; each plugin's `category` is in that set (`:116-121`) | script | yes, through `scripts/validate-plugins.sh` (`ci.yml:1777`) |
| `scripts/check-plugin-manifest-presence.sh` | Every `plugins/*/` directory has a catalog entry, and every entry has a manifest | script | `ci.yml:927` |
| `scripts/check-plugin-catalog-enablement.sh` | Every catalogued plugin is enabled somewhere a cloud session reads it | script | `ci.yml:943` |
| `scripts/generate-cheatsheet.mjs` | The `workflow-stage` enum. This is a second grouping axis, by sequence of use (`docs/skill-cheat-sheet.md:7-8`) | script | through `validate-plugins.sh` |
| `plugins/instruction-placement/skills/audit` | Which surface instruction content loads from. Not about taxonomy | judgment over `scripts/detect.sh` | no |

Rule owners: category form, assignment principle and singletons are in `docs/catalog-taxonomy.md:13-71`,
and the trigger register is at `:73-97`. The plugin boundary is `docs/plugin-philosophy.md:28` ("one
cohesive capability") and `:92-106`. Hook-split packaging is in ADR 0028 (`docs/plugin-philosophy.md:829`).

Gap: the scripts check only that a `category` value is legal. None checks that it fits: the
"subject wins if salient" test (`catalog-taxonomy.md:26-29`), whether the plugin is one cohesive
capability, whether an existing trigger has fired (for example, an audio plugin landing would fire the
`music` to `audio` rename at `catalog-taxonomy.md:84`), or whether a plugin-scoped revisit condition
was recorded (`:89-97`). Fill: **judgment**. A deterministic change is possible only as an **extend**:
make the trigger register machine-readable, which it is not today.

## 2. Naming (verb rule, collisions, words used elsewhere in the fleet)

Existing:

| Implementation | Checks | Kind | CI |
|---|---|---|---|
| `scripts/check-skill-leaf-names.sh` + `scripts/skill-leaf-name-registry.txt` (for example `:108`, `:123`) | The same leaf directory name in two or more plugins must be registered | script | `ci.yml:779` |
| `plugins/skill-quality/scripts/check-skill.sh:1931` (check 25) | The description's lead matches the verb contract, for example an `audit` skill must read as read-only | script, WARN only | yes, through `scripts/check-changed-skills.sh` (`ci.yml:1247`), changed skills only |
| `check-skill.sh:609` (check 1) | A declared `name` must equal its directory | script | same |
| `scripts/check-docs-naming.sh` | Lower-kebab `docs/` file names, case collisions | script | `ci.yml:788` |
| `plugins/naming/skills/name-it-better/SKILL.md:61,103-104,127-135` | Generates names: verb for an action, a "collision vocabulary" in the brief, three blind generators | judgment | no |
| `docs/glossary.md` + `/domain-driven-design:curate-language` | The repo's resolved vocabulary (`glossary.md:1-10`) | curated doc | no |

Rule owner: `docs/plugin-philosophy.md:116-176`. Verb meanings are at `:134-143`, the qualifier rule at
`:145-147`, the noun exceptions at `:149-176`, and the rule that shared leaf names are fine at
`:210-216`.

Gap: nothing enforces the imperative-verb grammar. `pixel-art` ships the noun skills `scene` and
`sprite` (`plugins/pixel-art/skills/`), which none of the exceptions at `:149-174` cover, and every
check passes them. The leaf registry catches identical names only, not the same word used with two
meanings (`video` as consuming media in `knowledge:video-digest` versus producing it:
`.work/strategy/repo-map.md:74`). Fill: a **new check**, or an **extend** of `check-skill-leaf-names.sh`,
that fails a leaf not in a verb list or the exception list (one data file, the same pattern as the
token files). Word-sense reuse is **judgment**, cross-checked against the glossary.

## 3. Routing (does a natural request reach the right skill)

Existing:

| Implementation | Checks | Kind | CI |
|---|---|---|---|
| `check-skill.sh:748` (check 3) | A trigger phrase is not lost from a description; it detects a phrase moved to a sibling skill, but only against `HEAD` on edit | script | through `check-changed-skills.sh` |
| `check-skill.sh:675` (check 2), `:1133` (check 12) + `scripts/skill-description-cap-baseline.txt` | Description length cap and trigger phrasing present | script | same |
| `plugins/claude-ops/skills/audit-native-overlap/SKILL.md:2` | Overlap between plugin skills and native Claude Code surfaces only, not between two plugin skills | script (`overlap.py`) + human verdicts | through `validate-plugins.sh` (registry self-check) |
| `plugins/claude-ops/skills/audit-skill-visibility/SKILL.md:2` | Whether a description is in the listing at all (budget starvation) | script | no |
| `skill-quality:check listing-budget` | Total listing budget | script | no |

Rule owner: `docs/plugin-philosophy.md:215-216` (the first clause of a description carries the
distinguishing object). `docs/conventions/native-references/` covers native overlap. No section owns
routing between two plugin skills. The one precedent is a collision found by hand during an ADR review
(`docs/adr/0016-source-skill-recommendation-from-the-catalog-not-the-listing.md:94-97`).

Gap: nothing in the fleet asks "which skill would this natural request reach, and does another skill
catch it too?" The seed rates this the highest-signal step (`grouping-audit-skill-seed.md:10-14`).
Fill: **judgment**. A fresh-context subagent is given only the descriptions and a set of requests,
per the fresh-eyes rule (`docs/plugin-philosophy.md:847-857`). A cheap deterministic pre-pass is
possible as a **new check** that lists trigger phrases shared by two or more descriptions, but routing
itself stays judgment.

## 4. Process vs output separation (ports and adapters, native default)

Existing:

| Implementation | Checks | Kind | CI |
|---|---|---|---|
| `plugins/coupling/skills/reduce/reference/remediations.md:19-21` | A generic remedy: "Extract an owned interface at the volatile boundary ... (ports-and-adapters)" | judgment | no |
| `plugins/plugin-quality/skills/audit/reference/recurring-concerns.md:30` (section 3, enforcement tiers) | The nearest check, and it is about what can be gated, not about output ports | judgment, one component | no |
| `docs/conventions/rendered-views/README.md:243` | A selection ladder for one output kind (HTML view): argument, then `userConfig`, then cascade, then shipped default | convention | no |
| `docs/conventions/ecosystem-commands/README.md:8-33` | Build/test/lint commands resolved from a consumer file, not baked into plugins | convention | no |

Rule owner: none. `docs/plugin-philosophy.md` never says "port" or "adapter" in this sense (grep; the
only hit, `:161`, means an upstream port). Its nearest rules are native-first (`:218-239`), config
ownership (`:332-343`), the two-lane posture (`:287-312`) and presence-gated collaboration (`:98-106`).

Gap: the whole fleet-wide rule (`grouping-audit-skill-seed.md:39-45`). This includes a skill body that
owns the process, outputs and external tools behind a port with a native default adapter selected by
`userConfig` and presence, and tool-neutral artifacts. Fill: first a **philosophy section**; the new
skill has no rule to cite until one exists. After that, **judgment**. A heuristic **new check** could
flag an external binary or service called in a skill body with no presence gate, but whether a port
is needed is judgment.

## 5. Hardcoded dependencies and assumptions

Existing:

| Implementation | Checks | Kind | CI |
|---|---|---|---|
| `scripts/check-skill-portability.sh:330-342` + `skill-portability-tokens.txt` | A fixed branch, forge, ecosystem or remote in an agnostic skill; `portability-ok` / `portability-scope` escapes | script, changed files | `ci.yml:1345` |
| `scripts/validate-plugin-contracts.mjs:22-26,263,266` + `org-agnosticism-tokens.txt` | Publisher ids, `MELODIC_*` keys, marketplace-bound setup | script | through `validate-plugins.sh` |
| `validate-plugin-contracts.mjs:275` | No `npx` or runtime downloads in hooks | script | same |
| `scripts/check-shell-portability.sh` + `shell-portability-tokens.txt` | GNU-only shell constructs in `.sh` files and skill markdown | script, changed files (`--all` is not in CI) | `ci.yml:1368` |
| `scripts/check-hook-userconfig-argv.sh` | Bare `${user_config.*}` in hook configs | script | `ci.yml:803` |
| `plugins/claude-config/skills/audit-permission-grants` | Machine paths and tilde paths in grants | script (`permission-rule-check.sh`) | no |
| `/docs-hygiene:audit-encapsulation` | Paths into another skill's or plugin's private files (`docs/plugin-philosophy.md:406-419`) | skill | no |
| `plugin-quality` `recurring-concerns.md:53-64` (section 5), `:65` (section 6) | Hardcoded consumer specifics, cross-platform | judgment, one component | no |
| `coupling` `remediations.md:44-47`, `coupling-model.md:109` | Externalize environment-varying values; one repo hardcoding another's layout | judgment | no |

Rule owners: `docs/plugin-philosophy.md:28-31` (no machine paths or undocumented layouts), `:92-106`
(no sibling-plugin files), `:287-328` (two lanes), `:393-396` (paths anchored at `${CLAUDE_PROJECT_DIR}`),
`:624-642` (declare every prerequisite; classify what happens when it is absent), `:697-708`
(cross-platform).

Gap: the checks match tokens (org, forge, branch, GNU flags). None inventories the seed's other
classes (`grouping-audit-skill-seed.md:47-52`): external binaries and their versions, network ports,
sizes and resolutions, other plugins' file layouts, installed browsers, PATH lookups. None gives each
item a verdict (port, `userConfig`, presence-gated, documented, fix needed). The animation inventory
did that by hand: 48 rows, 27 needing a fix (`dependency-inventory.md:7-17`). Fill: a **new check**
lists candidates (binaries invoked, literal ports, absolute paths, `python`/`bash` bare launches);
**judgment** assigns the verdicts. Do not add a third token file: the philosophy already requires any
new class to reuse or align with `org-agnosticism-tokens.txt` (`docs/plugin-philosophy.md:88-90`).

## 6. Duplicated values and SSOT inside a plugin

Existing:

| Implementation | Checks | Kind | CI |
|---|---|---|---|
| `/docs-hygiene:extract-ssot` (`SKILL.md:2,17`) | Repeated markdown prose; Rule of Three. Code and config copies are flagged but not fixed (`:44-48`) | judgment | no |
| `/code-metrics:audit-duplication` (`SKILL.md:2`) | Code clone classes, minus a sanctioned-replication registry | script (external detectors) | no |
| `scripts/check-cross-plugin-source-drift.sh` + `cross-plugin-source-registry.txt` | Identical files across plugins must be registered, and registered copies must still match | script | `ci.yml:2069` |
| `validate-plugin-contracts.mjs:317-321` | Every `artifact-protocol.md` copy is byte-identical to the canonical one | script | through `validate-plugins.sh` |
| `scripts/check-contract-clause-coverage.py` + `contract-clause-registry.json` | A restated contract clause keeps all its qualifiers | script | `ci.yml:1168` |
| `scripts/check-skill-count-claims.sh` | Skill-count claims in prose match the tree | script | `ci.yml:597` |
| `scripts/sync-plugin-options-docs.py` | README options generated from `userConfig` | script | `ci.yml:875` |
| `plugin-quality` `recurring-concerns.md:40-51` (section 4) | The same fact in several hand-maintained places | judgment, one component | no |
| `claude-config:audit-instructions` (`restatement-scan.py`) | Instruction restatement across surfaces | judgment + pre-scan | no |

Rule owners: `docs/plugin-philosophy.md:332` ("Choose one authoritative owner for each value", written
for configuration), `:389-391` (version: one home), `:490-496` (the runtime artifact is the single
source of truth for setup), `:648-652` (one owner doc per shared concern).

Gap: no check finds one value (a threshold, fps, port, path, tone level) stated in code and docs, or
in several code files, inside one plugin. That class needs a scalar match, not a clone match or a
prose match. The animation work found 26 such values by hand (`dependency-inventory.md:107-145`). The
rule "code reads the value from one owner; docs cite the owner" is only a proposal in that topic
(`:109-110`), not a philosophy rule. Fill: an **extend** of `extract-ssot`'s mixed-cluster path
(`SKILL.md:48` already names it), or a **new check** that lists numeric and path literals repeated
across a plugin's files. The owner decision per value is **judgment**. Promote the rule itself into
the philosophy.

## 7. Plugin-philosophy conformance in general

Existing:

| Implementation | Checks | Kind | CI |
|---|---|---|---|
| `scripts/validate-plugins.sh:80-87` | `claude plugin validate` per plugin, plus `--strict` for the catalog; runs the contract validator and generators | script | `ci.yml:1777` |
| `validate-plugin-contracts.mjs:190-292` | The setup contract (`disable-model-invocation`, check/apply, check-only), no marketplace-bound config, the artifact protocol | script | same |
| `skill-quality:check` (27 checks, `check-skill.sh:609-2070`) | The skill layout contract (owned there per `docs/plugin-philosophy.md:674`) | script | through `check-changed-skills.sh` |
| `plugins/plugin-quality/skills/audit/SKILL.md:2,349` | Behavioral audit of one component against an 8-section checklist | judgment, fresh subagent | no |
| `plugins/codebase-health/skills/audit/SKILL.md:2` | Doc, config, code and architecture claims against reality | judgment, fan-out | no |
| `plugins/claude-config/skills/audit-pass/SKILL.md:15` | An ordered, resumable coordinator that "adds no criteria of its own" | orchestrator | no |

Rule owner: the whole of `docs/plugin-philosophy.md`. The doc repeatedly says "the fleet conformance
audit tracks the gap" (`:427-428`, `:476-477`, `:602-603`) and "Fleet audits check conformance per
row" (`:652`). The seam-phrasing convention says the same (`docs/conventions/seam-phrasing/README.md:71`).

Gap: that fleet conformance audit does not exist. No skill, script or workflow implements it. Its
informal "dim-N" dimension labels have "no central registry defining the numbering"
(`docs/conventions/hook-observability/README.md:56-59`). Also not covered: the setup-iff criteria
(`docs/plugin-philosophy.md:423-464`), the retirement declaration (`:547-553`), and the
prerequisite-absence classes (`:629-634`) as a per-plugin sweep. Fill: this is the new skill's clearest
purpose. It should be the per-plugin form of that audit, with the dimension registry as its data file.

## 8. The method itself

Existing:

| Step | Implementation | Kind |
|---|---|---|
| External domain research | `/discovery:research` and `/discovery:research-deep` (`SKILL.md:2`) | judgment, fresh subagent |
| Adversarial pass | `/planning:devils-advocate`, a single stress-tester with an `incumbent` mode | judgment |
| Several different designs in parallel | `architecture:improve` Design-It-Twice (`SKILL.md:48`); `naming:name-it-better` blind lenses and `tournament` (`SKILL.md:127-135,182`) | judgment |
| Synthesis with an extraction trigger | `extract-ssot` Rule of Three (`SKILL.md:17`); the taxonomy trigger register (`catalog-taxonomy.md:73-97`); "lands in an owner doc before a second plugin adopts it" (`docs/plugin-philosophy.md:651`); the teardown second-adopter trigger (`:600-603`) | doctrine |

Rule owners: `docs/plugin-philosophy.md:726-743` (research precedes design) and `:847-857` (the
plan-attacker bias class requires a fresh context).

Gap: no skill runs two or more fresh agents that each argue a fixed position and then attack it with
12-24 month failure scenarios (the method behind `.work/strategy/position-a.md` and `position-b.md`).
`devils-advocate` attacks one plan; Design-It-Twice designs interfaces rather than arguing positions.
Fill: **judgment** in the new skill, dispatching `/discovery:research` and, for the attack step,
`/planning:devils-advocate`, both presence-gated. Only the "N positions, then converge" step is new.
Record the extraction trigger in the existing register (taxonomy or the plugin README), not in a new
store.

## Existing duplication found

1. **Two publisher/portability token stacks.** `org-agnosticism-tokens.txt` (read by
   `validate-plugin-contracts.mjs:24`) and `skill-portability-tokens.txt` (read by
   `check-skill-portability.sh`). The philosophy already flags the risk and requires alignment if the
   second activates a publisher class (`docs/plugin-philosophy.md:88-90`).
2. **Hardcoded consumer specifics judged in three places:** `plugin-quality` section 5
   (`recurring-concerns.md:53-64`), `coupling:reduce` (`remediations.md:44-47`), and
   `audit-permission-grants`. They differ in scope (one component, any altitude, grants only) and
   none cites the others.
3. **SSOT/DRY judged in three places:** `plugin-quality` section 4 (`recurring-concerns.md:40-51`),
   `extract-ssot`, and `audit-instructions`' restatement scan. They are partitioned by file class and
   surface, but `plugin-quality` section 4 restates the doctrine instead of routing to `extract-ssot`.
4. **Listing budget measured three ways:** `skill-quality:check listing-budget`,
   `claude-ops:audit-skill-visibility`, and the native `/skill-doctor`. These are routed apart in their
   descriptions (`audit-skill-visibility/SKILL.md:2`), so this is deliberate and not a defect.
5. **Two grouping axes:** the catalog taxonomy (`catalog-taxonomy.md`) and the cheat-sheet's
   workflow-stage (`docs/skill-cheat-sheet.md:7-8`). Both are declared and cite each other, so this is
   deliberate.
6. **`check-plugin-catalog-enablement.sh:72`** fetches a hardcoded standards-repo URL. The check is
   itself an instance of concern 5.

## First-cut shape (judgment)

- **An orchestrator, not a new checker.** Follow `claude-config:audit-pass`, which "adds no criteria
  of its own" (`SKILL.md:15`). Step 1 runs the deterministic checks already in CI, scoped to one
  plugin, and reads their output. Step 2 dispatches the existing judgment skills, presence-gated:
  `plugin-quality:audit` per component, `extract-ssot`, `audit-duplication`, `coupling:reduce` in
  report mode, and `name-it-better` only when a rename is proposed. Step 3 adds only the missing
  judgment: taxonomy and boundary fit (concern 1), a routing test in a fresh subagent (concern 3),
  a port verdict per output and tool (concern 4), and a verdict per dependency and value (concerns 5
  and 6). The positions-and-converge method (concern 8) is an optional deep tier.
- **Where it lives:** repo-local `.claude/skills/`, which does not exist yet. The rules it applies
  belong to this marketplace, and the philosophy reserves standalone configuration for
  "project-specific customizations" (`docs/plugin-philosophy.md:108-111`). It audits this
  marketplace's plugins against this marketplace's doctrine, so shipping it as a plugin would carry
  the doctrine to consumers who do not hold it. `plugin-quality:audit` stays the portable per-component
  auditor. Revisit if a second marketplace adopts `docs/plugin-philosophy.md`.
- **Not restating the philosophy:** the skill body cites sections by path, not by heading anchor,
  because anchors are barred as citation targets (`docs/plugin-philosophy.md:415-416`). It keeps one
  data file: the dimension registry that `hook-observability/README.md:56-59` says is missing. Each
  row gives a dimension id, the owning philosophy section or convention doc, and the check or skill
  that implements it. Rules added first to the philosophy (not to the skill): process vs output ports
  (concern 4), the intra-plugin value-SSOT rule (concern 6), and the inventory classes for concern 5.
  Name the skill with a verb from `:134-143` (`audit`, with a later `realign`), chosen through
  `/naming:name-it-better`.
- **Deterministic parts:** the existing CI scripts run against one plugin; the new candidate lists
  (leaf-name grammar, repeated trigger phrases, repeated literals, invoked binaries, ports and
  absolute paths). Put these in `scripts/` so CI can run them too, not only inside the skill.
- **Judgment parts:** category and boundary fit, the routing test, port verdicts, dependency and
  value verdicts, word-sense collisions, and the positions method. Every self-grading step runs in a
  fresh context (`docs/plugin-philosophy.md:847-857`).
