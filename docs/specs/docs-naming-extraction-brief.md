# docs-naming extraction: brief

Brief for moving the four file-name skills out of `plugins/docs-hygiene` into a new `docs-naming`
plugin. Tracked by
[#5348](https://github.com/melodic-software/claude-code-plugins/issues/5348). This document is a
proposal for the owner to sign off on. It changes no code, no plugin directory, no marketplace
file, and no ratified contract. Implementation is a separate follow-up after sign-off.

The split and the shared audit router were decided in the owner decision on
[#4142](https://github.com/melodic-software/claude-code-plugins/issues/4142#issuecomment-5895174537)
(Q1 and Q5). Every `file:line` below is pinned to `origin/main` at `56e4800a1`.

## Contents

- [Scope](#scope)
- [Decisions this brief takes](#decisions-this-brief-takes)
- [1. Config surface](#1-config-surface)
- [2. Artifact contract](#2-artifact-contract)
- [3. Gate emitter and drift test](#3-gate-emitter-and-drift-test)
- [4. marketplace.json entry](#4-marketplacejson-entry)
- [5. README and CHANGELOG parity](#5-readme-and-changelog-parity)
- [6. Cross-references](#6-cross-references)
- [7. Versions](#7-versions)
- [8. Shared audit router](#8-shared-audit-router)
- [Listing budget and the concern boundary](#listing-budget-and-the-concern-boundary)
- [Implementation order](#implementation-order)
- [Open question](#open-question)
- [Verification record](#verification-record)

## Scope

Moves, as one unit, `setup`, `audit-file-names`, `realign-file-names` and `generate-file-name-gate`,
plus the plugin-level files only they read. Does not move `rename-references`, which stays in
`docs-hygiene` and is the post-rename sweep for a rename someone already made. `docs-hygiene` still
needs a check-only `setup` (or a documented exemption) for its `markdownlint-cli2` prerequisite;
see "What `docs-hygiene` keeps" in section 1 and decision 1c.

Plugin-level files that move with the four skills, because every reader is a moving skill:

| File | Read by |
|---|---|
| `plugins/docs-hygiene/reference/config.md` | `audit-file-names/SKILL.md:46`, `setup/SKILL.md` |
| `plugins/docs-hygiene/reference/topic-docs.md` | `audit-file-names/SKILL.md:45`, `realign-file-names/SKILL.md:47` |
| `plugins/docs-hygiene/context/file-name-findings.md` | `audit-file-names/SKILL.md:44`, `realign-file-names/SKILL.md:45` |
| `plugins/docs-hygiene/scripts/resolve-config.sh` and `.test.sh` | five scripts, listed in item 1 |
| `plugins/docs-hygiene/lib/config-root.sh` | `resolve-config.sh:145` |

`plugins/docs-hygiene/context/clean-tree-fallback.md` and `derivability-route-followups.md` have no
reader among the four skills (`git grep -n 'clean-tree-fallback\|reference/topic-docs\|reference/config.md\|file-name-findings.md' -- plugins/docs-hygiene`)
and stay.

Out of scope: the macOS runner. The owner decision files it only if wanted.

## Decisions this brief takes

Each has a `Basis:` in its item. The owner may overrule any of them at sign-off. Only the router is
put as an open question in full, because the owner reserved it; the rest are recommendations with
the alternative named.

| # | Decision | Recommendation |
|---|---|---|
| 1a | Consumer config file name | Rename to `.claude/docs-naming.json` with a one-release read of the old name |
| 1b | Where `resolve-config.sh` lives | Moves; docs-hygiene keeps no copy and no config surface |
| 1c | `docs-hygiene` `setup` after the split | Keeps a check-only `setup` for `markdownlint-cli2`, or a documented exemption if the contract validator allows one |
| 2 | Findings artifact `type:` and memory concern directory | Rename both to `docs-naming` |
| 3 | Drift test | Stays in `scripts/`; only its two hardcoded paths change |
| 4 | Catalog entry | `maintenance`, next to `docs-hygiene`; enablement decided by the fleet list or an explicit key |
| 7 | Versions | `docs-hygiene` 0.24.0 (breaking), `docs-naming` 0.1.0 |
| 8 | Audit router | No new skill now; see [Open question](#open-question) |

## 1. Config surface

**What it is.** One consumer surface, `.claude/docs-hygiene.json`, in three layers: user-global
`~/.claude/docs-hygiene.json`, team `<repo>/.claude/docs-hygiene.json`, and a gitignored overlay
`<repo>/.claude/docs-hygiene.local.json` (`plugins/docs-hygiene/reference/config.md:27-31`). Its
keys are documented in `reference/config.md`, and it is resolved by
`plugins/docs-hygiene/scripts/resolve-config.sh`. The resolver reads its bundled defaults from
`skills/setup/templates/docs-hygiene.json` (`resolve-config.sh:73`, `:127`, `:200`) and sources
`lib/config-root.sh` (`resolve-config.sh:145`). Both dependencies move with it, so the moved
resolver's relative paths stay valid inside `docs-naming`.

**Every consumer of `resolve-config.sh`**, from `git grep -n resolve-config.sh` at the pinned commit.

| Site | Kind | Disposition |
|---|---|---|
| `skills/audit-file-names/scripts/inventory.sh:50` | caller | moves |
| `skills/audit-file-names/scripts/sweep.sh:53` | caller | moves |
| `skills/realign-file-names/scripts/apply-rename.sh:51` | caller | moves |
| `skills/generate-file-name-gate/scripts/emit-gate.sh:48` | caller | moves |
| `skills/setup/scripts/setup-check.sh:28` | caller | moves |
| `scripts/resolve-config.test.sh` | owner's test | moves with the script |
| `reference/config.md:164-165` | doc citing the path | moves; paths rewritten to `docs-naming` |
| `docs/conventions/config-cascade/README.md:407`, `:432` | registry rows | stay; edited to name `docs-naming` |
| `plugins/docs-hygiene/CHANGELOG.md:7`, `:327` | released entries | stay, unedited |

That is five callers in four skills. The resolver's own header says "Four callers in three skills"
(`resolve-config.sh:4`), which is already stale and gets corrected when the file moves.

**Files that look similar but are not consumers and do not move.**

- `plugins/testing/scripts/resolve-config.sh` is a separate resolver for `.claude/testing.yaml`
  (`plugins/testing/scripts/resolve-config.sh:2`). `docs/specs/tautological-tests.md:280` and `:720`
  record it as "modeled on ... not imported" from the docs-hygiene resolver, per the
  shell-test-helpers rule against cross-plugin imports. Its callers (`testing/skills/audit/scripts/cant-fail-scan.sh`,
  `testing/skills/setup/scripts/setup.sh`) are unrelated. Only the two prose mentions in
  `docs/specs/tautological-tests.md` name the old path, and that spec is historical tier, so they
  are reported, not rewritten.
- `docs/conventions/config-cascade/` is the convention the surface implements, not a consumer of the
  script. It carries two rows that must be edited (the Implementers row at `:407` and the root-rule
  row at `:432`), and one rule the move must respect: the surface's `<name>` is a path relative to
  `.claude/` and is not tied to a plugin name (`docs/conventions/config-cascade/README.md:38`).
- `docs/specs/tautological-tests/probes.md:100` mentions `resolve-config.sh --quick`, which is the
  testing plugin's flag, not this one.

**The `lib/config-root.sh` copy.** It is a byte-identical synced copy of the source-control
resolver. `scripts/sync-config-root.sh:33` and `scripts/sync-config-root.test.sh:20` list
`plugins/docs-hygiene/lib/config-root.sh` as a carrier. The carrier entry changes to
`plugins/docs-naming/lib/config-root.sh`, and `docs-hygiene` drops its copy, because after the
split it has no config surface to classify a root for.

**What `docs-hygiene` keeps.** No config surface. The plugin contract requires a
`setup` skill only for a consumer configuration surface, an external prerequisite, or non-trivial
`userConfig` (`docs/plugin-philosophy.md:483-486`). `docs-hygiene` has no `userConfig`
(`plugins/docs-hygiene/README.md:72`). Its one external prerequisite is `markdownlint-cli2` for
`compress` (`README.md:36-42`), which is a prerequisite under criterion (b), so `docs-hygiene`
keeps a check-only `setup` for it or a documented exemption; it does not end up with no `setup`
unless the contract allows that. Whether `scripts/validate-plugin-contracts.mjs` flags the
plugin is not settled by reading the script (its checks at `:102-226` run over setup skills that
exist, and none of the lines read enforce presence), so the implementation runs it before
deciding. This is a check for the implementer, not a decision for the owner.

**Recommendation 1a: rename the consumer file to `.claude/docs-naming.json`.**

- **Basis:** the config-cascade convention keys the surface by a path under `.claude/` and does not
  tie it to a plugin name (`docs/conventions/config-cascade/README.md:38`), so both choices
  conform. The rest is judgment: after the split the file is read by one plugin only, and a file
  named for a plugin that no longer reads it invites an edit that has no effect.
- **Cost:** existing consumers hold `.claude/docs-hygiene.json`. This repository's own is
  `.claude/docs-hygiene.json`, read by `scripts/check-docs-naming.test.sh:186` and named in
  `.github/workflows/ci.yml:204` and `.github/workflows/test-windows.yml:128`.
- **Migration:** `resolve-config.sh` reads the old path as a WARN-visible fallback for one minor
  release, and `setup check` names it. The convention's one sanctioned dual-read is defined for a
  migrated skill that finds a retired dedicated file and is declared per surface by a retirement
  record (`docs/conventions/config-cascade/README.md:198-208`). Whether a plain rename qualifies for
  a retirement record is part of what the owner signs.
- **Alternative:** keep `.claude/docs-hygiene.json`. No consumer breaks and no migration exists, at
  the cost of a plugin reading another plugin's name. Cheapest to ship, worst to explain.

## 2. Artifact contract

The whole interface between the two skills is one document,
`plugins/docs-hygiene/context/file-name-findings.md`, which both `SKILL.md` files point at and
neither restates (`audit-file-names/SKILL.md:44`, `realign-file-names/SKILL.md:45`).

**Writer.** `audit-file-names` runs three scripts in order: `inventory.sh`, `sweep.sh`, then
`emit-findings.sh` (`audit-file-names/SKILL.md:50-92`). `emit-findings.sh` writes one plan file at
the resolved topic-docs home, `<home>/file-names.md`. It merges into an existing plan by finding id
(`emit-findings.sh:137-147`), refuses a branch mismatch unless `--replace` (`:137-139`), and refuses
to replace a plan holding findings with an empty scan (`:143`).

**Reader and only writer of decisions.** `realign-file-names` finds the plan through the same
topic-docs binding (`realign-file-names/SKILL.md:67-71`) and applies one record per acceptance
through `apply-rename.sh`. That script reads these things from the plan:

| Read | Line |
|---|---|
| `branch:` frontmatter, checked against the current branch | `apply-rename.sh:177` |
| The record id, `^FN-[0-9a-f]+$`, and the `### FN-` heading | `apply-rename.sh:190`, `:195` |
| The old and new paths, parsed from the record's `### FN-` heading | `apply-rename.sh:200-201` |
| The `- **Status:**` line, read and rewritten | `apply-rename.sh:202`, `:243` |
| Every row of the record's site table (file, line, form, tier, action) | `apply-rename.sh:261-266` |

It never reads `type:`. `git grep -n 'docs-hygiene-file-name-findings'` returns four matches:
`emit-findings.sh:215` writes the string, `emit-findings.test.sh:66` asserts it, and
`plugins/docs-hygiene/context/file-name-findings.md:10` and `:39` document it (prose and example
frontmatter). Renaming the type to `docs-naming-file-name-findings` therefore breaks no reader, and
the rename edits all four sites.

**Why the type must never become `review-findings`.** `file-name-findings.md` states that type is
located by frontmatter alone and auto-applicable by construction, while every rename here moves a
tracked file behind one human acceptance. That reasoning moves with the file unchanged, and it is
the reason plugin-contract boundary 5 exempts the file-name set from auto-apply
(`plugins/docs-hygiene/reference/plugin-contract.md:43-48`).

**The concern directory.** The plan lives at `<memory_dir>/docs-hygiene/<branch-slug>/file-names.md`,
default `.work/docs-hygiene/<branch-slug>/` (`plugins/docs-hygiene/reference/topic-docs.md:14-21`).
The directory name is registered in two places in the topic-docs convention:
`docs/conventions/topic-docs/README.md:64` (the tier table) and `:774` (the implementers row). The
`:774` row currently describes two behaviors in one row, the `audit-noise` reader (stays) and the
`audit-file-names` writer (moves), so it splits into two rows.

**Recommendation 2: rename the type and the concern directory to `docs-naming`.**

- **Basis:** the type string is read by nothing (`apply-rename.sh` lines above), so its rename is
  free. The directory rename has one cost, stated below, and is otherwise judgment: the row at
  `topic-docs/README.md:774` is keyed by plugin name.
- **Cost:** a plan written before the upgrade sits under `.work/docs-hygiene/<slug>/`. After the
  upgrade the realign resolves `.work/docs-naming/<slug>/`, finds nothing, and stops with "no plan
  found", which `topic-docs.md` warns is indistinguishable from "no audit has been run"
  (`plugins/docs-hygiene/reference/topic-docs.md:50-54`). A plan is branch-local, checkout-local
  process state (`topic-docs.md:25-30`), so the remedy is a re-audit, and the record
  carries no decision the operator cannot re-make except an in-flight `accepted`, `declined` or
  `blocked` status. The `docs-naming` changelog names this in its first entry.
- **Alternative:** keep the `docs-hygiene` concern directory and type string. Zero migration, at the
  cost of a permanent misnamed directory.

The status arc (`pending` to `accepted`, `applying`, `applied`, `declined`, `blocked`), the
re-audit merge, and the decline-durability offer of an `exempt_paths` entry in the tracked config
(`file-name-findings.md`, sections "Status", "Re-audit merge", "Decline durability") move
unchanged, except that the file's two `type:` mentions (`:10`, `:39`) take the renamed type and the
decline-durability section names `.claude/docs-hygiene.json`, so it follows decision 1a.

## 3. Gate emitter and drift test

**The emitter.** `plugins/docs-hygiene/skills/generate-file-name-gate/scripts/emit-gate.sh` renders
`check-file-names.sh`, its test, and optionally a path-scoped rule into a consuming repository from
three templates (`emit-gate.sh:47`, `:387-393`). It resolves values through `resolve-config.sh`
(`:48`), so it moves with the resolver and needs no change beyond the config path in decision 1a.
The emitted gate carries no run-time dependency on the plugin (`emit-gate.sh:2-6`).

**The drift test.** `scripts/check-docs-naming.sh` is this repository's hand-written gate. Case 11
of `scripts/check-docs-naming.test.sh` (`:175-358`) renders the emitter with this repository's own
config, runs both gates over one seeded tree, and requires the exit code, stdout and stderr to
agree after normalizing three by-construction differences. It has teeth: 11c mutates the config and
requires the two gates to disagree (`:331-`). Two lines hardcode the moving paths:

```text
scripts/check-docs-naming.test.sh:185  EMITTER=".../plugins/docs-hygiene/skills/generate-file-name-gate/scripts/emit-gate.sh"
scripts/check-docs-naming.test.sh:186  REPO_CONFIG=".../.claude/docs-hygiene.json"
```

**A move cannot turn the drift test into a silent pass.** If `EMITTER` points at a missing file,
`drift_emit` (`:288-290`) fails, and the 11a branch reports `fail "template drift: emission failed"`
(`:304`). The test stays in `scripts/`: it guards the repository's own gate against the template, so
it is repository infrastructure, not plugin content. Baseline on the pinned commit:
`bash scripts/check-docs-naming.test.sh` ends `PASS=23 FAIL=0`.

**Other paths that change.**

| Site | Change |
|---|---|
| `.github/workflows/ci.yml:203-204` | shell change-detection filter names the emitter path and the config file |
| `.github/workflows/ci.yml:821-825` | runs the drift test and the gate; no path change, both use `scripts/` |
| `.github/workflows/test-windows.yml:127-128` | the same filter, on the Windows lane |
| `.github/workflows/test-windows.yml:265` | names `apply-rename.test.sh` explicitly; path changes |
| `plugins/docs-hygiene/skills/generate-file-name-gate/scripts/emit-gate.test.sh:25` | builds from `audit-file-names/scripts/fixtures/build-fixture.sh`; both skills move, so the relative path holds |
| `emit-gate.test.sh:157` | `.shellcheckrc` at `../../../../../.shellcheckrc`; depth is unchanged in the new plugin, so it holds |
| `generate-file-name-gate/templates/file-names-rule.md.tmpl:26-27`, `check-file-names.sh.tmpl:8`, `check-file-names.test.sh.tmpl:5` | emitted into consuming repositories; they name `/docs-hygiene:audit-file-names`, `/docs-hygiene:realign-file-names` and `/docs-hygiene:generate-file-name-gate`, so they are rewritten to `/docs-naming:` and any test expectation on those strings changes with them |
| `plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh:35` | `SKILLS=` lists two staying skills and four moving skills; splits into one list per plugin |

The Windows lane matters: `apply-rename.test.sh` exercises the case-only `git mv` path that a
case-sensitive runner cannot, so dropping or misnaming that CI step would let a regression ship
green from Linux alone (`.github/workflows/test-windows.yml:258-265`).

`docs/adr/0034-name-docs-files-lower-kebab-case-with-conventional-exceptions.md:48` cites
`scripts/check-docs-naming.sh --check` as the gate. It is a decision record, so it is not edited,
and the gate path does not change.

## 4. marketplace.json entry

Current entry, `.claude-plugin/marketplace.json:192-197`, for `docs-hygiene`: `source`
`./plugins/docs-hygiene`, category `maintenance`. Proposed new entry, placed next to it:

```json
{
  "name": "docs-naming",
  "source": "./plugins/docs-naming",
  "category": "maintenance",
  "tags": ["maintenance", "documentation", "skill", "file-names", "naming", "rename", "audit", "gate"]
}
```

Category `maintenance` matches `docs-hygiene` and is the vocabulary `docs/catalog-taxonomy.md` owns.
The `docs-hygiene` entry's tags drop nothing that stays true: `compress`, `deduplication` and
`progressive-disclosure` remain its content.

**Registering a plugin touches more than the entry.** The nearest precedent is the split of
`dometrain-mcp` out of `dometrain` (`1438451e1`, #5213), which changed these files and ran these
gates; the implementation follows that checklist.

| Surface | Change | Gate |
|---|---|---|
| `.claude-plugin/marketplace.json` | new entry above | `scripts/validate-plugins.sh` |
| `docs/catalog.md` | generated block, never hand-edited (`docs/catalog.md:3-5`) | `scripts/generate-catalog.mjs --check` |
| `.claude/settings.json` `enabledPlugins` | explicit key only if the fleet list does not enable the plugin | `scripts/check-plugin-catalog-enablement.sh` |
| `plugins/docs-naming/.claude-plugin/plugin.json` | new manifest | `scripts/check-plugin-manifest-presence.sh --check` |
| `plugins/docs-naming/CHANGELOG.md` | new file | `scripts/check-changelog-parity.sh --check`, `--check-bump`, `--check-order` |
| `docs/skill-cheat-sheet.md` | generated | `scripts/generate-cheatsheet.mjs` |

**Enablement is decided outside this repository.** `check-plugin-catalog-enablement.sh` fails a
catalogued plugin that neither the standards fleet list
(`components/cloud-environment/fleet-plugins.json`, a different repository) enables nor
`.claude/settings.json` keys. `docs-hygiene` has no key in `.claude/settings.json` today
(`python3` read of `enabledPlugins`, 8 keys) and the gate passes on the pinned commit, so the
fleet list enables it. Whether
`docs-naming` is covered is a fact about another repository that this brief cannot read. The
implementation runs the gate; when it fails, the resolution is an explicit `enabledPlugins` key
(as `dometrain-mcp` and `animation` have), or a change to the fleet list in standards.

## 5. README and CHANGELOG parity

**`docs-hygiene` README** (`plugins/docs-hygiene/README.md`):

- `:9-12`, the paragraph saying the file-name skills "are slated to move", becomes a pointer to
  `docs-naming`, and the "flavor, noise, duplication, boundary, rename, worth, loading, and
  authoring axes" sentence at `:3-6` loses nothing but the file-name set.
- `:26-29`, four skills-table rows, are deleted.
- `:32-46` Requirements: `jq` was required because the file-name skills read the config with it
  (`setup/SKILL.md`, "A missing `jq` is FAIL"). Whether any staying skill needs `jq` is an
  implementation check with `git grep -n 'jq' -- plugins/docs-hygiene/skills`; the line stays only
  if one does.
- `:70-84` Configuration: becomes "no configuration surface".
- `:86-106` "Renaming files: what the plugin does not do for you" moves whole to `docs-naming`,
  including the Windows-runs-the-case-only-`git mv` note and the macOS-unverified note.

**`docs-naming` README** (new): opening paragraph naming its one concern, a skills table for the
four skills, Requirements (Bash, git, jq), Install, Configuration (the surface and its layers), and
the section moved from `docs-hygiene`. It carries no claim about `docs-hygiene` beyond a pointer to
`rename-references` as the sibling.

**`docs-hygiene` manifest** (`plugin.json:5`): the one-sentence description currently lists the
file-name set at its end; it is rewritten without it. Keywords lose nothing that the file-name set
alone supplied.

**CHANGELOG.** `check-changelog-parity.sh --check-preserved` fails a changelog that drops a
released entry, so every `docs-hygiene` entry that describes the file-name skills (for example
`0.22.0` and `0.23.x`, including `:7` and `:327`) stays as written. The new `0.24.0` entry states
the removal and points at `docs-naming`. The `docs-naming` changelog starts at its first version and
does not copy the old entries.

**Other parity obligations.**

- `scripts/em-dash-purged-paths.txt:243-258` lists `docs-hygiene` globs as purged of em dashes. The
  moved files are covered only if the same globs are added for `plugins/docs-naming/`.
- `docs/conventions/config-cascade/README.md:407` and `:432` (Implementers and root-rule rows) are
  re-keyed to `docs-naming`.
- `docs/native-surfaces.md:1207`, `:1227`, `:1228` and `docs/native-surfaces/records.json:3287`,
  `:3647`, `:3665` hold the `setup`, `audit-file-names` and `realign-file-names` overlap rulings,
  keyed by plugin and fingerprinted. They are regenerated with the overlap tooling, not hand-edited.
- `docs/skill-cheat-sheet.md:229`, `:234` are generated. `scripts/cheatsheet-config.mjs:63` excludes
  `docs-hygiene/generate-file-name-gate` as "infra setup" and becomes `docs-naming/generate-file-name-gate`.

## 6. Cross-references

`git grep -n 'audit-file-names\|realign-file-names\|generate-file-name-gate\|docs-hygiene:setup'`,
excluding the four moving skills and the released changelog, finds these.

**Inside `docs-hygiene`, skills that stay.** Only one skill points at the moving set.

| Site | Reference | Change |
|---|---|---|
| `skills/rename-references/SKILL.md:2` | description ends "A whole tree against a casing rule is docs-hygiene:audit-file-names" | becomes `docs-naming:audit-file-names`; the description's length changes |
| `skills/rename-references/SKILL.md:166-171` | `## Next` names `/docs-hygiene:audit-file-names` | same change |

`write-for-agents`, `extract-ssot`, `compress`, and the audit skills do not name the file-name skills.

**Guarding.** `rename-references` would name a skill in a plugin it does not depend on. Every
cross-plugin reference is either a declared dependency or guarded behind an "if installed" check
with a fallback (`docs/plugin-philosophy.md:108-110`), and optional collaboration stays
presence-gated (`:102-104`). The reference is optional, so it is guarded, not a manifest
dependency. The `## Next` line becomes "if `docs-naming` is installed", with the whole-tree case
handled by hand when it is not.

**Reverse direction: moving skills that name a staying skill.** `realign-file-names/SKILL.md:133`
and `realign-file-names/context/apply-recipe.md:68` tell the operator to run
`/docs-hygiene:rename-references audit orphans <old> to <new>` after each applied pair. That
reference becomes cross-plugin in the other direction and takes the same guard, with the fallback
that the realign's own straggler sweep still runs.

**Repo-wide.**

| Site | Change |
|---|---|
| `plugins/docs-hygiene/reference/plugin-contract.md:14-24`, `:43-48`, `:58-60` | the Enforcement concern row is emptied, the file-name set sentence and boundary 5's per-file clause move, and the closing decision text "move to a `docs-naming` plugin" is now done |
| `plugins/playbooks/skills/repo-sweep/catalogs/hygiene.md:281` | `skill: docs-hygiene:audit-file-names, docs-hygiene:realign-file-names` becomes `docs-naming:*`; the entry carries `applies-when` and `checked: false` |
| `plugins/docs-hygiene/reference/topic-docs.md` | moves to `docs-naming`; `docs-hygiene` keeps no memory-tier concern of its own for these skills |
| `docs/catalog.md:75` | generated; the `docs-hygiene` description regenerates from the manifest |
| `docs/adr/0034-...md:48` | historical, unedited |

**The ratified plugin contract changes.** `plugin-contract.md` is ratified by the owner (`:3-5`).
After the split the Enforcement concern has no skill, the file-name set sentence at `:21-24` is
gone, and boundary 5's clause about renames being gated per file (`:43-48`) is true of
`docs-naming`, not `docs-hygiene`. Amending that document is part of what the owner signs, not a
side edit. The listing-budget decision at `:52-60` states "the extraction PR landing" as its
recheck trigger, so the extraction PR updates its claim and as-of.

## 7. Versions

`docs-hygiene` is at `0.23.19` (`plugins/docs-hygiene/.claude-plugin/plugin.json:4`). Removing four
user-invocable skills, a config surface and a resolver is breaking for any consumer who invokes
`/docs-hygiene:audit-file-names` or keeps `.claude/docs-hygiene.json`.

- **`docs-hygiene` 0.24.0.** The plugin is pre-1.0, and the nearest precedent for a breaking
  extraction is `dometrain` 0.4.x to 0.5.0, whose changelog opens "**Breaking: the MCP server moved
  to `dometrain-mcp`**" under `### Changed` (`plugins/dometrain/CHANGELOG.md`). The entry uses the
  plugin's dated `## [x.y.z] - YYYY-MM-DD` heading (`plugins/docs-hygiene/CHANGELOG.md:3`), and
  names the four moved skills, the new plugin, and the memory-directory and config-file migrations.
- **`docs-naming` 0.1.0.** The precedent for a plugin born from a split is `dometrain-mcp` 0.1.0
  (`plugins/dometrain-mcp/CHANGELOG.md`), with an `### Added` entry naming what moved and from where.
- **Both in one pull request.** `check-changelog-parity.sh --check-bump` needs a new `## [<v>]`
  entry present at head and absent at the base for every manifest version that changed.

**Basis:** the two precedents above and `scripts/check-changelog-parity.sh` header. The specific
numbers are judgment; the owner may prefer a `1.0.0` for `docs-naming` once the config rename
settles.

## 8. Shared audit router

**Question (Q5 of #4142).** A shared entry point for the audit skills, decided together with the
split. Today "audit my docs" can mean `audit-noise`, `audit-derivability`,
`audit-progressive-disclosure`, `audit-encapsulation`, or `audit-file-names`, and a reader picks by
taxonomy.

**Facts.**

- The fleet already ruled on the pattern. A model-invoked router skill that routes the agent is
  REJECTED: under the model-invoked default the always-in-context listing does that job, and a router
  reaching into the deliberately hidden set would defeat the exception classes. The human-side
  problem is answered by `docs/skill-cheat-sheet.md` and `claude-ops:inventory`. Only domain-scoped
  composition routers, whose membership is derived, such as `discipline:sweep-all`, are admitted
  (`docs/conventions/invocation-mode/README.md:197-205`).
- Each audit skill's description already ends in a sibling pointer: `audit-derivability` ("Line-level
  noise is /docs-hygiene:audit-noise"), `audit-noise` ("Code comments:
  /code-tidying:audit-comment-residue"), `audit-progressive-disclosure` ("In-page noise is
  /docs-hygiene:audit-noise; frontmatter QA is /skill-quality:check"), all at `SKILL.md:2`.
- The five audits take different targets: a tree of markdown, one file, agent-facing instruction
  files, skill-private citations, and every tracked file under a root.
- `claude-config:audit-pass` is a composition router, but its lanes are Claude configuration
  (`config`, `memory`, `retirements`, `postures`,
  `plugins/claude-config/skills/audit-pass/SKILL.md:232-235`) and none of them is a docs-hygiene
  audit (`git grep -n 'audit-noise\|audit-derivab\|audit-progressive\|audit-file-names' -- plugins/claude-config/skills/audit-pass`
  is empty).
- `plugins/playbooks/skills/repo-sweep/catalogs/hygiene.md` already lists the docs audits as catalog
  entries (lines 90, 217, 263, 274, 281), so a whole-repo pass over them has a home.
- The budget no longer discriminates (see below): `docs-hygiene` reads 4,278 of 8,000 after the
  split, so one more description fits.

**Options.**

1. **No router.** Rely on the descriptions' sibling pointers, `repo-sweep`, and the cheat sheet.
   Adds no skill and no description.
2. **A composition router in `docs-hygiene`**, for example `docs-hygiene:audit`, that runs the
   read-only audits that stay (`audit-noise`, `audit-derivability`, `audit-progressive-disclosure`,
   `audit-encapsulation`) over one target and merges one report. Model-invoked, membership derived
   from the sibling skills, so it fits the composition carve-out.
3. **A cross-plugin router** that also runs `docs-naming:audit-file-names`. It must guard that
   reference as optional, and its plan-writing sibling is a different artifact and a different
   consent gate than the report-only three.
4. **Fold the audits into `claude-config:audit-pass` lanes.** Widens a plugin whose lanes are all
   Claude configuration.

**Recommendation: option 1, no new skill now.**

**Basis:** `docs/conventions/invocation-mode/README.md:197-205` (a pure router is rejected; the
carve-out needs a composition with derived membership and a real merged output); the
sibling pointers at each audit's `SKILL.md:2`; the budget arithmetic below, which removes the
obstacle #4142 named but does not by itself create a need. Demand for a router is `judgment`: the
only statement of it is one remark in the #4142 issue body. What would settle it is invocation
counts for the four audit skills from the OTEL store (`claude-ops:observability`) and a count of
sessions where the wrong audit was invoked first.

## Listing budget and the concern boundary

**Numbers.** `plugins/skill-quality/scripts/check-listing-budget.sh plugins/docs-hygiene/skills`
reports `aggregate: 5234 chars`, budget 8000, over 11 listing-eligible skills, so 5,234 of 8,000.
Two of the 13 skills are `disable-model-invocation: true` (`setup` and `generate-file-name-gate`)
and are not counted. Measured after the split by pointing the same script at two directories of
symlinks:

| Plugin | Listed skills | Description characters |
|---|---|---|
| `docs-hygiene` after the split | 9 | 4,278 |
| `docs-naming` | 2 (`audit-file-names`, `realign-file-names`) | 956 |
| Sum | 11 | 5,234 |

The 8,000 default is the only listed-skill budget rule (`plugins/docs-hygiene/reference/plugin-contract.md:52-54`,
`plugins/skill-quality/scripts/check-listing-budget.sh` header). The split is not forced by the
budget: 5,234 is inside it today. The 7,986 figure in the #4142 body is a different reading from the
current 5,234 and is not used here.

**The reason to split is the concern boundary, not the budget.** A plugin is "a reusable,
independently useful vertical slice of one cohesive capability" (`docs/plugin-philosophy.md:30`).
The four skills form a slice with their own configuration surface, their own artifact contract, and
their own gate, and they share nothing at run time with `compress` or `write-for-humans` beyond the
word "docs". One boundary point argues the same way: the plugin contract's unifying axis is
"tracked markdown a repository maintains" (`plugin-contract.md:26-27`), but the file-name set judges
every tracked file under a configured root (`inventory.sh:4-5`, `config.md:87`), with code files
exempted by extension (`config.md:92`), and it treats `docs/architecture/landscape.json` as a
generated record. That is a tracked-tree naming concern, not a markdown-content one.

## Implementation order

Separate follow-up after sign-off, one pull request:

1. Create `plugins/docs-naming` and `git mv` the four skills and the six plugin-level files from
   the Scope table; fix relative paths, the resolver header, and the config file name per 1a.
2. Apply the decisions of items 2, 3, 5 and 6 to the moved and staying files. Run
   `scripts/validate-plugin-contracts.mjs`, then give `docs-hygiene` a check-only `setup` for
   `markdownlint-cli2` or file the documented exemption (decision 1c).
3. Register the plugin (item 4 checklist) and bump both versions with both changelog entries (item 7).
4. Run the gates named in items 3 and 4, and `scripts/check-skill-count-claims.sh`. The Windows
   `test-windows` lane covers `apply-rename.test.sh`.

Not part of the implementation: the macOS runner, and any router skill unless the owner chooses
option 2 or 3 below.

## Open question

**The shared audit router.** The owner accepted "decide the router together with the split" and
reserved the decision. The final call stays with the owner. This brief does not implement anything.

- **What it is.** Whether the split adds a shared entry point for the docs audit skills, and if so
  where it lives and what it composes.
- **Options.**
  1. No new skill. Rely on the sibling pointers in each audit description, `repo-sweep`, and the
     cheat sheet.
  2. A composition router `docs-hygiene:audit` over the four report-only audits that stay in
     `docs-hygiene`. Costs one description (the nine listed skills average about 475
     characters, so `docs-hygiene` would read roughly 4,750 of 8,000).
  3. A cross-plugin router that also runs `docs-naming:audit-file-names` behind an "if installed"
     guard.
  4. Add the docs audits as lanes of `claude-config:audit-pass`.
- **Recommendation.** Option 1, on the invocation-mode router verdict, the existing sibling
  pointers, and the absence of any measured misrouting. If the owner wants one, option 2 is the
  admissible form (composition with derived membership), and option 3 is the one to avoid because
  it couples a report-only pass to a plan-writing skill that has a different consent gate.
- **Unblocks.** Whether the extraction PR adds a listed skill to `docs-hygiene`, and so the final
  listing numbers, the `docs-hygiene` description set, and its `0.24.0` changelog entry.
- **Evidence that would settle it.** Per-skill invocation counts for the four audits from
  `claude-ops:observability`, and a sample of sessions where the first audit invoked was not the one
  the user needed.

**Also for sign-off, with recommendations already stated above.** These are not reserved decisions
and proceed as written unless the owner says otherwise.

- **Config file name (1a).** Rename to `.claude/docs-naming.json` with a one-release read of the old
  name. Alternative: keep `.claude/docs-hygiene.json`. Unblocks: every path in item 1 and the
  `ci.yml` and drift-test edits in item 3.
- **Type and concern directory (2).** Rename to `docs-naming`, costing a re-audit for any plan in
  flight. Alternative: keep both names. Unblocks: the topic-docs registry rows and the emitter's
  frontmatter.
- **Ratified plugin contract (6).** Amend `plugin-contract.md` as part of the extraction PR.
  Alternative: a separate small PR before it. Unblocks: the contract's Enforcement row and boundary
  5 wording.
- **Versions (7).** `docs-hygiene` 0.24.0 and `docs-naming` 0.1.0. Unblocks: both changelog entries.

Implementation is a separate follow-up after sign-off. Nothing here is decided by this document.

## Verification record

**Claim:** origin/main has no `plugins/docs-naming`, the four skills are under
`plugins/docs-hygiene/skills`, `resolve-config.sh` has five callers in four skills, `apply-rename.sh`
never reads `type:`, and `docs-hygiene` lists 5,234 of 8,000 characters
of which 956 belong to the two listed file-name skills.
**Basis:** at `56e4800a1`, `ls plugins/docs-naming` (absent); `git grep -n resolve-config.sh`;
`sed -n` of `apply-rename.sh:177-243`; `git grep -n 'docs-hygiene-file-name-findings'`;
`plugins/skill-quality/scripts/check-listing-budget.sh` run over `plugins/docs-hygiene/skills` and
over two symlink directories splitting it; `bash scripts/check-docs-naming.test.sh` (`PASS=23 FAIL=0`).
**As of:** `origin/main` at `56e4800a1`.
**Recheck:** a `plugins/docs-naming` directory landing, a change to any file cited in items 1 to 6,
or a listed-skill addition to `plugins/docs-hygiene/skills`.
