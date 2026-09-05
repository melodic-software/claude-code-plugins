# justify

Topic slug: `justify-existence`. Branch: `claude/justify-existence-skill-interview-lsgmkq`.
Brief written by `/planning:interview` on 2026-09-05 (commit `8766f8e8`); Plan written by
`/planning:plan` on 2026-09-05. Ledgers: `.work/justify-existence/interview-checklist.md`,
`.work/justify-existence/plan-checklist.md`.

> **Scope change, 2026-09-05 (planning stage).** Four Open Decisions resolved during
> `/planning:plan` supersede parts of the Brief below. Superseded lines are struck through and
> point here; nothing is deleted, so the interview's reasoning stays readable.
>
> - **OD1.** The deliverable is a third lane skill **inside `plugins/overengineering/`**, not a
>   new plugin. Basis: `docs/adr/0017-ship-the-product-code-lane-as-its-own-skill.md` decides that
>   lanes of the scrutiny method ship as sibling skills composing `audit` ("two lanes, two skills,
>   and this makes three"); the interview's Q6 premise that the plugin was enforcement-scoped was
>   wrong, only the `audit` skill is. Supersedes Q6, Q10, Q11, Q13.
> - **OD2.** Leaf name `justify`; handle **`/overengineering:justify <target>`**.
> - **OD3.** Design gate early-exit, operator accepted; artifact at `design/design-resolution.md`.
> - **OD4.** The shared findings artifact is extended: five non-enforcement `Layer` values, a new
>   non-spine `Basis` field, `schema` 1 to 2, with `realign` and `delta` taught to accept schema 2.
>   Supersedes Q14 (no vendoring, no registry entry, no drift gate; intra-plugin citation is legal
>   under ADR 0018 clause 1).
> - **Correction.** Captured assumption 2 was wrong about `overengineering`: its artifact is
>   deliberately **not** `type: review-findings` (consent-gated per item). This skill inherits
>   that, so findings never route through the fix relay.
>
> **Second amendment, 2026-09-05 (after the Step 3 plan review).** The fresh-context reviewer
> verified three contract facts the draft missed: the artifact's merge rule 3 closes any prior
> finding whose layer was walked and whose id is absent, so a pointed-target run needs a
> **targeted run mode** (`mode: targeted`, `targets:`) in the same schema bump; finding ids
> hardcode the `audit` producer and a closed kind-prefix set, so the lane gets its own `check` and
> `claim` forms and a `package:` prefix; and a routed enforcement-kind target has no legal spine,
> so **routing writes no artifact row**.
>
> **Third amendment, 2026-09-05 (after the Step 4 formal stress-test).** Three more contract
> facts, verified, and two operator decisions:
>
> - **OD5.** V1 targets are a path, `path#heading`, or a kind-prefixed identifier. A line or
>   comment target **widens to its enclosing heading or file, and the report's first line says
>   so**. Basis: the id contract forbids positional anchors (`findings-artifact.md`, "Finding
>   ids": "Never a positional ordinal"). Narrows Q2 for V1 only; the Brief's TLDR is amended.
> - **OD1, re-confirmed with a smaller benefit.** `realign` **presents** this lane's findings
>   but **never executes** them: its only ladder is the enforcement one, and ADR 0017 states that
>   a product-code ladder must exist before `realign` can execute a new lane's findings. `delta`
>   **never compares** them: it composes `audit`, which walks only the ten enforcement layers.
>   Both are recorded as chosen limits. The other grounds for OD1 hold.
> - The targeted-run clause must also scope the artifact's four single-valued run-level sections
>   (`Evidence availability`, `Summary`, `Suppressed`, `Closed since last run`) and suppression
>   dispositions to `targets`, and `Basis` is required only on rows a schema-2 run writes, so
>   carried-forward schema-1 rows stay legal.
> - The sanctioning-record probe moves into `surface-walk.md` "Preflight" (lane-independent),
>   because the canonical vendored-copies case routes to `audit` under layer 6.
> - `Basis` is citation-based: `measured` needs a tier 1-4 citation; `class-inferred` rests on
>   §6's oracle clause or a §7 class with a silent or tier-5-only consult; `unexamined` is legal
>   only with UNPROVEN.

## Brief

### TLDR

- ~~New single-skill plugin **`justification`**, category `quality`, handle **`/justification:audit <target>`**.~~ Superseded by OD1/OD2: **third lane skill `justify` inside `overengineering`, handle `/overengineering:justify <target>`.**
- Points at any artifact ~~at any granularity (repo, folder, file, CI pipeline, feature or design, ADR, comment, one line)~~ (third amendment, OD5: a repo, folder, file, `path#heading`, or kind-prefixed identifier; a line or comment target widens to its enclosing heading or file and the report says so) and asks: was there a stated reason for this, and is that reason still valid today?
- Read-only. Reports first, then discusses with the operator; hands the discussion to `/planning:interview` when it needs structure. Never applies a remedy; remedies route to the skills that already own them.
- Verdicts use the `overengineering` §6 ladder verbatim (KEEP / RETIRE / DOWNGRADE / CONSOLIDATE / UNPROVEN, FLAG-FOR-HUMAN cap) plus one delta: every row carries an evidentiary-basis tag (`measured` / `class-inferred` / `unexamined`), citation-based per the third amendment.
- Evidence is tiered and auto-escalating (git, then forge, then consumer-specific sources); unreachable tiers are named in the verdict, never silently skipped; when not sure, it asks the operator for external context.

### Goal

Give the operator a pointed, portable instrument that makes any artifact justify its existence against the two-part test the operator stated: a reason existed when it was built, and that reason still holds today. The failure it exists to reverse is accreted output approved as a wall of text and now carried at cost (the operator's term: AI slop). The outcome is a report the operator can act on with confidence, where a retirement claim has paid for itself with evidence and a retention claim is visibly labelled by how much evidence actually supports it. The remedy is refactor or remove, decided by the operator after discussion; the skill's job ends at the report and the conversation it opens.

### Constraints

- ~~**ADR 0018 clause 2.** No cross-plugin path citation into `overengineering`'s private files. The shared scrutiny method is vendored into `plugins/justification/` and registered in `scripts/cross-plugin-source-registry.txt` so `check-cross-plugin-source-drift.sh --check` gates drift (ADR 0019).~~ Superseded by OD1: the skill lives inside `overengineering`, so the method is cited intra-plugin via `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` (ADR 0018 clause 1). Nothing is vendored. Section pointers are the file path plus the section's prose title, never `#anchors` (ADR 0018 clause 4). Cross-skill pointers use the `${CLAUDE_PLUGIN_ROOT}/skills/audit/<path>` form so `check-skill.sh` resolves them.
- ~~**Enforcement-layer targets route, presence-gated.**~~ Superseded by OD1 and the second amendment: a target whose **whole** content an enforcement layer's discovery probe inventories routes to the sibling `/overengineering:audit` and **writes no artifact row**; a target only **partly** inventoried (a skill file, an instruction file with imports) is classified under a lane layer with the routed part named in the row. No presence gate is needed inside one plugin.
- **Two gates, reported separately.** The ablation rubric (`docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook", durable tier exempt) and the ADR 0003 precision bar (no class exemption) are independent. A verdict row states which gate it answers. A fused verdict is a defect. On the lane's own five layers the ablation gate is **not applicable** and the row says so; it applies only to the enforcement kinds this lane routes.
- **Retire costs more than keep.** A RETIRE row names where the search looked and what a counterexample would look like, and is refused when the search was a single document or a single query form.
- **Absence checks vary the query form** (line wrap, hyphenation, casing, synonyms) before "not found" becomes a finding. A single-form grep is not a search.
- **Check for a sanctioning record and a maintaining gate before calling any pattern debt.** The canonical negative case is `lib/hook-utils.sh`: 17 byte-identical copies sanctioned by ADR 0019 and actively maintained by a CI drift gate. Third amendment: those copies live under `plugins/*/hooks/` and route to `audit` under layer 6, so the probe lives in `surface-walk.md` "Preflight" where both lanes run it; the shipped docs describe the pattern generically and this repo's specifics stay in this Brief and in eval fixtures.
- **`realign` presents, never executes, this lane's findings** (third amendment). Its only ladder is the enforcement one; ADR 0017 requires a per-layer ladder before `realign` can execute a new lane's findings. A `justify`-producer row in the queue is displayed with its owner from the Boundary table and no rung is offered.
- **Read-only on the target.** The only write is the findings artifact at the memory-tier home `overengineering` already resolves, in `mode: targeted`; never to the audited artifact. The artifact is `type: overengineering-findings` and is never `type: review-findings`. Every writer re-reads the on-disk artifact immediately before writing and merges against that copy.
- **No repo-wide sweep.** A bare invocation follows the fallback ladder in the acceptance criteria; it never enumerates the repository.
- **Portable.** Satisfies `docs/PLUGIN-PHILOSOPHY.md` "Design boundary": no dependence on this organization's paths, names, forge, or MCP servers, and no `docs/**` path of this repository cited from shipped files. Consumer-specific evidence tiers are discovered from the consumer's own CLAUDE.md, installed MCP servers, and tool search.
- **One skill.** The no-target discovery behaviour is a mode of `justify`, not a sibling. Listing entry must survive `skill-quality:check listing-budget`.
- **House prose style.** No em dashes in SKILL.md, README, or plugin manifests; `/ai-slop:audit` clean on created files and added lines.
- **Repo process.** `scripts/affected-tests.sh --run` before push; PR opened as draft; PR body satisfies `.claude/rules/pr-body-contract.md`; announce to the sibling sessions before opening the PR (essentials inlined in Phase 6); read `.claude/rules/catalog-taxonomy.md` before touching `marketplace.json`.
- **Files this lane does not touch:** `docs/PLUGIN-PHILOSOPHY.md`, `lib/hook-utils.sh` and its copies, `plugins/*/hooks/**`, `docs/conventions/hook-*`, `scripts/check-*.sh`, `docs/adr/**` without prior announcement.

### Acceptance criteria

- ~~`plugins/justification/` exists with `.claude-plugin/plugin.json`, `skills/audit/SKILL.md`, `README.md`, `CHANGELOG.md`, and `skills/audit/evals/evals.json`; `.claude-plugin/marketplace.json` carries the entry with `"category": "quality"`; `docs/CATALOG.md` is regenerated.~~ Superseded by OD1: `plugins/overengineering/skills/justify/SKILL.md` and `skills/justify/evals/evals.json` exist; `plugins/overengineering/context/justification-lane.md` exists; `plugin.json` version is bumped with a matching `CHANGELOG.md` entry; `README.md` lists the fourth skill; `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` are regenerated with the repo's own tooling.
- ~~`skill-quality:check justification` passes~~ `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/overengineering/skills" bash plugins/skill-quality/scripts/check-skill.sh justify` reports PASS; `check-listing-budget.sh` does not regress against the baseline captured in Phase 3.
- `/overengineering:justify <target>` on a path, `path#heading`, or kind-prefixed identifier produces a report in which every verdict row carries: one of the six §6 tokens; a `Basis` value (`measured` = at least one tier 1-4 citation supports the verdict; `class-inferred` = the verdict rests on §6's non-derivable-oracle clause or a §7 class match and any consult was silent or tier-5-only; `unexamined` = no tier consulted, legal only with `Verdict: UNPROVEN`); the evidence tiers consulted with each marked silent or unavailable when it returned nothing; `ablation: n/a` on the lane's layers; and, for RETIRE, the search locations and the counterexample shape. A line or comment target is widened to its enclosing heading or file and the report's first line states the widening (third amendment, OD5).
- `/overengineering:justify` with no target does not sweep. It uses conversation context if any exists and confirms the inferred target in one line before walking; otherwise offers git-history discovery of old, low-churn candidates; otherwise asks the operator. The chosen rung is stated in the output.
- ~~An enforcement-kind target produces a finding whose `Routed-to` names `/overengineering:audit`.~~ Second and third amendments: a target whose whole content an enforcement probe inventories produces **no artifact row**; the inline report names `/overengineering:audit` and the layer that claimed it. A partly inventoried target is classified under a lane layer with the routed part named in the row.
- ~~The vendored method file is listed in `scripts/cross-plugin-source-registry.txt`.~~ Superseded: `findings-artifact.md` declares `schema: 2`; its `Layer` enum carries the five new values; its per-finding table carries `Basis` (required on rows a schema-2 run writes); its frontmatter carries `mode` and `targets`; its merge rules carry the targeted-run clause scoping rules 1-3, the four run-level sections, and suppression dispositions to `targets`; its finding-id table carries the `justify` producer's `check` and `claim` and the `package:` prefix; `realign`, `delta`, and `audit` each state they accept schema 2; `realign` presents and never executes a `justify`-producer row; `delta` states it never compares this lane's findings and distinguishes "not walkable by `audit`" from "not walked this run".
- SKILL.md carries a Boundary section naming, by slash handle, the incumbents it defers to: `overengineering:audit`, `code-tidying:audit-dead-code`, `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue`, `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise`, `claude-config:audit-instructions`, `claude-config:unhobble`, `claude-ops:audit-native-overlap`, `improvement:find`; and the scrutiny pairing `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast`.
- `evals/evals.json` includes at least these cases: (a) a sanctioned, gate-maintained byte-identical copy set is NOT reported as debt; (b) a manifest of hook-bearing plugins where most ship hooks plus their own setup skill is NOT reported as one violation per plugin; (c) a RETIRE row without named search locations is rejected; (d) a class claim offered as the verdict is recorded as `class-inferred` with a separately labelled earned-keep answer, on a `documents` fixture; (e) a bare invocation does not enumerate the repository; (f) a hooks manifest and a rules file each route with no row; (g) a skill file is classified under `components` with its always-loaded part named as routed; (h) a line target widens and the first report line says so; (i) "I don't know" yields UNPROVEN. `skills/realign/evals/evals.json` gains a case: a `justify`-producer row is presented and no rung is offered.
- When the operator's answer to an evidence-tier question is "I don't know", the item is recorded UNPROVEN with the tier named, not resolved either way.

### Captured assumptions

- The operator's phrase "don't make videos" was a dictation slip for: do not conclude an artifact is unjustified merely because its justification is not in the repository. Revisit if the operator corrects the reading.
- ~~Findings conform to the repo's detector-findings convention, as `provenance` and `overengineering` already do.~~ Corrected 2026-09-05: findings are `type: overengineering-findings` per `plugins/overengineering/context/findings-artifact.md`, which deliberately refuses the fix relay. The inline report comes first per the operator's Q8 answer.
- ADR 0003's precision bar governs the no-target discovery mode, because that mode emits candidates over a corpus. Discovery mode ships only after a check on this repository reports its candidate count and how many the operator confirmed as real (Phase 4 measures it and records the numbers in this file and in the PR body). Revisit if discovery mode is cut from V1.
- The `overengineering` §6 ladder tokens are stable enough to adopt verbatim. Revisit if `overengineering` changes its ladder; inside one plugin that change and this lane move together.
- V1 is attended-only, derived from the operator's answers to Q7 ("if not 100% sure, ask") and Q8 ("report first, then discuss"). See Q15.
- ~~`justification` is the plugin name.~~ Superseded by OD1/OD2: the handle is `/overengineering:justify <target>`. Revisit if it reads wrongly in use.
- `Basis` is outside the spine, so `delta` cannot report a `Basis` move. Chosen, not discovered: the spine stays closed so the diff stays meaningful. Moot in V1 since `delta` never compares this lane's findings at all; revisit if `delta` gains a pass-through for `justify`.
- `realign` is display-only for this lane until a per-layer rollback ladder exists (ADR 0017's own deferred work). Revisit when that ladder lands.

### Out-of-scope

- Applying any refactor or removal. Remedies route to existing appliers.
- A repository-wide sweep in any mode.
- An unattended or dispatched run mode (deferred, Q15).
- A pre-creation corrector ("before you add that, justify it"). That is a different skill wearing the same name; if wanted later it is a `discipline` corrector.
- Comment-specific logic and `path:line` targets (third amendment, OD5). `code-tidying:dissolve-comments` and `audit-comment-residue` own comments; a line target widens.
- A per-layer `realign` rollback ladder for this lane's layers (ADR 0017's deferred work).
- A `delta` pass-through for targeted runs.
- Editing `docs/PLUGIN-PHILOSOPHY.md` or writing a new ADR in this lane without prior announcement to the sibling sessions.
- ADR 0017's extraction of `surface-walk.md`'s lane-independent parts to the plugin root, beyond the one preflight probe this plan adds there. This lane points at the enforcement lane's copy intra-plugin, exactly as `product-code-lane.md` does during the transition.

### Deferred questions

- Q15: Should `/overengineering:justify` support an unattended or dispatched run mode (recording UNPROVEN and OPEN-INTENT instead of asking)? Defer until V1 has shipped and been used attended at least once. **Arbiter: USER-RESERVED** (an unattended mode changes the acceptance criteria above; `/planning:plan` proposes, the operator resolves).

## Plan

### Goal

**What**: Add a third lane skill, `justify`, to `plugins/overengineering/`, binding the existing scrutiny method to a lane whose item is whatever artifact the operator points at, and extend the shared findings artifact (schema 2) so the lane's verdicts land in the same file and suppression record, without a pointed run ever closing, rewriting, or re-disposing what it did not examine.
**Why**: The operator's two-part test (a reason existed; it still holds) is exactly what the method's §4 intent reconstruction and §5 rediscovery compute. Nothing in the fleet applies it to non-enforcement artifacts, and ADR 0017 fixes the shape a new lane takes.

### Standards grounding

Resolution ladder rungs 1-3 absent (no `.claude/standards.yaml`, no `docs/standards/`); rung 4 inferred from repository context. Persist-offer made to the operator on 2026-09-05, not acted on.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/PLUGIN-PHILOSOPHY.md` | Design boundary; Native-first; Instruction economy; Fresh-eyes checkpoints; "one mechanism per concern" (line 714) | team (inferred) |
| `docs/adr/0017-ship-the-product-code-lane-as-its-own-skill.md` | Decision; Consequences (the `realign` ladder prerequisite) | team |
| `docs/adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md` | Decision clauses 1-4 | team |
| `docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md` | Decision clauses 1-5 | team |
| `plugins/overengineering/context/scrutiny-method.md` | Lane binding; §2, §4, §5, §6, §7 | team (plugin-internal contract) |
| `plugins/overengineering/context/findings-artifact.md` | Frontmatter; Layer vocabulary; Per-finding fields; The stable spine / free prose split; Finding ids; Re-run merge semantics; Ordering; Evidence availability; Suppressed; Closed since last run | team (plugin-internal contract) |
| `plugins/overengineering/skills/audit/context/surface-walk.md` | Preflight; The per-layer loop; Granularity; Layer 1 through Layer 10 probes | team (plugin-internal) |
| `plugins/overengineering/skills/realign/SKILL.md` | Arguments; Execution order, the rollback ladder | team (plugin-internal) |
| `plugins/overengineering/skills/delta/SKILL.md`, `context/run-states.md` | The run; Layers that were not walked | team (plugin-internal) |
| `docs/conventions/finding-suppression/README.md` | id derivation; obligation 3 (dispositions) | team |
| `docs/CATALOG-TAXONOMY.md`; `.claude/rules/catalog-taxonomy.md` | Form rule; Assignment principle | team |
| `.claude/rules/vendor-docs-are-not-style.md`, `.claude/rules/pr-body-contract.md` | whole | team (ambient, cited for completeness) |

### Approach

Build technique: **tracer bullet** on the kept slice. No viability unknown (the method exists and has two lanes); the risk is integration, so the thinnest working `justify` SKILL.md runs end-to-end on one real target before any polish. Contract changes land first so the lane doc and skill body cite fields that exist. Evals precede the skill body they grade (test-first; the eval is the skill's observable-behavior spec, per `/tdd:principles` "Test before or after? Before" and "Output-based first").

Order: contract migration (1) → lane binding doc (2) → evals, red, plus the listing-budget baseline (3) → SKILL.md thin slice, live tracer run, discovery measurement, green (4) → plugin surfaces (5) → gate sweep and PR (6).

Conventions in every Sanity Check: run from the repository root; every command is verbatim-executable; `grep -E` wherever alternation appears, so nothing depends on GNU-only `\|` or `\+`. Counting checks use `test "$(grep -c …)" -eq N` because `grep -c` exits 1 on a zero count and cannot be chained with `&&` on its own.

### Phase 1: Extend the shared findings artifact to schema 2 [DONE]

**Executed 2026-09-05.** Pre-flight confirmed: no script parses the artifact; the only non-markdown
hits are `evals/evals.json` files. All Sanity Checks green. One real gap the phase's own checks
caught and fixed: `audit` merges into a prior artifact per layer, so it needed a schema-acceptance
sentence of its own, not only the "writes schema 2" sentence the plan listed. Two Sanity Checks were
corrected in place (em-dash scope, and whitespace normalization before matching); both corrections
carry their reasons inline below.

Contract migration. The pre-flight consumer check is the first work item.

- [ ] **Pre-flight (FIRST):** confirm no script parses the artifact. Expected today: the only non-markdown hit is `plugins/overengineering/skills/realign/evals/evals.json`, an eval mention. Consumers are the prose skills `realign`, `delta`, and `audit`. Record the result in this phase's notes. (After Phase 3, `justify/evals/evals.json` also matches; the check is "every hit is an `evals.json`".)
- [ ] `context/findings-artifact.md` "Frontmatter": `schema` row reads "currently `2`"; keep the stop-on-unrecognized rule. Add `mode` (required; `walk` or `targeted`; `audit` writes `walk`) and `targets` (required when `mode: targeted`; the list of item identifiers examined this run, each a repo-relative path, `path#heading`, or kind-prefixed identifier). A `walk` run omits `targets`.
- [ ] `context/findings-artifact.md` "Re-run merge semantics": add the **targeted-run clause** ahead of rule 3. In a `targeted` run: rules 1 and 2 apply to ids whose sites are all in `targets`; rule 3 applies **only** to a prior id whose every site is in `targets` and whose item is now absent; every other prior id carries forward per rule 4 regardless of `scope`. `scope` lists the layers of the targets for ordering only and asserts no exhaustive walk. The run-level sections `## Evidence availability`, `## Suppressed`, and `## Closed since last run` are **not rewritten** for ids outside `targets`; the targeted run appends a per-target evidence-availability block and records dispositions only for suppression entries whose ids have sites in `targets`, reporting all other entries as "not evaluated this run". `## Summary` is recomputed from the spine as rule 6 already requires.
- [ ] `context/findings-artifact.md` "Layer vocabulary": append `decision-records` · `documents` · `components` · `dependencies` · `source` after `external-integrations` (the enum wraps across lines in the source; keep the wrap), keeping the "eleventh layer means a schema bump" sentence and stating these five are the justification lane's and never inventory an enforcement kind.
- [ ] `context/findings-artifact.md` "Per-finding fields": add row `Basis` | Spine: no | Required: on every row written or rewritten by a schema-2 run | one of `measured` (at least one tier 1-4 citation supports the verdict), `class-inferred` (the verdict rests on §6's non-derivable-oracle clause or a §7 class match, and any consult was silent or tier-5-only; a `class-inferred` KEEP requires the oracle itself to be cited, which makes it `measured`), `unexamined` (no tier consulted; legal only with `Verdict: UNPROVEN`). A carried-forward schema-1 row carries no `Basis` until re-evaluated, and consumers display "not recorded (schema 1)".
- [ ] `context/findings-artifact.md` "Finding ids": generalize the `check` row to `overengineering/<producer>/rule-<layer>` with `<producer>` one of `audit`, `justify`; add `claim = artifact-item` (and `artifact-item(member=<name>)`) for the `justify` producer beside `enforcement-item`; add `package:<name>` to the kind-prefix set for the `dependencies` layer. State that a routed target produces no id and no row, and that the anchor for a `path#heading` target is `[<file>, <heading>]`.
- [ ] `skills/realign/SKILL.md`: accept `schema` `1` or `2`; on `2`, display `Basis`, `mode`, and `targets` with the finding. **A row whose `check` producer is `justify` is presented with its owner from the lane's Boundary table and no rung is offered**; the rollback ladder is enforcement-shaped and ADR 0017 requires a per-layer ladder first.
- [ ] `skills/realign/evals/evals.json`: one case, `justify-producer-row-is-presented-never-executed`, on a fixture artifact carrying one `overengineering/justify/rule-documents` row; expects display with the owner named and no rung.
- [ ] `skills/delta/SKILL.md` and `skills/delta/context/baseline-model.md`, `context/run-states.md`: accept schema `1` or `2`; `Basis` is prose outside the spine and never enters the diff; **`delta` never compares this lane's findings** because it composes `audit`, whose `scope` names only the ten enforcement layers; the coverage line distinguishes "not walkable by `audit`" (the five justify layers, with their finding count) from "not walked this run"; an intervening `targeted` run is **not** an evidence-availability move.
- [ ] `skills/audit/SKILL.md`: one sentence that the enforcement lane writes `schema: 2`, `mode: walk`, and sets `Basis` per the definitions above.
- [ ] `skills/audit/context/surface-walk.md` "Preflight": add the **sanctioning-record probe**, stated generically: a decision record, convention doc, or registry that sanctions a pattern, plus a gate that maintains it; a sanctioned and gated pattern is never CONSOLIDATE or RETIRE on the grounds of duplication alone. Lane-independent; both lanes run it.

**File inventory (Phase 1):**

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/overengineering/context/findings-artifact.md` | MODIFY | enum, `Basis`, `mode`/`targets`, targeted clause, id forms, `schema: 2` |
| [ ] `plugins/overengineering/skills/realign/SKILL.md` | MODIFY | accept schema 2; present-only for `justify` rows |
| [ ] `plugins/overengineering/skills/realign/evals/evals.json` | MODIFY | one new case |
| [ ] `plugins/overengineering/skills/delta/SKILL.md` | MODIFY | accept schema 2; never compares this lane; coverage wording |
| [ ] `plugins/overengineering/skills/delta/context/baseline-model.md` | MODIFY | `Basis` outside the spine |
| [ ] `plugins/overengineering/skills/delta/context/run-states.md` | MODIFY | "not walkable by audit" vs "not walked"; targeted run is not a move |
| [ ] `plugins/overengineering/skills/audit/SKILL.md` | MODIFY | writes schema 2, `mode: walk`, `Basis` |
| [ ] `plugins/overengineering/skills/audit/context/surface-walk.md` | MODIFY | sanctioning-record probe in Preflight |
| [ ] `plugins/overengineering/context/product-code-lane.md` | KEEP | its layer set is a specification ahead of its skill; not this lane's to change |

**Sanity Check:**

- `grep -rlE 'overengineering-findings' plugins/ scripts/ --include='*.sh' --include='*.mjs' --include='*.py' --include='*.json' | grep -vE '/evals/evals\.json$'` prints nothing.
- `test "$(grep -cE 'currently \`2\`' plugins/overengineering/context/findings-artifact.md)" -eq 1 && echo OK` prints `OK`.
- `test "$(grep -cE '\`(decision-records|documents|components|dependencies|source)\` ·' plugins/overengineering/context/findings-artifact.md)" -ge 1 && test "$(grep -cE '\`source\`' plugins/overengineering/context/findings-artifact.md)" -ge 1 && echo OK` prints `OK`.
- `test "$(grep -cE '^\| \`(Basis|mode|targets)\`' plugins/overengineering/context/findings-artifact.md)" -eq 3 && echo OK` prints `OK`.
- `test "$(grep -cE 'overengineering/<producer>/rule-<layer>|artifact-item|package:<name>' plugins/overengineering/context/findings-artifact.md)" -ge 3 && echo OK` prints `OK`.
- `test "$(grep -cE 'not rewritten|not evaluated this run' plugins/overengineering/context/findings-artifact.md)" -ge 2 && echo OK` prints `OK` (the targeted clause scopes the run-level sections and dispositions).
- For each of `plugins/overengineering/skills/{realign,delta,audit}/SKILL.md`, normalize whitespace and then match. The command is fenced rather than inline because the repo's markdown formatter strips the space after an inline code span, which silently broke this very check twice:

  ```bash
  for x in realign delta audit; do
    tr '\n' ' ' < "plugins/overengineering/skills/$x/SKILL.md" | tr -s ' ' \
      | grep -qE '`(schema: )?1` and `(schema: )?2` are both recognized' \
      && echo "$x OK" || echo "$x FAIL"
  done
  ```

 **Normalize before matching; do not tighten the regex** (corrected twice on 2026-09-05 during Phase 1). A single-line `grep` reported the phrase absent in `realign`, where it wraps across a line break. A wrap-tolerant `grep -Pz` still reported it absent in `delta`, where the wrap falls mid-phrase, and in `audit`, which says `schema: 1` rather than `1`. All three texts were correct on every run. This is the lane's own absence rule landing three times on its own check, and it is the concrete reason the lane requires varying the query form before "not found" becomes a finding.

- `grep -qE 'no rung' plugins/overengineering/skills/realign/SKILL.md && echo OK` prints `OK`; `jq -e '[.evals[].name] | index("justify-producer-row-is-presented-never-executed")' plugins/overengineering/skills/realign/evals/evals.json` exit 0.
- `grep -qE 'not walkable by' plugins/overengineering/skills/delta/context/run-states.md && echo OK` prints `OK`.
- `grep -qiE 'sanctioning' plugins/overengineering/skills/audit/context/surface-walk.md && echo OK` prints `OK`.
- `bash scripts/check-purged-em-dashes.sh --check` exit 0. **Corrected 2026-09-05 during Phase 1**, from "no em dash on any added line under `plugins/overengineering`". That check was stricter than the repository's own rule and would have failed correct work: `scripts/em-dash-purged-paths.txt` covers `plugins/overengineering/README.md` and `plugins/overengineering/skills/*/SKILL.md` only, `.claude/rules/vendor-docs-are-not-style.md` binds instruction surfaces (SKILL.md, plugin READMEs, AGENTS.md, CLAUDE.md, `.claude/rules/**`) and not `context/` docs, and `findings-artifact.md` already carries 63 em dashes as its established style. Editing a table row there preserves the row's existing em dash; introducing an inconsistent dash-free row would be the defect. The created files (`justification-lane.md`, `skills/justify/SKILL.md`) stay dash-free, and the new SKILL.md is covered by the purged-paths glob automatically.

### Phase 2: Lane binding doc `context/justification-lane.md` [DONE]

**Executed 2026-09-05.** All twelve sections written; every Sanity Check green except the
slash-handle check, which reports exactly one unresolved handle, `/overengineering:justify`, the
skill this document binds and which Phase 4 creates. That is an ordering artifact of the plan, not a
defect in the file: the lane doc must name its own skill, and the plan writes the doc first. **Phase
4 re-runs this check and it must then print nothing.** A second correction inherited from Phase 1
applies here too: the em-dash rule for this file is the repository's own purged-paths list, and the
file is dash-free regardless.

Mirror `context/product-code-lane.md`'s shape. Supplies the four things "Lane binding" asks for, plus this lane's rules. Lane sections are numbered `## 1.` to `## 12.` and referred to as "section N"; bare `§N` is reserved for `scrutiny-method.md`. Section pointers into sibling files are the file path plus the section's prose title, never a `#anchor` (ADR 0018 clause 4). No organization-specific path, name, count, incident, or `docs/**` reference of this repository appears in this file; concrete cases live in eval fixtures.

- [x] Header: the method is not restated; this document supplies only the lane's four things; status **shipping**.
- [x] Section 1, **routing precedence, stated first**: if an enforcement layer's discovery probe (`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`, "Layer 1" through "Layer 10") would inventory the target's **whole** content, the target routes to `/overengineering:audit`, **no row is written**, and the inline report names the layer. If a probe would inventory only **part** of it (a skill file whose always-loaded portion is layer 2; an instruction file that imports others), the target is classified below with the routed part named in the row and handed to `audit` in `Routed-to`. Imports are read, not inferred. Only what survives is classified.
- [x] Section 2, item inventory: the item is what the operator points at. Allowed target forms: a path, `path#heading`, a kind-prefixed identifier. A line or comment target **widens** to its enclosing heading or file and the report's first line states the widening; comments are named to `code-tidying:dissolve-comments` in that line. Aggregating-container rule by pointer (`surface-walk.md`, "Granularity"): per-member sub-verdicts only where the file's structure lists members mechanically (numbered decisions, manifest entries, headings).
- [x] Section 3, layer vocabulary **by exclusion** after section 1, one subsection per layer with its discovery probes: `decision-records` (status line, date, superseding record, citing files); `documents` (prose docs that are not layer-2 instruction surfaces: inbound links, last substantive commit, generator ownership); `components` (a plugin, skill, or agent as a unit, excluding its always-loaded text and any hooks manifest: listing presence, invocation evidence where the consumer records it, catalog entry); `dependencies` (declared packages and pinned tools, identifier `package:<name>`: import or call sites, lockfile presence, upstream status); `source` (code constructs: call sites and the §3 liveness questions; **binds `${CLAUDE_PLUGIN_ROOT}/context/product-code-lane.md` "4. Protected-class defaults, extending §7" by pointer**; hand-over rule: when the product-code lane's skill ships, `source` findings close under that lane's layers in a schema bump).
- [x] Section 4, one **routing table**: target class → layer or route → row or no row. Rows for: hooks manifest (route, no row); rules or instruction file inventoried whole (route, no row); skill or agent file (classify `components`, routed part named); instruction file with imports (classify `documents`, routed part named); decision record; prose doc; package; code construct; comment (widen to file, name the owner); line (widen to heading or file).
- [x] Section 5, evidence sources on the §2 tiers: tier 1 runtime or usage records the consumer keeps; tier 2 the introducing commit, its PR and linked issue, churn, revert history (the workhorse); tier 3 incidents; tier 4 operator attestation **and** consumer-installed external context (ticketing, meeting-transcript MCP servers) recorded as attestation with date and source; tier 5 the artifact's own text, decision rationale, comments. Auto-escalation in order; every tier consulted is named silent or unavailable. **Ask-when-unsure:** when tiers 1-3 are silent and tier 4 could exist, ask before writing UNPROVEN.
- [x] Section 6, protected-class defaults extending §7: accepted decision records with citing consumers; license, security, compliance documents; anything with declared external consumers; the intentionally-dormant class carries directly; `source` adds the product-code lane's classes by pointer.
- [x] Section 7, preflight additions beyond `surface-walk.md` "Preflight": **query-form variation** for every absence claim; **retire-costs-more** (surfaces searched and counterexample shape named; a one-document search is refused); **targeted mode** always (`mode: targeted`, `targets`); **re-read before write** (load the on-disk artifact immediately before writing and merge against that copy; record its `date`). The sanctioning-record probe is inherited from the shared preflight, not restated.
- [x] Section 8, the two gates: every row answers **earned-keep**; **ablation** is `n/a (routed layers only)` on the lane's five layers. A class claim presented as the verdict is a defect: it is recorded as a protected or class marker with `Basis: class-inferred`, and the earned-keep verdict is stated separately with its own `Basis`.
- [x] Section 9, `Basis` assignment by pointer to `findings-artifact.md` "Per-finding fields", with the consequence stated: a row with no consult is UNPROVEN and `unexamined`; a KEEP is `measured` or it is not a KEEP.
- [x] Section 10, no-target ladder: conversation context, with the inferred target confirmed in one line before the walk (a compacted session's summary may name files never pointed at); else **offer** git-age discovery and wait; else ask. Never enumerate.
- [x] Section 11, boundary against existing owners (mirrors product-code-lane "6. Boundary against existing owners"): the enforcement route (section 1); instruction text → `claude-config:audit-instructions`, `claude-config:unhobble`; comments → `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue`; unreachable code → `code-tidying:audit-dead-code`; doc derivability and noise → `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise`; native duplication → `claude-ops:audit-native-overlap`; cross-dimension ranking → `improvement:find`; scrutiny pairing → `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast`. Non-sibling routes are presence-gated with the inline fallback recorded in `Routed-to`. The §10 YAGNI boundary restated: the remedy is refactor or remove, decided by the operator; the lane never proposes additions.
- [x] Section 12, known limits, each stated as chosen: `realign` presents this lane's rows and never executes them; `delta` never compares them; `Basis` moves are invisible to `delta`; two sessions writing the same artifact rely on re-read-before-write, not a lock.

**Sanity Check:**

- `test "$(grep -cE '^## [0-9]+\.' plugins/overengineering/context/justification-lane.md)" -ge 12 && echo OK` prints `OK`.
- Method references only: `comm -23 <(grep -oE '§[0-9]+' plugins/overengineering/context/justification-lane.md | tr -d '§' | sort -u) <(grep -oE '^## [0-9]+' plugins/overengineering/context/scrutiny-method.md | grep -oE '[0-9]+' | sort -u)` prints nothing; `grep -cE '§[0-9]+ (above|below)' plugins/overengineering/context/justification-lane.md` prints `0`.
- Slash handles resolve (grammar tokens like `path:line` are skipped because no `plugins/path/` exists): `grep -oE '`/?[a-z0-9-]+:[a-z0-9-]+`' plugins/overengineering/context/justification-lane.md | tr -d '`/' | sort -u | while IFS=: read -r p s; do test -d "plugins/$p" || continue; test -d "plugins/$p/skills/$s" || echo "UNRESOLVED $p:$s"; done` prints nothing.
- No anchor links: `grep -cE '\]\([^)]*#[a-z]' plugins/overengineering/context/justification-lane.md` prints `0`.
- No repo specifics: `grep -ciE 'hook-utils|adr 0019|melodic|docs/(adr|PLUGIN|conventions)|\.\./\.\./\.\./docs|17 (byte-identical )?copies|20 of 20|14 (ship|are)' plugins/overengineering/context/justification-lane.md` prints `0`.
- `markdownlint-cli2 plugins/overengineering/context/justification-lane.md` exit 0; `grep -c $'\xe2\x80\x94' plugins/overengineering/context/justification-lane.md` prints `0`.

### Phase 3: Evals first, red; listing-budget baseline [DONE]

Write the observable-behavior spec before the skill body. Fixtures are self-contained under `skills/justify/evals/fixtures/`; every fixture is named in at least one case's `files[]`, spelled `evals/fixtures/…` so both resolution roots `check-evals-quality.sh` accepts find it; shell-shaped fixtures use `.txt` so `scripts/check-shell-portability.sh` does not lint them; **no fixture is named `CLAUDE.md`**, because a nested `CLAUDE.md` loads as live instructions when a session reads files beside it (official memory docs).

- [x] Capture the listing-budget baseline before any listing entry changes, then paste its aggregate line into this phase's notes below (the memory tier is ephemeral). **The root argument is corrected on 2026-09-05.** `check-listing-budget.sh` takes *skills roots*, directories that directly contain skill directories, so `plugins/` matched nothing and the command reported "0 skills, nothing to report", a green-looking result measuring an empty set. The working form passes every plugin's skills directory:

  ```bash
  bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/*/skills \
    > .work/justify-existence/listing-budget-before.txt
  ```

- [x] `skills/justify/evals/evals.json`, `skill_name: justify`, cases (ids 1-10):
  1. `bare-invocation-does-not-sweep`: no target, no conversation context; expects the ladder stated, git-age discovery **offered** not run, no enumeration, no file written.
  2. `pointed-target-full-row`: `evals/fixtures/decision-0001.md`; expects one finding with a six-token verdict, `Basis`, tiers consulted with silent or unavailable marked, `Layer: decision-records`, `mode: targeted`, `targets` naming the fixture, `schema: 2`, `ablation: n/a`.
  3. `sanctioned-copies-are-not-debt`: `evals/fixtures/vendored/a/util.txt`, `evals/fixtures/vendored/b/util.txt` (byte-identical) plus `evals/fixtures/vendored/REGISTRY.txt` sanctioning them and naming a maintaining check; expects KEEP or UNPROVEN, never RETIRE or CONSOLIDATE, with the sanctioning record cited.
  4. `bundled-setup-skill-is-not-a-violation`: `evals/fixtures/plugins-manifest.md` describing hook-bearing plugins most of which ship hooks plus their own `setup` skill; expects the two groups separated and a one-violation-per-plugin count refused.
  5. `retire-without-search-is-refused`: `evals/fixtures/lonely-doc.md` with "I grepped once, retire it"; expects the RETIRE refused until search surfaces and query forms are named, UNPROVEN meanwhile.
  6. `class-claim-is-not-the-verdict`: `evals/fixtures/convention-doc.md` with "keep it, it is a convention doc"; expects the class recorded as a marker with `Basis: class-inferred`, and a separately labelled earned-keep verdict with its own `Basis`; a single fused row fails.
  7. `whole-inventoried-kinds-route-with-no-row`: `evals/fixtures/hooks.json` and `evals/fixtures/rules-example.md` (shaped as a rules file); expects each routed to `/overengineering:audit` naming layer 1 and layer 2, and **no artifact row**.
  8. `partly-inventoried-file-is-classified`: `evals/fixtures/SKILL.md` and `evals/fixtures/claude-md.txt` (an instruction file with an import line); expects `components` and `documents` rows respectively, each naming the routed part in `Routed-to`.
  9. `line-target-widens-and-says-so`: `evals/fixtures/lonely-doc.md:7`; expects the first report line to state the widening to the enclosing heading or file and one row for the widened item.
  10. `dont-know-is-unproven`: `evals/fixtures/decision-0001.md` with the operator answering "I don't know" to the external-context question; expects UNPROVEN with the tier named.

**Sanity Check:**

- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/overengineering/skills/justify/evals/evals.json` exit 0.
- `jq -r '.evals[].files[]' plugins/overengineering/skills/justify/evals/evals.json | sort -u | while read -r f; do test -f "plugins/overengineering/skills/justify/$f" || test -f "plugins/overengineering/skills/justify/evals/$f" || echo "MISSING $f"; done` prints nothing.
- `bash scripts/check-orphaned-fixtures.sh --check` exit 0.
- `bash scripts/check-shell-portability.sh --all` exit 0. (The `--all` flag is required; the script's usage is `<base-ref> | --all | --paths FILE...` and a bare invocation exits with usage.)
- `find plugins/overengineering/skills/justify/evals -name CLAUDE.md` prints nothing.
- `markdownlint-cli2 'plugins/overengineering/skills/justify/evals/fixtures/**/*.md'` exit 0.
- `test -s .work/justify-existence/listing-budget-before.txt && echo OK` prints `OK`, and the aggregate line is pasted into this phase's notes.
- Red: `test ! -f plugins/overengineering/skills/justify/SKILL.md && echo RED` prints `RED`.

Notes (filled at execution). Listing-budget aggregate before, captured 2026-09-05 over
`plugins/*/skills`:

```text
Shared listing-budget estimate over 182 listing-eligible skill(s) across 74 root(s):
  aggregate: 135465 chars
  budget:    8000 chars (documented default (SLASH_COMMAND_TOOL_CHAR_BUDGET fallback))
CHECK-LISTING-BUDGET: WARN — aggregate 135465/8000 chars over budget by 127465 at the configured budget.
```

The marketplace is already far past the documented default budget, so "must not regress" is read
against this 135465 number and not against the 8000 budget line: Phase 6 compares the aggregate
before and after, and the `justify` entry is expected to add roughly its own entry size. Every other
Phase 3 Sanity Check ran green, including the RED check, which is the point of the phase: the evals
exist and `skills/justify/SKILL.md` does not. Two commands were corrected as noted above. Ten
fixtures shipped, each named in at least one case's `files[]`; the two shell-shaped ones use `.txt`
and no fixture is named `CLAUDE.md`.

### Phase 4: `skills/justify/SKILL.md`, thin slice, live tracer run, discovery measurement [DONE]

Model on `skills/audit/SKILL.md`'s section order. Composes the method by pointer; restates nothing. Every pointer into a sibling skill uses `${CLAUDE_PLUGIN_ROOT}/skills/audit/<path>` plus the section's prose title.

- [x] Frontmatter: `description` under the per-entry cap, first clause naming the object ("Justify the existence of any artifact you point at…"), quoted triggers ("justify this", "does this need to exist", "why is this here", "is this still valid", "earn its keep", "justify the existence of"), the no-target behaviour, "Not for" the enforcement surface (route to `audit`) and remedies (route to owners); `argument-hint: "<path | path#heading | kind:identifier> | (none: conversation context, then offered git-age discovery, then ask)"`; `user-invocable: true`; `disable-model-invocation: false`; `shell: bash`; `metadata.workflow-stage: anytime`; `metadata.summary`.
- [x] Pre-computed context: **one** git injection line only (`#1619`): branch via `git symbolic-ref --quiet --short HEAD`.
- [x] Purpose; the method pointer (`${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md`) and the lane pointer (`${CLAUDE_PLUGIN_ROOT}/context/justification-lane.md`); Read-only contract by pointer to `${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md` "Read-only contract", stating the one write, `mode: targeted`, and re-read-before-write.
- [x] Branch identity by pointer to `${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md` "A detached checkout has no branch identity": a detached checkout writes no artifact and emits the full inline summary; the refusal line is quoted.
- [x] Arguments: the OD5 grammar (path, `path#heading`, kind-prefixed identifier); the widening rule for a line or comment target with the first-line statement; the no-target ladder per lane section 10; the discovery offer command: `git log --diff-filter=A --name-only --format='%ad' --date=short -- . | awk 'NF'` post-processed into (path, first-seen date) pairs ranked oldest first, **offered and waited on**, never run unasked.
- [x] Before the walk: `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md` "Preflight" by pointer (now including the sanctioning-record probe) plus the lane's section 7 additions and the section 1 routing test.
- [x] The walk: the per-item loop by pointer; a pointed target is one item unless the container rule splits it.
- [x] Verdicts and evidence: §6 by pointer; `Basis` and `ablation: n/a` on every row; the earned-keep gate named.
- [x] Intent checkpoints: attended only in V1; report first, then the discussion; reuse `planning:interview` mechanics when installed, inline numbered questions otherwise; "I don't know" → UNPROVEN with the tier named.
- [x] **Boundary (in SKILL.md):** the handle table from lane section 11, so the acceptance criterion holds on this file.
- [x] The report: hand off to `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/report-template.md` by pointer.
- [x] Gotchas: the absence rule with a **generic** worked example (a multi-word phrase wrapped across a line break defeats a single-line grep); the relocated-coverage case (a never-fires guard whose concern is guarded elsewhere is not unguarded). No repo-specific incident names.
- [x] **Tracer run, with the artifact protected:** resolve the artifact home the way the skill will (`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md` "Resolution"); if a `findings.md` or `spine-baseline.md` already exists there, copy both to `.work/justify-existence/tracer-backup/`. Then run `/overengineering:justify docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md` in this session. Afterwards **restore** the backed-up files if they existed, or delete the artifact only if none existed before and its frontmatter shows `mode: targeted` with the tracer's `date`.
- [x] **Discovery measurement (ADR 0003 clauses 1-2):** run the discovery probe on this repository once, record the candidate count and how many the operator confirms as real, and write both numbers into this phase's notes below and into the PR body's `## Verification`. Zero confirmed candidates cuts discovery mode from V1 and amends Brief assumption 3 (a `[FALLBACK]` gate).

**Sanity Check:**

- `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/overengineering/skills" bash plugins/skill-quality/scripts/check-skill.sh justify 2>&1 | grep -qE 'PASS' && echo OK` prints `OK`.
- `bash scripts/check-skill-precompute-compose.sh --strict --paths plugins/overengineering/skills/justify/SKILL.md` exit 0.
- `bash scripts/check-skill-portability.sh --paths plugins/overengineering/skills/justify/SKILL.md plugins/overengineering/context/justification-lane.md` exit 0.
- Slash handles resolve: `grep -oE '`/?[a-z0-9-]+:[a-z0-9-]+`' plugins/overengineering/skills/justify/SKILL.md | tr -d '`/' | sort -u | while IFS=: read -r p s; do test -d "plugins/$p" || continue; test -d "plugins/$p/skills/$s" || echo "UNRESOLVED $p:$s"; done` prints nothing.
- No anchor links: `grep -cE '\]\([^)]*#[a-z]' plugins/overengineering/skills/justify/SKILL.md` prints `0`.
- No repo specifics: `grep -ciE 'hook-utils|adr 0019|melodic|docs/(adr|PLUGIN|conventions)|one mechanism per concern' plugins/overengineering/skills/justify/SKILL.md` prints `0`.
- Tracer output contains a finding heading (`###`) followed by `**Layer:** decision-records`, `**Verdict:**` one of the six tokens, and `**Basis:**` one of the three values; its frontmatter shows `mode: targeted` and `schema: 2`.
- Artifact protected: if `.work/justify-existence/tracer-backup/findings.md` exists, `cmp -s .work/justify-existence/tracer-backup/findings.md "<resolved home>/findings.md" && echo RESTORED` prints `RESTORED`; otherwise `test ! -f "<resolved home>/findings.md" && echo CLEAN` prints `CLEAN`. The resolved home is recorded in this phase's notes.
- `git status --porcelain | grep -vE '^.. (plugins/overengineering/|docs/topics/justify-existence/)'` prints nothing.
- Discovery numbers recorded below.

Notes (filled at execution), 2026-09-05.

**Resolved artifact home:** `.work/overengineering/claude-justify-existence-skill-interview-lsgmkq/`,
reached at rung 5, the documented default. Rung 1 found no `.claude/topic-docs.yaml`; rungs 2 to 4
had nothing declared, nothing inferable (no existing `.work/overengineering/` layout), and no concern
file. No `findings.md` or `spine-baseline.md` existed there, so nothing was backed up and the CLEAN
branch of the protection check applies. The run also created the memory root's self-ignore guard,
`.work/.gitignore` containing `*`, which is one of the two sanctioned auxiliary writes.

**Tracer run:** `/overengineering:justify docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md`.
One finding, `e7cc6c5167abbd56`, `Layer: decision-records`, `Verdict: KEEP`, `Basis: measured`,
`ablation: n/a`, `Status: OPEN`, frontmatter `schema: 2` and `mode: targeted` with `targets` naming
only that file. The routing test ran first and did not fire: no enforcement probe inventories a
decision record, so the target reached a lane layer rather than routing. **The five layers and the
routing precedence held on a real target**, so neither of the two Phase 4 stop conditions was
triggered and no re-plan was needed. Evidence was tier 2: the introducing commit, a later amendment
narrowing its scope, and two live surfaces citing it as binding doctrine. The protected-class marker
and the KEEP were recorded separately, as section 8 requires. The artifact was deleted afterwards
per the protection rule, and the worktree-footprint check printed nothing.

**Discovery measurement (ADR 0003 clauses 1-2).** The probe ran once over this repository.

| Measure | Count |
|---|---|
| Distinct paths ever added that still exist | 2692 |
| Ranked candidates (first seen on or before 2026-07-31, two commits or fewer since) | 638 |
| After excluding evals, fixtures, tests, schemas, and examples | 285 |
| Markdown documents within that filtered set | 146 |
| Of those, cited nowhere outside their own directory | 3 |
| Surviving query-form variation, and confirmed real | **2** |

The two are `docs/hook-migration-audit.md` and `docs/ai-briefing-design.md`: one-off documents from
2026-07-12, never updated, with no inbound link under the filename form or the title-words form. The
third, `docs/adr/0006-...`, **is** cited, by two files, but only under the `ADR 0006` form rather than
the filename form. The lane's own query-form-variation rule caught that false positive during this
measurement, which is the most useful thing the tracer produced.

**Reading of the number, and the gate.** Age plus low churn on its own has poor precision here: 2 real
candidates out of 638 ranked ones. That is expected rather than alarming, because most of the ranked
set is fixtures, evals, and tests, whose low churn is their designed steady state and whose
inactivity therefore returns no information (§7's category error). It matters for what discovery mode
may be: as an **offer the operator chooses from**, which is what this plan specifies (offered, waited
on, never run unasked, and its output is explicitly a candidate list rather than a finding set), the
ADR 0003 precision bar for a default-on emitter does not apply. Shipping it default-on, or having it
emit findings, would not survive these numbers.

**Confirmed count is 2, not 0, so the cut gate did not fire.** Recorded honestly: the two candidates
are the implementer's verified assessment, reached mechanically and re-checked with varied query
forms, **pending the operator's confirmation**, which is the `[FALLBACK]` gate this phase names. If
the operator judges them not real, the confirmed count is 0, discovery mode is cut from V1, and Brief
assumption 3 is amended. Nothing else in the phase depends on that answer.

**Recommendation carried forward, not applied.** The measurement suggests the offer would be far more
useful if it corroborated before presenting, ranking oldest-first and then reporting how many
candidates survive a citation check. That is a change to the shipped discovery command, so it is
recorded here for the operator rather than made in-phase.

### Phase 5: Plugin surfaces [DONE]

**Executed 2026-09-05.** All eight Sanity Checks green. The version gate did not fire: `origin/main`
still carries `overengineering` 0.3.6, so 0.4.0 stands and nothing needed renumbering above a
sibling. One deviation from the plan's letter, recorded rather than taken silently: the marketplace
`tags` list was set equal to the keyword list as instructed, and the keyword list itself already
carried `delta`, which the tags did not, so the sync added `delta` alongside `justification` and
`justify`. The `diff` check in the Sanity Check below is what the plan asked for and it passes.

- [x] Read `.claude/rules/catalog-taxonomy.md` (procedural; category is unchanged).
- [x] `.claude-plugin/plugin.json`: `version` 0.3.6 → **0.4.0** (if a sibling PR lands a higher `overengineering` version first, renumber above it); description gains one clause naming the justification lane; `keywords` gain `justification`, `justify`.
- [x] `CHANGELOG.md`: `## [0.4.0]` with `### Added` (the `justify` lane; `justification-lane.md`; the sanctioning-record probe in the shared preflight) and `### Changed` (findings artifact schema 2: five layers, `Basis`, `mode`/`targets`, targeted merge clause, `justify` id forms, `package:` prefix; `realign` presents and never executes `justify` rows; `delta` coverage wording; `audit` writes schema 2).
- [x] `README.md`: fourth row in the skill table; "The shared method all three skills apply" reworded to "The shared method every skill applies" (accuracy; the count-claims gate does not match this form, so this is not a gate fix).
- [x] `.claude-plugin/marketplace.json`: `overengineering` entry `tags` set equal to the keyword list (a choice for consistency, not a repaired defect; no convention or gate ties tags to keywords). Category stays `quality`.
- [x] `node scripts/generate-catalog.mjs` and `node scripts/generate-cheatsheet.mjs` to regenerate `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` (the cheat sheet groups by `metadata.workflow-stage`; no config edit).

**File inventory (Phase 5):**

| File | Action | Rationale |
|---|---|---|
| [x] `plugins/overengineering/.claude-plugin/plugin.json` | MODIFY | version, description, keywords |
| [x] `plugins/overengineering/CHANGELOG.md` | MODIFY | `## [0.4.0]` |
| [x] `plugins/overengineering/README.md` | MODIFY | fourth row; wording |
| [x] `.claude-plugin/marketplace.json` | MODIFY | tags |
| [x] `docs/CATALOG.md` | MODIFY (generated) | regen |
| [x] `docs/SKILL-CHEAT-SHEET.md` | MODIFY (generated) | regen |
| [x] `.claude/settings.json` | KEEP | `overengineering@melodic-software` already enabled |
| [x] `scripts/skill-leaf-name-registry.txt` | KEEP | `justify` collides with no other plugin |
| [x] `scripts/cheatsheet-config.mjs` | KEEP | grouping is by metadata, not per skill |

**Sanity Check:**

- `git fetch origin main && bash scripts/check-changelog-parity.sh --check && bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.
- `bash scripts/check-skill-count-claims.sh --check` exit 0.
- `node scripts/generate-catalog.mjs --check && node scripts/generate-cheatsheet.mjs --check` exit 0.
- `bash scripts/check-plugin-catalog-enablement.sh && bash scripts/check-skill-leaf-names.sh --check` exit 0.
- `jq -e '.version == "0.4.0"' plugins/overengineering/.claude-plugin/plugin.json` exit 0 (or the renumbered value, recorded here).
- `diff <(jq -r '.keywords[]' plugins/overengineering/.claude-plugin/plugin.json | sort) <(jq -r '.plugins[] | select(.name=="overengineering") | .tags[]' .claude-plugin/marketplace.json | sort)` prints nothing.
- `grep -cE 'all three skills' plugins/overengineering/README.md` prints `0`.
- `test "$(grep -cE 'overengineering:' docs/SKILL-CHEAT-SHEET.md)" -eq 4 && echo OK` prints `OK`.

### Phase 6: Gate sweep, peer announcement, PR [TODO]

- [ ] `bash scripts/affected-tests.sh --explain --run` exit 0.
- [ ] Listing budget: `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/ > .work/justify-existence/listing-budget-after.txt`; compare the aggregate line against the one pasted in Phase 3's notes and record the delta here; the `justify` entry may add, the aggregate must not exceed the budget.
- [ ] `bash scripts/check-purged-em-dashes.sh --check` exit 0 (covers `README.md` and `skills/*/SKILL.md`, including the new one).
- [ ] `/ai-slop:audit` scoped to **created files and added lines only**: the new `SKILL.md`, `justification-lane.md`, `evals.json`, fixtures, and `git diff -U0 origin/main...HEAD -- <each modified file> | grep '^+'` for modified context docs, which carry pre-existing em dashes outside this plan's scope.
- [ ] **Peer announcement, before the PR exists.** Several sessions work this repo in parallel. Discover live peers via the remote-session list; message each via a persistent-session trigger (create, fire, delete) stating: this branch, the PR title, the full file list, that no contended file (`lib/hook-utils.sh` and copies, `plugins/*/hooks/**`, `docs/conventions/hook-*`, `docs/adr/**`, `scripts/check-*.sh`) is touched, and that `plugins/overengineering/**` is this lane's. Note the two shared generated files (`docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md`) and `.claude-plugin/marketplace.json`, which the later-landing PR regenerates or re-merges after rebase. Wait for no reply.
- [ ] Commit per phase via `/source-control:commit`; open the PR as **draft** via `/source-control:pull-request create` with a body meeting `.claude/rules/pr-body-contract.md` (`No related issue: <reason>` or `Closes #<n>`; `## Summary`, `## Fix`, `## Verification` including the discovery measurement numbers and the listing-budget delta, `## Related`). Flip to ready once CI is green.

**Sanity Check:**

- `bash scripts/affected-tests.sh` (list mode) exit 0 and prints at least one suite; `bash scripts/affected-tests.sh --run` exit 0.
- Footprint: `git diff --name-only origin/main...HEAD | grep -vE '^(plugins/overengineering/|docs/topics/justify-existence/|docs/CATALOG\.md$|docs/SKILL-CHEAT-SHEET\.md$|\.claude-plugin/marketplace\.json$)'` prints nothing.
- `test -s .work/justify-existence/listing-budget-after.txt && echo OK` prints `OK`; the delta is recorded here.
- The PR exists as a draft; its body's first non-empty line matches `^(No related issue: |Closes #|Fixes #|Resolves #)` and `grep -cE '^## (Summary|Fix|Verification|Related)$'` over the body prints `4`.

Notes (filled at execution): listing-budget aggregate after: `<pasted line>`; delta: `<value>`.

### Files Affected (whole plan)

| File | Action |
|---|---|
| `plugins/overengineering/context/justification-lane.md` | Create |
| `plugins/overengineering/skills/justify/SKILL.md` | Create |
| `plugins/overengineering/skills/justify/evals/evals.json` | Create |
| `plugins/overengineering/skills/justify/evals/fixtures/**` (decision-0001.md, vendored/{a,b}/util.txt, vendored/REGISTRY.txt, plugins-manifest.md, lonely-doc.md, convention-doc.md, hooks.json, rules-example.md, SKILL.md, claude-md.txt) | Create |
| `docs/topics/justify-existence/design/design-resolution.md` | Create (done at plan time) |
| `docs/topics/justify-existence/DEVIATIONS.md` | Create only if implementation deviates from a named test boundary |
| `plugins/overengineering/context/findings-artifact.md` | Modify |
| `plugins/overengineering/skills/{audit,realign,delta}/SKILL.md` | Modify |
| `plugins/overengineering/skills/realign/evals/evals.json` | Modify |
| `plugins/overengineering/skills/delta/context/{baseline-model,run-states}.md` | Modify |
| `plugins/overengineering/skills/audit/context/surface-walk.md` | Modify |
| `plugins/overengineering/.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md` | Modify |
| `.claude-plugin/marketplace.json` | Modify |
| `docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md` | Modify (generated) |
| `docs/topics/justify-existence/PLAN.md` | Modify (this file; phase tags and notes) |

### Dependencies

- Depends on: `scrutiny-method.md` "Lane binding" (unchanged), `surface-walk.md` lane-independent sections and "Layer 1"–"Layer 10" probes (Preflight gains one probe; otherwise unchanged), `report-template.md` (unchanged), `reference/topic-docs.md` for the artifact home (unchanged), `product-code-lane.md` "4. Protected-class defaults" (unchanged, pointed at by the `source` layer), `docs/conventions/finding-suppression/` (unchanged; the `check` constituent gains a producer segment).
- Depended on by: `realign`, `delta`, and `audit` (schema 2 acceptance and the present-only rule are Phase 1), the catalog and cheat-sheet generators, the listing-budget estimate, the orphaned-fixtures and shell-portability gates.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| New plugin `justification` (interview Q6) | ADR 0017 fixes lanes as sibling skills; would require vendoring three files under a sync gate and a cross-plugin route | ADR 0017 is superseded, or the operator rules the name outweighs the build cost |
| Separate artifact type `justification-findings` | Loses the shared suppression record and `realign`'s per-item display; `delta` would not consume either way | `realign` grows a multi-type reader |
| Reuse `scope` semantics for pointed runs | Merge rule 3 would close every un-examined finding in the target's layer | never |
| Routed targets write a row under a justify layer with `Verdict: UNPROVEN` | A spine row for an item another producer owns; its id would collide with or shadow `audit`'s | `audit` learns to skip ids from another producer |
| Force targets onto the existing ten layers | A README filed under `agent-instructions` is a false spine value carried forever | never |
| Line anchors (`path:line`) as ids | The id contract forbids positional anchors; two runs would derive two ids for one item | never |
| Drop `source` from V1 | Contradicts the Brief's "any line of code"; the protected-class gap is closed by pointing at the product-code lane's section 4 | the product-code lane's skill ships, at which point `source` hands over under a schema bump |
| Build the per-layer `realign` ladder now | ADR 0017's own deferred work; roughly doubles the plan | the ladder is needed for the first accepted `justify` retirement |
| Repo-wide sweep as bare invocation | The operator excluded it; ADR 0003's 23.7% case | the operator asks for a sweep mode and a corpus check reports acceptable precision |

### Test strategy

- Test-first: Phase 3 evals precede the Phase 4 body they grade. Output-based: every case asserts on the report's observable shape (verdict token, `Basis`, tiers, `mode`/`targets`, route with no row, widening statement, absence of a sweep), never on internal steps.
- Test boundaries: `/overengineering:justify <target>` (new); the findings artifact at schema 2 (existing contract, modified here, including `mode`/`targets`, the targeted merge clause, and the `Basis` migration rule); the route to `/overengineering:audit` (existing sibling, no row written); `realign`'s presentation of a `justify`-producer row (existing skill, one new rule, one new eval). No other boundary; a boundary picked during implementation that is not named here is a deviation logged to `DEVIATIONS.md` beside this file.
- Static gates as regression suite: `check-skill.sh`, `check-evals-quality.sh`, `check-listing-budget.sh`, `check-skill-precompute-compose.sh --strict`, `check-skill-portability.sh`, `check-orphaned-fixtures.sh --check`, `check-shell-portability.sh`, `check-purged-em-dashes.sh --check`, `check-changelog-parity.sh` (both modes), `check-skill-count-claims.sh --check`, `generate-catalog.mjs --check`, `generate-cheatsheet.mjs --check`, `check-plugin-catalog-enablement.sh`, `check-skill-leaf-names.sh --check`, `affected-tests.sh --run`, `markdownlint-cli2`, em-dash grep on added lines, `/ai-slop:audit` on created files and added lines.
- Regression for the migration: `realign`, `delta`, and `audit` bodies name schema 1 and 2 as accepted (grep); the spine definition is unchanged (`grep -cE 'id, layer, artifact, verdict, status' plugins/overengineering/context/findings-artifact.md` prints ≥ `1`); `delta`'s eval `unwalked-layer-is-coverage-never-a-closure` still describes the walk mode and is not weakened.
- The live tracer run (Phase 4) is the single end-to-end probe, on an attached branch, with the pre-existing artifact backed up and restored. Model-graded eval runs are the operator's to schedule via `claude plugin eval` and are not a mechanical gate here.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Description exceeds the per-entry listing cap or regresses the shared budget | Med | Med | Draft to the cap; Phase 3 captures the baseline into this file, Phase 6 compares; trim trigger phrases before anything else |
| Schema 2 breaks a reader nobody grepped for | Low | High | Pre-flight grep is Phase 1's first item; the migration is prose-only; schema is versioned so a reader that stops does so visibly; carried-forward rows stay legal by the `Basis` migration rule |
| The targeted clause is misread and a targeted run still closes or re-disposes findings it did not examine | Low | High | Clause placed ahead of rule 3 and scopes the four run-level sections and dispositions explicitly; eval 2 asserts `mode: targeted` |
| `realign` executes a `justify` row through the enforcement ladder | Low | High | Present-only rule in `realign` with its own eval |
| The five layers or the routing precedence prove wrong on a real target | Med | Med | Do not widen in-phase; record the mismatch, stop, and `/planning:plan review` |
| Two sessions write the same artifact concurrently | Low | Med | Re-read-before-write in every writer; hazard recorded in Known limits; no lock claimed |
| Sibling lanes edit `plugins/overengineering/**` or regenerate the shared generated files concurrently | Low | Med | No peer declared the plugin; announcement before the PR; regenerate `CATALOG.md` and `SKILL-CHEAT-SHEET.md` after rebase |
| `check-skill-count-claims` fires on README wording | Low | Low | Its closed claim forms do not match the current line; reworded for accuracy anyway |
| `Basis` invites `class-inferred` KEEPs as the easy default | Med | Med | A `class-inferred` KEEP requires the oracle cited, which makes it `measured`; eval 6 rejects the fused shape |
| Fixtures trip repo-wide gates or load as instructions | Med | Low | `.txt` for shell-shaped fixtures; no `CLAUDE.md` filename; every fixture in a `files[]`; both gates in Phase 3's checks |
| Discovery mode ships with unknown precision | Med | Med | Phase 4 measures on this repo and records the numbers here and in the PR body; zero confirmed candidates cuts the mode |
| The tracer run clobbers an existing artifact on this branch | Low | Med | Backup before, restore after; delete only when none existed and the file is provably the tracer's |

## Blast radius

**MEDIUM.** About 23 files, all inside one plugin plus its catalog, cheat-sheet, and marketplace rows; a versioned schema bump on a plugin-internal contract with prose-only consumers, now including two frontmatter keys, a merge clause that scopes four run-level sections, and a present-only rule in `realign`; fully reversible by revert. Stress-test triggers matched: "new skill creation that composes other skills" (composes `audit` and `planning:interview`) and a contract change consumed by three sibling skills. Step 4 formal stress-test: **ran**.

## Stress-test summary

**Step 3 (fresh-context plan reviewer), 2026-09-05:** 23 findings, 5 CRITICAL / 11 IMPORTANT / 7 SUGGESTION. Every contract claim was verified against the files before acting; all held. Resolutions: targeted run mode (`mode`, `targets`, merge clause) in the schema 2 bump; routed targets write no row; the lane's own `check`/`claim` forms and `package:` prefix; routing rule stated first and layers defined by exclusion; `source` binds the product-code lane's protected classes by pointer; ablation gate marked not applicable on the lane's layers; discovery mode measured in Phase 4; detached-checkout behaviour inherited by pointer; every Sanity Check rewritten as an exact command; fixture gates added; listing-budget baseline captured; ai-slop gate scoped to added lines; repo specifics moved out of shipped docs; Boundary handles placed in SKILL.md; no `#anchor` pointers; compaction confirm added to the no-target ladder; peer-announcement essentials inlined.

**Step 4 (`/planning:devils-advocate`, fresh context), 2026-09-05:** 3 CRITICAL / 6 HIGH / 6 MEDIUM / 4 LOW; verdict "does not survive as written". Every load-bearing claim was verified against the files; all held. Two findings changed the Brief and went to the operator (OD5 target grammar; OD1 re-confirmation with the composition benefit restated honestly), both accepted. The rest were decided on the verified text: `realign` presents and never executes this lane's rows (with an eval); the targeted clause scopes the four single-valued run-level sections and suppression dispositions to `targets`; `Basis` is required only on rows a schema-2 run writes; `delta`'s claim replaced by a Known-limits statement and a coverage-line distinction; the sanctioning-record probe moved into the shared preflight so the canonical vendored-copies case is reachable; `fixtures/CLAUDE.md` renamed because a nested `CLAUDE.md` loads as live instructions; `Basis` made citation-based and eval 6 rewritten; routing precedence for partly inventoried files, with eval 7 on whole-inventoried fixtures and a new eval 8; the six broken Sanity Checks rewritten and the tracer cleanup made restore-not-delete; lane sections renumbered `## N.` so `§N` means the method only; re-read-before-write; portability grep widened and cross-skill pointers pinned to the `${CLAUDE_PLUGIN_ROOT}/skills/audit/…` form; suppression dispositions scoped; baselines and measurements pasted into this tracked file, not only the ephemeral memory tier; one routing table; four LOW items accepted (wrapped enum pattern, count-claims risk downgraded, tags sync stated as a choice, pre-flight grep restated). No research-iterate was needed: every finding is grounded in-repo plus one official-docs fact the sub-agent fetched.

## Execution shape

**Fully sequential: 1 → 2 → 3 → 4 → 5 → 6.** Phases 3 and 5 are file-disjoint from every other phase and could run in parallel with 2 and 4 respectively, but the independent work is well under 100 LOC each and the whole plan is judgment-heavy prose authored to one voice; parallel agents would multiply token cost for no wall-clock saving worth the coordination. Sequential is the default, so no fallback is needed.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | contract edits to shared prose; wording must match the sibling skills' voice |
| 2 | main-session | the lane doc is the design core; judgment-heavy |
| 3 | main-session | evals encode acceptance criteria; needs the interview context |
| 4 | main-session | the skill body plus a live run and a measurement that need the operator present |
| 5 | main-session | small mechanical edits plus two generated files; not worth a dispatch |
| 6 | main-session | gate commands, the peer announcement, and the PR |

## Open questions

None at approval time. Q15 (unattended mode) stays deferred in the Brief with a USER-RESERVED arbiter.

## Handoff to implementation

### User-approval gates

- **[FALLBACK, confirm or override]** If `check-skill.sh` fails the per-entry cap on the `justify` description, the implementer trims trigger phrases first and the "Not for" clause second, never the quoted triggers that name the object. Surface the trimmed description before committing.
- **[FALLBACK, confirm or override]** If the Phase 4 tracer run shows a real target that fits none of the five layers and is not routed, or that the routing precedence classifies wrongly, the implementer stops and re-plans via `/planning:plan review` rather than adding a layer or a precedence case in-phase.
- **[FALLBACK, confirm or override]** If the Phase 4 discovery measurement yields zero operator-confirmed candidates, discovery mode is cut from V1 and Brief assumption 3 is amended; the operator confirms the cut.
- **[FALLBACK, confirm or override]** If a sibling PR lands a higher `overengineering` version before Phase 5, the implementer renumbers above it and says so.
- Any scope expansion beyond the files listed above.

### Execution shape ([EXEC-SHAPE] tagged)

- `[EXEC-SHAPE]` Contract migration first, evals before the skill body, plugin surfaces after the tracer run.
- `[EXEC-SHAPE]` Sequential, all main-session, as tabled above.
- `[EXEC-SHAPE]` Targeted run mode expressed as `mode: targeted` plus `targets`, with the merge clause placed ahead of rule 3 and scoping the four run-level sections and suppression dispositions, in the same schema 2 bump OD4 approved.
- `[EXEC-SHAPE]` `Basis` required only on rows a schema-2 run writes; carried-forward schema-1 rows display "not recorded (schema 1)".
- `[EXEC-SHAPE]` Routed targets write no artifact row; partly inventoried files are classified with the routed part named.
- `[EXEC-SHAPE]` `realign` presents and never executes `justify`-producer rows; one new `realign` eval.
- `[EXEC-SHAPE]` `check = overengineering/justify/rule-<layer>`, `claim = artifact-item`, prefix `package:<name>`, heading anchor `[<file>, <heading>]`.
- `[EXEC-SHAPE]` `Basis` semantics citation-based, as defined in Phase 1.
- `[EXEC-SHAPE]` `source` layer kept in V1 with the product-code lane's protected classes by pointer and a hand-over rule.
- `[EXEC-SHAPE]` Ablation gate recorded `n/a` on the lane's five layers.
- `[EXEC-SHAPE]` The sanctioning-record probe lives in `surface-walk.md` "Preflight" (lane-independent), not in the lane doc.
- `[EXEC-SHAPE]` Lane doc filename `context/justification-lane.md`, sections numbered `## N.`, `§N` reserved for the method.
- `[EXEC-SHAPE]` Version bump 0.3.6 → 0.4.0 (a new skill is a minor bump under the plugin's declared semver); marketplace tags set equal to keywords as a consistency choice.
- `[EXEC-SHAPE]` ADR 0017's `surface-walk.md` extraction is not performed beyond the one preflight probe; the lane points at the enforcement lane's copy intra-plugin.
- `[EXEC-SHAPE]` Sanity-check criteria per phase as written above.

### Mechanical work

- Commit boundaries: one commit per phase (1 contract; 2 lane doc; 3 evals and baseline; 4 skill body; 5 surfaces), each via `/source-control:commit`; PLAN.md phase tags and notes advance in the same commit as the phase.
- Verification checkpoints: each phase's Sanity Check runs green before its commit; Phase 6 runs the whole gate list.
- Sequential fallback: not applicable (already sequential).
- The PR is opened as a draft after the peer announcement; flip to ready when Phase 6 is green.
