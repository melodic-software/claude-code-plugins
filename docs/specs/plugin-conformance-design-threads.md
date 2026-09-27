# Plugin alignment audit: design threads

Phase 2 of the design session. Input: `capability-matrix.md` (concerns 1-8, "Existing duplication
found", "First-cut shape"). The philosophy sections this audit enforces, "Skills are processes" and
"One owner per value", are read from the `feat/animation-plugin` copy of `docs/plugin-philosophy.md`
until #4534 merges; line numbers below cite that copy.

Status key: **RESOLVED** (decided), **DIRECTIONAL** (direction agreed or recommended, details for
`/planning:plan`), **OPEN** (needs the user; each carries a recommendation), **DEFERRED** (research or
trigger tag).

| # | Thread | Status |
|---|---|---|
| T1 | Orchestrator in `.claude/skills/` | RESOLVED |
| T2 | Philosophy rules and concern registry first | RESOLVED |
| T3 | New deterministic scripts | RESOLVED |
| T4 | Existing overlaps become follow-up issues | RESOLVED |
| T5 | Own branch off main | RESOLVED |
| T6 | Name chosen with `/naming:name-it-better` | RESOLVED (process); name itself is T8 |
| T7 | Phantom "fleet conformance audit" citations | RESOLVED: A, this skill becomes that audit |
| T8 | Skill name | RESOLVED: `audit-plugin-conformance` |
| T9 | Concern registry: home and row shape | RESOLVED: `docs/conformance-dimensions.md` |
| T10 | Verb-name check: gate or advisory | RESOLVED: CI gate with baseline |
| T11 | Follow-up issue list | RESOLVED: #4582-#4586 filed; item 5 waits for the baseline run |
| T12 | Remaining philosophy rule: dependency inventory classes | RESOLVED |
| T13 | Script shape: extend vs new, CI wiring | RESOLVED |
| T14 | Target scope, fan-out and findings persistence | RESOLVED |
| T15 | Judgment steps and the positions tier | RESOLVED; positions tier TAGGED-DEFERRED |
| T16 | Test-seam posture | RESOLVED |
| T17 | Sequencing against #4534 | RESOLVED |

## Resolved (user decisions, 2026-09-24)

### T1. An orchestrator composing existing checks, in `.claude/skills/`

Decision: the skill adds no checks of its own beyond T3's scripts; it runs the existing CI scripts
scoped to one plugin and dispatches the existing judgment skills presence-gated, following
`claude-config:audit-pass`, which "adds no criteria of its own" (`audit-pass/SKILL.md:15`). It lives
repo-local in `.claude/skills/` (the directory does not exist yet).

Rationale: capability-matrix concerns 1-7 each already have a partial owner; re-implementing them
would be a second owner of each check, the defect the audit exists to find. Repo-local because it
applies this marketplace's doctrine; shipping it as a plugin would carry the doctrine to consumers
who do not hold it (`docs/plugin-philosophy.md:110-112` reserves standalone config for
project-specific customizations). `plugin-quality:audit` stays the portable per-component auditor.
Revisit trigger: a second marketplace adopts `docs/plugin-philosophy.md`.

### T2. The philosophy rules and a concern registry come first

Decision: rules land in `docs/plugin-philosophy.md` before the skill cites them, and the skill reads
one concern registry instead of restating the philosophy. "Skills are processes" (`:220-235`) and
"One owner per value" (`:440-456`) landed in #4534 and close concerns 4 and 6's missing-rule gap.

Rationale: an audit with no rule to cite is opinion. The registry is the missing dimension home that
`docs/conventions/hook-observability/README.md:56-59` names ("no central registry defining the
numbering").

### T3. New deterministic scripts for verb names, dependencies and value duplication

Decision: three candidate-list scripts: leaf-name verb grammar (concern 2), dependency inventory
(concern 5: invoked binaries, literal ports, absolute paths, bare `python`/`bash` launches), and
repeated literals within a plugin (concern 6). They live in `scripts/` so CI can run them too.
Verdicts on what they list stay judgment. Shape: T13.

Rationale: these three are the gaps where a scalar or grammar match exists and no current check makes
it (the animation inventory found 48 dependencies and 26 duplicated values by hand,
`docs/topics/animation-ports/design/dependency-inventory.md`, pruned; in history at
`fe29b787d4dc998861e9a0e5144334566f90cbe2`).

### T4. Existing overlaps are filed as follow-up issues

Decision: overlaps found in existing checks are not fixed inside this work; they become issues. The
list is T11; filing waits for the user's OK.

Rationale: keeps this branch to the audit itself; each overlap has its own owner and blast radius.

### T5. Own branch off main

Decision: `feat/plugin-alignment-audit`, draft PR #4538.

Rationale: independent of the animation and pixel-art plugins it will audit.

### T6. Name chosen with `/naming:name-it-better`

Decision: the name is picked by the user from a `/naming:name-it-better` run, not locked by the
design. T8 carries the candidates.

Rationale: blind generators break the anchor on a name the design session already leaned toward, and
the name is hard to change once docs and citations use it (T7).

## Resolved (user decisions, 2026-09-27)

### T7. Phantom "fleet conformance audit" citations

The citing sites, none backed by a skill, script or workflow:

| Site | Text |
|---|---|
| `docs/plugin-philosophy.md:254` | "re-verified against current docs before each fleet audit" |
| `:301-303` | "Re-verify before each audit." (Monitors, Themes, Channels rows) |
| `:462-464` | "the fleet conformance audit tracks the gap" (formatter/linter setup) |
| `:512-513` | "the fleet conformance audit tracks the gap" (pre-contract setup skills) |
| `:637-639` | "a step the fleet conformance audit checks" (teardown second adopter) |
| `:688` | "Fleet audits check conformance per row." (convention registry) |
| `docs/conventions/seam-phrasing/README.md:71` | "Fleet audits check dim-11-adjacent seam phrasing" |
| `docs/conventions/hook-observability/README.md:56-59` | "informal fleet-conformance shorthand ... no central registry" |

Options:

- **A. This skill becomes that audit.** Each site is rewritten to name the skill, and each promise
  becomes a registry row (T9) with an implementing check: native-stance re-verification (`:254`,
  `:301-303`), setup-coverage gap (`:464`, `:513`), teardown second-adopter trigger (`:638`),
  convention-registry conformance (`:688`), seam phrasing (dim-11), visible skip (dim-9).
- **B. Remove the citations.** The doctrine stops promising enforcement it does not have; the gaps go
  untracked.
- **C. Tag them** "(planned: #4538)" now and rewrite when the skill ships.

Recommendation: **A**, with the citation edits landing in the same PR as the skill so no commit
cites a missing skill; C only if the skill slips past one release. A is the reason concern 7 is "the
new skill's clearest purpose". Unblocks: T9's first registry rows and the skill name's wording (T8).

**Decision (user, 2026-09-27): A.** The skill becomes the fleet conformance audit; every site above is
rewritten in the skill's PR to cite `/audit-plugin-conformance` and its registry row. Rationale: the
doctrine keeps its enforcement promises and each one gets a named check, instead of silently dropping
tracked gaps (B) or shipping a placeholder (C).

Addendum (plan review, 2026-09-27): four more live sites make the same promise and are rewritten too:
`docs/finding-your-unknowns.md:142`, `docs/conventions/hook-precision/README.md:66`,
`docs/conventions/pre-pr-ordering/README.md:69`, `docs/conventions/hook-observability/README.md:281`.
Frozen records (CHANGELOGs, dated research, `docs/topics/`) stay as written. Approved by the user
2026-09-27.

### T8. Skill name

A repo-local skill has no plugin namespace, so the leaf is the whole name. Preliminary candidates,
verb first per `docs/plugin-philosophy.md:118-176`, for the `/naming:name-it-better` run to extend
or beat:

| Candidate | For | Against |
|---|---|---|
| `audit-fleet-conformance` | Matches the eight existing citations (T7 A needs the least rewording) | "fleet" also means the repo fleet (`repo-fleet-hygiene`) and the machine fleet (`/fleet:reach`) |
| `audit-plugin-conformance` | Names the object; no "fleet" collision | Reads as one plugin; the skill also runs over all |
| `audit-plugin-alignment` | Matches the topic slug and PR title | "alignment" is vaguer than "conformance" |
| `audit-plugins` | Shortest | Collides in meaning with `plugin-quality:audit` and `claude-ops:plugins audit` |

Recommendation: run `/naming:name-it-better` with these four as the collision vocabulary, leaning
toward `audit-plugin-conformance`; if chosen, T7's rewrites say "plugin conformance audit". A later
`realign` sibling (verb table `:136-145`) is out of scope. Unblocks: the skill directory, T7 wording.

**Decision (user, 2026-09-27): `audit-plugin-conformance`.** `/naming:name-it-better` ran three blind
generators (responsibility-literal, moment-of-use, domain-lore) on a brief without the candidates.
All three proposed `audit-plugin-conformance`; all three ranked the shorter `audit-conformance` and
`audit-doctrine` first. Neither shorter form beats it strongly enough to override the lean:

- Scope fit: a repo-local skill has no plugin namespace, and the naming rule says the namespace
  supplies the object (`:120`). Without "plugin" in the name, nothing says what conforms.
  `audit-conformance` could read as code, spec or security conformance.
- Semantic accuracy: "conformance" is the standards term of art for meeting a normative
  specification, which the philosophy doc is. "Doctrine" is used informally in the doc
  ("house doctrine") but is not its title, so `audit-doctrine` names the target less exactly.
- Other generated names dropped: `scan-conformance` (both verbs are read-only; `audit` matches the
  sibling audits), `audit-marketplace-conformance` (longer, and no clearer), and the "fleet" names
  (the word already means repos and machines here).

T7's rewrites say "plugin conformance audit".

### T9. Concern registry: home and row shape

Options for the home:

- **A. A doc under `docs/`**, e.g. `docs/conformance-dimensions.md`, a markdown table.
- **B. A data file inside the skill directory.**
- **C. Extend the philosophy's own Convention registry table** (`:684-`).

Recommendation: **A**. Philosophy sections and convention docs will cite it (T7), and citing a file
inside a skill's directory is the encapsulation breach `docs/plugin-philosophy.md:431-433` bars (`docs/**` cites skills by slash invocation, never by path), which
rules out B. C mixes "who owns a convention" with "what checks it". Row shape in
`library-topology.md`. Ids keep the existing informal numbers where they exist (dim-8 setup wave,
dim-9 visible skip, dim-11 seam phrasing, per `hook-observability/README.md:56-59`) and number the
rest after them. A script (T13) fails when a row names a check that does not exist. Unblocks: T7,
the skill body.

**Decision (user, 2026-09-27): A,** at `docs/conformance-dimensions.md`. Rationale as above: docs and
conventions can cite it without reaching into a skill directory.

### T10. Verb-name check: gate or advisory

Today every check passes noun skills such as `pixel-art`'s `scene` and `sprite`, which no noun exception
at `:150-176` covers.

- **A. CI gate with a baseline file** of current offenders (the `skill-description-cap-baseline.txt`
  ratchet pattern): new offenders fail, old ones are listed for T11.
- **B. Advisory only**, reported by the skill.
- **C. Gate with no baseline**, which fails CI until every offender is renamed or excepted.

Recommendation: **A**. It stops new drift at once without forcing renames into this branch. Note:
`feat/pixel-art` (#4407) would land `scene` and `sprite` as new offenders unless it renames them or
merges first and gets baselined. Unblocks: T13's CI wiring.

**Decision (user, 2026-09-27): A,** a CI gate with a baseline of current offenders. Rationale: stops
new noun leaves now; existing ones become T11 item 5 instead of blocking this branch.

### T11. Follow-up issue list

From capability-matrix "Existing duplication found" and concern tables:

1. Align the two token stacks: `org-agnosticism-tokens.txt` and `skill-portability-tokens.txt`
   (`docs/plugin-philosophy.md:90-92` already requires alignment).
2. Hardcoded consumer specifics judged in three places (`plugin-quality` recurring-concerns section 5,
   `coupling:reduce` remediations, `audit-permission-grants`) with no cross-citation: name one owner,
   the others route to it.
3. `plugin-quality` recurring-concerns section 4 restates SSOT doctrine instead of routing to
   `/docs-hygiene:extract-ssot`.
4. `scripts/check-plugin-catalog-enablement.sh:67` fetches a hardcoded standards-repo URL (a concern-5
   instance).
5. Noun skill leaves (`pixel-art` `scene`, `sprite`, plus whatever T13's verb script lists at
   baseline time): rename or add an exception.
6. `skill-quality` check 25 (verb contract) is WARN-only and runs on changed skills only.

Items 4 and 5 of the matrix's list (listing budget three ways, two grouping axes) are deliberate and
cite each other; not filed. Recommendation: file 1-4 and 6 now; file 5 after the verb script's
baseline run so the list is complete. Unblocks: nothing in this design; keeps T4's promise.

**Decision (user, 2026-09-27): file 1-4 and 6 now; 5 waits for the baseline run.** No open duplicate
was found before filing. Filed: 1 = #4582, 2 = #4583, 3 = #4584, 4 = #4585, 6 = #4586. Item 5 is filed
by the build phase that produces the verb baseline.

## Resolved (user agreed the recommended direction, 2026-09-27; details for `/planning:plan`)

### T12. Remaining philosophy rule: dependency inventory classes

Concerns 4 and 6 now have rules. Concern 5's inventory classes (external binaries and versions,
network ports, sizes and resolutions, other plugins' layouts, installed browsers, PATH lookups) and
their verdict set (port, `userConfig`, presence-gated, documented, fix needed) are not in the
philosophy. Direction: add them as a short list under "Prerequisites and failure behavior" (`:660-`),
reusing that section's absence classes, as the first commit of the build. No new token file
(`:90-92`).

Rationale: T2 puts the rule before the check; the dependency script (T13) needs a rule to cite, and
that section already owns what happens when a prerequisite is absent.

### T13. Script shape and CI wiring

- Verb grammar: **extend** `scripts/check-skill-leaf-names.sh` with a verb list and exception list in
  one data file beside `skill-leaf-name-registry.txt`, plus the T10 baseline.
- Dependency inventory and repeated literals: **new** scripts in `scripts/`, each taking a plugin
  path, printing a candidate list (TSV or JSON), exit 0. They list; they do not gate.
- Registry integrity: a check that every T9 row's named check exists; wire into
  `scripts/validate-plugins.sh`.
- Suppressions reuse the marketplace finding-suppression convention already used by
  `.claude/audit-pass.md`, not a new store.

Rationale: extending the leaf-name script keeps one owner for leaf-name rules; the two new scripts
only list because their verdicts are judgment (T3); reusing the suppression convention avoids a
second store.

Addendum (plan review, 2026-09-27): PLAN.md proposes standalone `ci.yml` steps for the registry check
instead of `scripts/validate-plugins.sh`, which needs `claude` and `node` on PATH. Approved by the
user 2026-09-27.

### T14. Target scope, fan-out and findings persistence

Direction: argument is one plugin (default: plugins touched on the branch), or `all`. `all` runs the
deterministic scripts once over the tree, then one judgment subagent per plugin, piloting one plugin
before fanning out. Findings persist per plugin and lane so an interrupted run resumes, the
`claude-config:audit-pass` shape, written to the memory tier, not tracked. Read-only; no `--fix`.

Rationale: an `audit` verb is read-only (`:140`); the pilot guards against a usage limit stopping a
wide fan-out mid-run; reusing `audit-pass`'s resume shape avoids a second persistence scheme.

### T15. Judgment steps; positions tier deferred

Direction: the judgment steps are those the matrix's First-cut shape names: taxonomy and boundary
fit (1), a routing test in a fresh subagent given only descriptions and requests (3), a port verdict
per output and tool (4), a verdict per dependency and value (5, 6), each in a fresh context per
`docs/plugin-philosophy.md:867-` (fresh-eyes checkpoints). Existing judgment skills
(`plugin-quality:audit`, `extract-ssot`, `code-metrics:audit-duplication`, `coupling:reduce`) are
dispatched presence-gated. TAGGED-DEFERRED: the "N positions, then converge" deep tier (concern 8).
Research tag: whether a positions-then-converge pass finds boundary errors the per-concern verdicts
miss, measured on one real case. Trigger: a run where the per-concern verdicts disagree on a boundary
decision and a human asks for it.

Rationale: these are the gaps no existing check covers (capability matrix concerns 1, 3-6), and the
fresh-eyes rule bars a producing context from grading its own output.

### T16. Test-seam posture

One seam per script: sibling `scripts/<name>.test.sh` fixtures, the repo's existing pattern
(`scripts/check-changed-skills.test.sh` and peers). The skill body itself is checked by
`skill-quality:check`; no model-graded eval in the first cut.

Rationale: the scripts carry all deterministic logic, so a fixture test per script is the smallest
seam that fails when that logic breaks; a model-graded eval waits until the skill has run on real
plugins.

### T17. Sequencing against #4534

The two rules exist only on `feat/animation-plugin`. Build order: #4534 merges, this branch merges
main, then T12's rule, the T9 registry, the T13 scripts, the skill, and T7's citation rewrites in one
PR. Design work (this file) does not wait.

Rationale: the skill cites the two rules #4534 adds, and T7's rewrites must land with the skill so
no commit cites a missing audit.

## Next

`/planning:design-handoff`, then `/planning:plan` into `plugin-conformance-audit-plan.md`.
