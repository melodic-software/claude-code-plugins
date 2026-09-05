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
> verified three contract facts the draft missed, and the Plan below now carries them: the
> artifact's merge rule 3 closes any prior finding whose layer was walked and whose id is absent,
> so a pointed-target run needs a **targeted run mode** (`mode: targeted`, `targets:`) in the same
> schema bump; finding ids hardcode the `audit` producer and a closed kind-prefix set, so the lane
> gets its own `check` and `claim` forms and a `package:` prefix; and a routed enforcement-kind
> target has no legal spine, so **routing writes no artifact row**. Acceptance criteria touched by
> these are struck and annotated below.

## Brief

### TLDR

- ~~New single-skill plugin **`justification`**, category `quality`, handle **`/justification:audit <target>`**.~~ Superseded by OD1/OD2: **third lane skill `justify` inside `overengineering`, handle `/overengineering:justify <target>`.**
- Points at any artifact at any granularity (repo, folder, file, CI pipeline, feature or design, ADR, comment, one line) and asks: was there a stated reason for this, and is that reason still valid today?
- Read-only. Reports first, then discusses with the operator; hands the discussion to `/planning:interview` when it needs structure. Never applies a remedy; remedies route to the skills that already own them.
- Verdicts use the `overengineering` §6 ladder verbatim (KEEP / RETIRE / DOWNGRADE / CONSOLIDATE / UNPROVEN, FLAG-FOR-HUMAN cap) plus one delta: every row carries an evidentiary-basis tag (`measured` / `class-inferred` / `unexamined`).
- Evidence is tiered and auto-escalating (git, then forge, then consumer-specific sources); unreachable tiers are named in the verdict, never silently skipped; when not sure, it asks the operator for external context.

### Goal

Give the operator a pointed, portable instrument that makes any artifact justify its existence against the two-part test the operator stated: a reason existed when it was built, and that reason still holds today. The failure it exists to reverse is accreted output approved as a wall of text and now carried at cost (the operator's term: AI slop). The outcome is a report the operator can act on with confidence, where a retirement claim has paid for itself with evidence and a retention claim is visibly labelled by how much evidence actually supports it. The remedy is refactor or remove, decided by the operator after discussion; the skill's job ends at the report and the conversation it opens.

### Constraints

- ~~**ADR 0018 clause 2.** No cross-plugin path citation into `overengineering`'s private files. The shared scrutiny method is vendored into `plugins/justification/` and registered in `scripts/cross-plugin-source-registry.txt` so `check-cross-plugin-source-drift.sh --check` gates drift (ADR 0019).~~ Superseded by OD1: the skill lives inside `overengineering`, so the method is cited intra-plugin via `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` (ADR 0018 clause 1). Nothing is vendored. Section pointers are prose titles beside the file path, never `#anchors` (ADR 0018 clause 4).
- ~~**Enforcement-layer targets route, presence-gated.**~~ Superseded by OD1 and the second amendment: enforcement-kind targets route to the sibling `/overengineering:audit` and **write no artifact row**; the inline report names the route. No presence gate is needed inside one plugin.
- **Two gates, reported separately.** The ablation rubric (`docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook", durable tier exempt) and the ADR 0003 precision bar (no class exemption) are independent. A verdict row states which gate it answers. A fused verdict is a defect. Second amendment: on the lane's own five layers the ablation gate is **not applicable** and the row says so; it applies only to the enforcement kinds this lane routes.
- **Retire costs more than keep.** A RETIRE row names where the search looked and what a counterexample would look like, and is refused when the search was a single document or a single query form.
- **Absence checks vary the query form** (line wrap, hyphenation, casing, synonyms) before "not found" becomes a finding. A single-form grep is not a search.
- **Check for a sanctioning record and a maintaining gate before calling any pattern debt.** The canonical negative case is `lib/hook-utils.sh`: 17 byte-identical copies sanctioned by ADR 0019 and actively maintained by a CI drift gate. Second amendment: this repo's specifics stay in this Brief and in eval fixtures; the shipped lane doc describes the pattern generically (Design boundary).
- **Read-only on the target.** The only write is the findings artifact at the memory-tier home `overengineering` already resolves; never to the audited artifact. The artifact is `type: overengineering-findings` and is never `type: review-findings` (see Correction above).
- **No repo-wide sweep.** A bare invocation follows the fallback ladder in the acceptance criteria; it never enumerates the repository.
- **Portable.** Satisfies `docs/PLUGIN-PHILOSOPHY.md` "Design boundary": no dependence on this organization's paths, names, forge, or MCP servers. Consumer-specific evidence tiers are discovered from the consumer's own CLAUDE.md, installed MCP servers, and tool search.
- **One skill.** The no-target discovery behaviour is a mode of `justify`, not a sibling. Listing entry must survive `skill-quality:check listing-budget`.
- **House prose style.** No em dashes in SKILL.md, README, or plugin manifests; `/ai-slop:audit` clean on created files and added lines.
- **Repo process.** `scripts/affected-tests.sh --run` before push; PR opened as draft; PR body satisfies `.claude/rules/pr-body-contract.md`; announce to the sibling sessions before opening the PR (essentials inlined in Phase 6).
- **Files this lane does not touch:** `docs/PLUGIN-PHILOSOPHY.md`, `lib/hook-utils.sh` and its copies, `plugins/*/hooks/**`, `docs/conventions/hook-*`, `scripts/check-*.sh`, `docs/adr/**` without prior announcement.

### Acceptance criteria

- ~~`plugins/justification/` exists with `.claude-plugin/plugin.json`, `skills/audit/SKILL.md`, `README.md`, `CHANGELOG.md`, and `skills/audit/evals/evals.json`; `.claude-plugin/marketplace.json` carries the entry with `"category": "quality"`; `docs/CATALOG.md` is regenerated.~~ Superseded by OD1: `plugins/overengineering/skills/justify/SKILL.md` and `skills/justify/evals/evals.json` exist; `plugins/overengineering/context/justification-lane.md` exists; `plugin.json` version is bumped with a matching `CHANGELOG.md` entry; `README.md` lists the fourth skill; `docs/CATALOG.md` is regenerated with the repo's own tooling.
- ~~`skill-quality:check justification` passes~~ `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/overengineering/skills" bash plugins/skill-quality/scripts/check-skill.sh justify` reports PASS; `check-listing-budget.sh` does not regress against the baseline captured in Phase 3.
- `/overengineering:justify <file>` on a named artifact produces a report in which every verdict row carries: one of the six §6 tokens; a `Basis` value from `measured` / `class-inferred` / `unexamined` (second amendment: `measured` = evidence tiers consulted, cited or silent; `class-inferred` = the verdict rests on §6's non-derivable-oracle clause or a §7 class match without a tier consult; `unexamined` = no tier consulted, legal only with `Verdict: UNPROVEN`); the evidence tiers consulted with each marked silent or unavailable when it returned nothing; and, for RETIRE, the search locations and the counterexample shape.
- `/overengineering:justify` with no target does not sweep. It uses conversation context if any exists and confirms the inferred target in one line before walking; otherwise offers git-history discovery of old, low-churn candidates; otherwise asks the operator. The chosen rung is stated in the output.
- ~~An enforcement-kind target produces a finding whose `Routed-to` names `/overengineering:audit`.~~ Second amendment: an enforcement-kind target produces **no artifact row**; the inline report names `/overengineering:audit` as the route and states why (which of the ten layers' discovery probes would inventory it).
- ~~The vendored method file is listed in `scripts/cross-plugin-source-registry.txt`.~~ Superseded by OD4 and the second amendment: `findings-artifact.md` declares `schema: 2`; its `Layer` enum carries the five new values; its per-finding table carries `Basis`; its frontmatter carries `mode` and `targets`; its merge rules carry the targeted-run clause; its finding-id table carries the `justify` producer's `check` and `claim` and the `package:` prefix; and `realign`, `delta`, and `audit` each state they accept schema 2.
- SKILL.md carries a Boundary section naming, by slash handle, the incumbents it defers to: `overengineering:audit`, `code-tidying:audit-dead-code`, `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue`, `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise`, `claude-config:audit-instructions`, `claude-config:unhobble`, `claude-ops:audit-native-overlap`, `improvement:find`; and the scrutiny pairing `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast`.
- `evals/evals.json` includes at least these cases: (a) a sanctioned, gate-maintained byte-identical copy set is NOT reported as debt; (b) a manifest of hook-bearing plugins where most ship hooks plus their own setup skill is NOT reported as one violation per plugin; (c) a RETIRE row without named search locations is rejected; (d) a row that fuses a class claim with an earned-keep answer is rejected (second amendment: on a `documents` fixture, since an enforcement fixture would route); (e) a bare invocation does not enumerate the repository; (f) a CLAUDE.md, a hooks manifest, and a SKILL.md each route with no row.
- When the operator's answer to an evidence-tier question is "I don't know", the item is recorded UNPROVEN with the tier named, not resolved either way.

### Captured assumptions

- The operator's phrase "don't make videos" was a dictation slip for: do not conclude an artifact is unjustified merely because its justification is not in the repository. Revisit if the operator corrects the reading.
- ~~Findings conform to the repo's detector-findings convention, as `provenance` and `overengineering` already do.~~ Corrected 2026-09-05: findings are `type: overengineering-findings` per `plugins/overengineering/context/findings-artifact.md`, which deliberately refuses the fix relay. The inline report comes first per the operator's Q8 answer.
- ADR 0003's precision bar governs the no-target discovery mode, because that mode emits candidates over a corpus. Discovery mode ships only after a check on this repository reports its candidate count and how many the operator confirmed as real (Phase 4 measures it). Revisit if discovery mode is cut from V1.
- The `overengineering` §6 ladder tokens are stable enough to adopt verbatim. Revisit if `overengineering` changes its ladder; inside one plugin that change and this lane move together.
- V1 is attended-only, derived from the operator's answers to Q7 ("if not 100% sure, ask") and Q8 ("report first, then discuss"). See Q15.
- ~~`justification` is the plugin name.~~ Superseded by OD1/OD2: the handle is `/overengineering:justify <target>`. Revisit if it reads wrongly in use.
- `Basis` is outside the spine, so `delta` cannot report a `Basis` move (an `unexamined` row becoming `measured`). Chosen, not discovered: the spine stays closed so the diff stays meaningful. Revisit if operators ask for basis deltas.

### Out-of-scope

- Applying any refactor or removal. Remedies route to existing appliers.
- A repository-wide sweep in any mode.
- An unattended or dispatched run mode (deferred, Q15).
- A pre-creation corrector ("before you add that, justify it"). That is a different skill wearing the same name; if wanted later it is a `discipline` corrector.
- Comment-specific logic. `code-tidying:dissolve-comments` and `audit-comment-residue` own that ground; this skill defers to them.
- Editing `docs/PLUGIN-PHILOSOPHY.md` or writing a new ADR in this lane without prior announcement to the sibling sessions.
- A `realign`-style applier sibling.
- ADR 0017's extraction of `surface-walk.md`'s lane-independent parts to the plugin root. This lane points at the enforcement lane's copy intra-plugin, exactly as `product-code-lane.md` does during the transition.

### Deferred questions

- Q15: Should `/overengineering:justify` support an unattended or dispatched run mode (recording UNPROVEN and OPEN-INTENT instead of asking)? Defer until V1 has shipped and been used attended at least once. **Arbiter: USER-RESERVED** (an unattended mode changes the acceptance criteria above; `/planning:plan` proposes, the operator resolves).

## Plan

### Goal

**What**: Add a third lane skill, `justify`, to `plugins/overengineering/`, binding the existing scrutiny method to a lane whose item is whatever artifact the operator points at, and extend the shared findings artifact (schema 2) so the lane's verdicts land where `realign` and `delta` already read, without a pointed run ever closing findings it did not examine.
**Why**: The operator's two-part test (a reason existed; it still holds) is exactly what the method's §4 intent reconstruction and §5 rediscovery compute. Nothing in the fleet applies it to non-enforcement artifacts, and ADR 0017 fixes the shape a new lane takes.

### Standards grounding

Resolution ladder rungs 1-3 absent (no `.claude/standards.yaml`, no `docs/standards/`); rung 4 inferred from repository context. Persist-offer made to the operator on 2026-09-05, not acted on.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/PLUGIN-PHILOSOPHY.md` | Design boundary; Native-first; Instruction economy; Fresh-eyes checkpoints; "one mechanism per concern" (line 714) | team (inferred) |
| `docs/adr/0017-ship-the-product-code-lane-as-its-own-skill.md` | Decision; "The shared machinery is extracted, not forked" | team |
| `docs/adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md` | Decision clauses 1, 2, 4 | team |
| `docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md` | Decision clauses 1-5 | team |
| `plugins/overengineering/context/scrutiny-method.md` | Lane binding; §2, §4, §5, §6, §7 | team (plugin-internal contract) |
| `plugins/overengineering/context/findings-artifact.md` | Frontmatter; Layer vocabulary; Per-finding fields; The stable spine / free prose split; Finding ids; Re-run merge semantics; Ordering | team (plugin-internal contract) |
| `plugins/overengineering/skills/audit/context/surface-walk.md` | Preflight; The per-layer loop; Granularity; Layer 2 (its coverage of skill, command, and agent definitions) | team (plugin-internal) |
| `docs/CATALOG-TAXONOMY.md` | Form rule; Assignment principle | team |
| `.claude/rules/vendor-docs-are-not-style.md`, `.claude/rules/pr-body-contract.md` | whole | team (ambient, cited for completeness) |

### Approach

Build technique: **tracer bullet** on the kept slice. No viability unknown (the method exists and has two lanes); the risk is integration, so the thinnest working `justify` SKILL.md runs end-to-end on one real target before any polish. Contract changes land first so the lane doc and skill body cite fields that exist. Evals precede the skill body they grade (test-first; the eval is the skill's observable-behavior spec, per `/tdd:principles` "Test before or after? Before" and "Output-based first").

Order: contract migration (1) → lane binding doc (2) → evals, red, plus the listing-budget baseline (3) → SKILL.md thin slice, live tracer run, discovery measurement, green (4) → plugin surfaces (5) → gate sweep and PR (6).

Path conventions in every Sanity Check: run from the repository root; `$REPO` is not used; every command is verbatim-executable. `grep -E` is used wherever alternation appears, so nothing depends on GNU `\|` or `\+`.

### Phase 1: Extend the shared findings artifact to schema 2 [TODO]

Contract migration. The pre-flight consumer check is the first work item.

- [ ] **Pre-flight (FIRST):** confirm no script parses the artifact. Expected: the only non-markdown hit is `plugins/overengineering/skills/realign/evals/evals.json`, an eval mention. Consumers are the prose skills `realign`, `delta`, and `audit`. Record the result in this phase's notes.
- [ ] `context/findings-artifact.md` "Frontmatter": `schema` row reads "currently `2`"; keep the stop-on-unrecognized rule. Add two keys: `mode` (required; `walk` or `targeted`; `audit` writes `walk`) and `targets` (required when `mode: targeted`; the list of item identifiers examined this run, each a repo-relative path or kind-prefixed identifier). A `walk` run omits `targets`.
- [ ] `context/findings-artifact.md` "Re-run merge semantics": add the **targeted-run clause** ahead of rule 3: in a `targeted` run, rules 1 and 2 apply to ids whose sites are in `targets`; rule 3 applies **only** to a prior id whose every site is in `targets` and whose item is now absent; every other prior id carries forward per rule 4 regardless of `scope`. `scope` in a targeted run lists the layers of the targets, for ordering only, and asserts no exhaustive walk.
- [ ] `context/findings-artifact.md` "Layer vocabulary": append `decision-records` · `documents` · `components` · `dependencies` · `source` after `external-integrations`, keeping the "eleventh layer means a schema bump" sentence and stating these five are the justification lane's and never inventory an enforcement kind.
- [ ] `context/findings-artifact.md` "Per-finding fields": add row `Basis` | Spine: no | Required: always | one of `measured` (evidence tiers consulted, cited or silent), `class-inferred` (the verdict rests on §6's non-derivable-oracle clause or a §7 class match without a tier consult), `unexamined` (no tier consulted; legal only with `Verdict: UNPROVEN`). State that a KEEP is never `unexamined` because §6 requires a citation.
- [ ] `context/findings-artifact.md` "Finding ids": generalize the `check` row to `overengineering/<producer>/rule-<layer>` with `<producer>` one of `audit`, `justify`; add `claim = artifact-item` (and `artifact-item(member=<name>)`) for the `justify` producer beside `enforcement-item`; add `package:<name>` to the kind-prefix set for the `dependencies` layer. State that a routed target produces no id and no row.
- [ ] `skills/realign/SKILL.md`: accept `schema` `1` or `2`; on `2`, display `Basis`, `mode`, and `targets` with the finding and never let them change gating.
- [ ] `skills/delta/SKILL.md` and `skills/delta/context/baseline-model.md`: accept schema `1` or `2`; `Basis` is prose outside the spine and never enters the diff; a `targeted` run contributes findings but **never counts a layer as walked** for the "Layers that were not walked" coverage line, which gains a "targets examined: N" sentence for targeted runs. Add a gotcha: `delta` cannot see a `Basis` move.
- [ ] `skills/audit/SKILL.md`: one sentence that the enforcement lane writes `schema: 2`, `mode: walk`, and sets `Basis` (`measured` when a tier was consulted, else `class-inferred`).

**File inventory (Phase 1):**

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/overengineering/context/findings-artifact.md` | MODIFY | enum, `Basis`, `mode`/`targets`, merge clause, id forms, `schema: 2` |
| [ ] `plugins/overengineering/skills/realign/SKILL.md` | MODIFY | accept schema 2 |
| [ ] `plugins/overengineering/skills/delta/SKILL.md` | MODIFY | accept schema 2; targeted runs and coverage |
| [ ] `plugins/overengineering/skills/delta/context/baseline-model.md` | MODIFY | `Basis` outside the spine; targeted runs |
| [ ] `plugins/overengineering/skills/audit/SKILL.md` | MODIFY | writes schema 2, `mode: walk`, `Basis` |
| [ ] `plugins/overengineering/context/product-code-lane.md` | KEEP | its layer set is a specification ahead of its skill; not this lane's to change |

**Sanity Check:**

- `grep -rlE 'overengineering-findings' plugins/ scripts/ --include='*.sh' --include='*.mjs' --include='*.py' --include='*.json'` prints exactly one line, `plugins/overengineering/skills/realign/evals/evals.json`.
- `grep -cE '^\`agent-hooks\` · .*\`external-integrations\` · \`decision-records\` · \`documents\` · \`components\` · \`dependencies\` · \`source\`' plugins/overengineering/context/findings-artifact.md` prints `1` (the enum is one line in the source; if the edit wraps it, adjust the pattern to the wrapped shape and record the change here).
- `grep -cE 'currently \`2\`' plugins/overengineering/context/findings-artifact.md` prints `1`.
- `grep -cE '^\| \`(Basis|mode|targets)\`' plugins/overengineering/context/findings-artifact.md` prints `3`.
- `grep -cE 'overengineering/<producer>/rule-<layer>|artifact-item|package:<name>' plugins/overengineering/context/findings-artifact.md` prints a number ≥ 3.
- `grep -cE 'targeted' plugins/overengineering/context/findings-artifact.md` prints a number ≥ 3 (frontmatter key, merge clause, id note).
- For each of `plugins/overengineering/skills/realign/SKILL.md`, `plugins/overengineering/skills/delta/SKILL.md`, `plugins/overengineering/skills/audit/SKILL.md`: `grep -cE 'schema.*(1 or 2|1\` or \`2)' <file>` prints ≥ `1`.
- `git diff -U0 origin/main...HEAD -- plugins/overengineering | grep '^+' | grep -c $'\xe2\x80\x94'` prints `0` (no em dash on any added line).

### Phase 2: Lane binding doc `context/justification-lane.md` [TODO]

Mirror `context/product-code-lane.md`'s shape. Supplies the four things "Lane binding" asks for, plus this lane's rules from the Brief. Every bare `§N` is a section of `scrutiny-method.md`. Section pointers into sibling files are the file path plus the section's prose title, never a `#anchor` (ADR 0018 clause 4). No organization-specific path, name, count, or incident appears in this file; concrete cases live in eval fixtures.

- [ ] Header: the method is not restated; this document supplies only the lane's four things; status **shipping**.
- [ ] §1 **Routing rule, stated first and once:** if any of the ten enforcement layers' discovery probes (`skills/audit/context/surface-walk.md`, "Layer 1" through "Layer 10") would inventory the target, the target is routed to `/overengineering:audit`, **no row is written**, and the inline report names the layer that claimed it. Only what survives that test is classified below. Worked routing examples in prose: a hooks manifest (layer 1), a CLAUDE.md or the always-loaded portion of a skill, command, or agent definition (layer 2), a CI workflow (layer 5).
- [ ] §2 Item inventory: the item is what the operator points at, at the granularity pointed at. Aggregating-container rule by pointer (`surface-walk.md`, "Granularity"): a pointed-at file is the container; per-member sub-verdicts only where the file's own structure lists members mechanically (an ADR's numbered decisions, a manifest's entries).
- [ ] §3 Layer vocabulary, **defined by exclusion** after §1, one subsection per layer with its discovery probes: `decision-records` (decision logs and records; probe: status line, date, superseding record, citing files); `documents` (prose docs that are not layer-2 instruction surfaces; probe: inbound links, last substantive commit, whether a generator owns it); `components` (a plugin, skill, or agent **as a unit**, excluding its always-loaded text and any hooks manifest, both of which route; probe: listing presence, invocation evidence where the consumer records it, catalog entry); `dependencies` (declared packages and pinned tools; identifier `package:<name>`; probe: import or call sites, lockfile presence, upstream status); `source` (code constructs; probe: call sites and the §3 liveness questions; **binds `product-code-lane.md` "4. Protected-class defaults, extending §7" by pointer**, and states the hand-over rule: when the product-code lane's skill ships, `source` findings close under that lane's layers in a schema bump).
- [ ] §4 Evidence sources mapped onto the §2 tiers: tier 1 runtime or usage records the consumer keeps; tier 2 the introducing commit, its PR and linked issue, churn, revert history (the lane's workhorse); tier 3 incidents; tier 4 operator attestation **and** consumer-installed external context (ticketing, meeting-transcript MCP servers) recorded as attestation with date and source; tier 5 the artifact's own text, decision rationale, comments. Auto-escalation: consult tiers in order, stop when a verdict is earned, name every tier consulted and whether it was silent or unavailable. **Ask-when-unsure:** when tiers 1-3 are silent and tier 4 could exist, ask the operator whether external context exists before writing UNPROVEN.
- [ ] §5 Protected-class defaults extending §7: accepted decision records with citing consumers (retirement is a re-decision); license, security, and compliance documents; anything with declared external consumers; the intentionally-dormant class carries directly. `source` adds the product-code lane's classes by pointer (§3 above).
- [ ] §6 Preflight additions beyond `surface-walk.md` "Preflight": **sanctioning-record probe**, stated generically (a decision record, convention doc, or registry that sanctions the pattern, and a gate that maintains it; a sanctioned and gated pattern is never debt); **query-form variation** for every absence claim (line wrap, hyphenation, casing, synonyms; a single-form grep is not a search); **retire-costs-more**: a RETIRE row names the surfaces searched and the counterexample shape, and the lane refuses a RETIRE whose search was one document; **targeted mode**: every run writes `mode: targeted` and `targets`, never a walk.
- [ ] §7 The two gates: every row answers the **earned-keep** gate (does this configuration earn its carry cost; no class exemption). The **ablation** gate (would a better model still need this; durable tier exempt) is **not applicable on this lane's five layers** and each row says `ablation: n/a (routed layers only)`; it applies to the enforcement kinds §1 routes. A row that presents a class claim as an earned-keep answer is a defect.
- [ ] §8 `Basis` assignment, pointing at `findings-artifact.md` "Per-finding fields" for the vocabulary and stating the consequence: a row with no tier consulted is `UNPROVEN` and `unexamined`, never a KEEP.
- [ ] §9 No-target ladder: conversation context (confirm the inferred target in one line before walking, because a compacted session's summary may name files the operator never pointed at); else **offer** git-age discovery and wait; else ask. Never enumerate.
- [ ] §10 Boundary against existing owners (mirrors product-code-lane "6. Boundary against existing owners"): the enforcement route (§1, sibling, always present, no row); instruction text → `claude-config:audit-instructions`, `claude-config:unhobble`; comments → `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue`; unreachable code → `code-tidying:audit-dead-code`; doc derivability and noise → `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise`; native duplication → `claude-ops:audit-native-overlap`; cross-dimension ranking → `improvement:find`; scrutiny pairing → `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast`. Every non-sibling route is presence-gated with the inline fallback recorded in `Routed-to`.
- [ ] §11 The §10 YAGNI boundary restated for arbitrary artifacts: the remedy is refactor or remove, decided by the operator; the lane never proposes additions.
- [ ] §12 Known limits: `delta` cannot see a `Basis` move (chosen; the spine stays closed).

**Sanity Check:**

- `test "$(grep -cE '^## ' plugins/overengineering/context/justification-lane.md)" -ge 12 && echo OK` prints `OK`.
- Every `§N` cited resolves: `comm -23 <(grep -oE '§[0-9]+' plugins/overengineering/context/justification-lane.md | tr -d '§' | sort -u) <(grep -oE '^## [0-9]+' plugins/overengineering/context/scrutiny-method.md | grep -oE '[0-9]+' | sort -u)` prints nothing.
- Every slash handle resolves: `grep -oE '`/?[a-z0-9-]+:[a-z0-9-]+`' plugins/overengineering/context/justification-lane.md | tr -d '`/' | sort -u | while IFS=: read p s; do test -d "plugins/$p/skills/$s" || echo "UNRESOLVED $p:$s"; done` prints nothing.
- `grep -cE '#[a-z]' plugins/overengineering/context/justification-lane.md` prints `0` (no anchor links).
- `grep -cE 'hook-utils|ADR 0019|melodic|17 (byte-identical )?copies|20 of 20|14 (ship|are)' plugins/overengineering/context/justification-lane.md` prints `0` (no repo specifics).
- `markdownlint-cli2 plugins/overengineering/context/justification-lane.md` exit 0; `grep -c $'\xe2\x80\x94' plugins/overengineering/context/justification-lane.md` prints `0`.

### Phase 3: Evals first, red; listing-budget baseline [TODO]

Write the observable-behavior spec before the skill body. Fixtures are self-contained under `skills/justify/evals/fixtures/`; every fixture is named in at least one case's `files[]`; shell-shaped fixtures use a `.txt` suffix so `scripts/check-shell-portability.sh` does not lint them as scripts.

- [ ] Capture the listing-budget baseline before any listing entry changes: `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/ > .work/justify-existence/listing-budget-before.txt`.
- [ ] `skills/justify/evals/evals.json`, `skill_name: justify`, cases (ids 1-8):
  1. `bare-invocation-does-not-sweep`: no target, no conversation context; expects the ladder stated, git-age discovery **offered** not run, no enumeration, no file written.
  2. `pointed-target-full-row`: `fixtures/decision-0001.md`; expects one finding with a six-token verdict, `Basis`, tiers consulted with silent or unavailable marked, `Layer: decision-records`, `mode: targeted`, `targets` naming the fixture, `schema: 2`, `ablation: n/a`.
  3. `sanctioned-copies-are-not-debt`: `fixtures/vendored/a/util.txt`, `fixtures/vendored/b/util.txt` (byte-identical) plus `fixtures/vendored/REGISTRY.txt` sanctioning them and naming a maintaining check; expects KEEP or UNPROVEN, never RETIRE or CONSOLIDATE, with the sanctioning record cited.
  4. `bundled-setup-skill-is-not-a-violation`: `fixtures/plugins-manifest.md` describing a set of hook-bearing plugins most of which ship hooks plus their own `setup` skill; expects the report to separate the two groups and refuse a one-violation-per-plugin count.
  5. `retire-without-search-is-refused`: `fixtures/lonely-doc.md` with "I grepped once, retire it"; expects the RETIRE refused until search surfaces and query forms are named, UNPROVEN recorded meanwhile.
  6. `class-claim-is-not-earned-keep`: `fixtures/convention-doc.md` with "keep it, it is a convention doc"; expects `Basis: class-inferred` **and** an earned-keep answer stated separately (UNPROVEN or the measured verdict), with a refusal to let the class claim stand as the verdict.
  7. `enforcement-kinds-route-with-no-row`: `fixtures/hooks.json`, `fixtures/CLAUDE.md`, `fixtures/SKILL.md`; expects each routed to `/overengineering:audit` naming layer 1, 2, 2 respectively, and **no artifact row** for any of them.
  8. `dont-know-is-unproven`: `fixtures/decision-0001.md` with the operator answering "I don't know" to the external-context question; expects UNPROVEN with the tier named, not KEEP or RETIRE.

**Sanity Check:**

- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/overengineering/skills/justify/evals/evals.json` exit 0.
- `jq -r '.evals[].files[]' plugins/overengineering/skills/justify/evals/evals.json | sort -u | while read -r f; do test -f "plugins/overengineering/skills/justify/$f" || echo "MISSING $f"; done` prints nothing.
- `bash scripts/check-orphaned-fixtures.sh --check` exit 0.
- `bash scripts/check-shell-portability.sh` exit 0 (no `.sh` fixture is introduced).
- `markdownlint-cli2 'plugins/overengineering/skills/justify/evals/fixtures/**/*.md'` exit 0.
- `test -s .work/justify-existence/listing-budget-before.txt && echo OK` prints `OK`.
- Red: `test ! -f plugins/overengineering/skills/justify/SKILL.md && echo RED` prints `RED`.

### Phase 4: `skills/justify/SKILL.md`, thin slice, live tracer run, discovery measurement [TODO]

Model on `skills/audit/SKILL.md`'s section order. Composes the method by pointer; restates nothing.

- [ ] Frontmatter: `description` under the per-entry cap, first clause naming the object ("Justify the existence of any artifact you point at…"), quoted triggers ("justify this", "does this need to exist", "why is this here", "is this still valid", "earn its keep", "justify the existence of"), the no-target behaviour, "Not for" the enforcement surface (route to `audit`) and remedies (route to owners); `argument-hint: "<target> | (none: conversation context, then offered git-age discovery, then ask)"`; `user-invocable: true`; `disable-model-invocation: false`; `shell: bash`; `metadata.workflow-stage: anytime`; `metadata.summary`.
- [ ] Pre-computed context: **one** git injection line only (`#1619`): branch via `git symbolic-ref --quiet --short HEAD`.
- [ ] Purpose; the method pointer (`${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md`) and the lane pointer (`${CLAUDE_PLUGIN_ROOT}/context/justification-lane.md`); Read-only contract by pointer to `skills/audit/SKILL.md` "Read-only contract", stating the one write and its `mode: targeted`.
- [ ] **Branch identity** by pointer to `skills/audit/SKILL.md` "A detached checkout has no branch identity": a detached checkout writes no artifact and emits the full inline summary; the refusal line is quoted.
- [ ] Arguments: `<target>` grammar (path, `path:line`, `path#heading`, or a free-text name resolved against the tree with the query-form rule); the no-target ladder per lane §9 with the one-line confirmation; discovery offer command: `git log --diff-filter=A --name-only --format='%ad' --date=short -- . | awk 'NF' | sort -u` piped through an age ranking, **offered and waited on**, never run unasked.
- [ ] Before the walk: `surface-walk.md` "Preflight" by pointer plus the lane's §6 additions and the §1 routing test.
- [ ] The walk: the per-item loop by pointer; a pointed target is one item unless the container rule splits it.
- [ ] Verdicts and evidence: §6 by pointer; `Basis` on every row; `ablation: n/a` on every row; the earned-keep gate named.
- [ ] Intent checkpoints: attended only in V1; report first, then the discussion; reuse `planning:interview` mechanics when installed, inline numbered questions otherwise; "I don't know" → UNPROVEN with the tier named.
- [ ] **Boundary (in SKILL.md, not only the lane doc):** the handle table from lane §10, so the acceptance criterion holds on this file.
- [ ] The report: hand off to `skills/audit/context/report-template.md` by pointer.
- [ ] Gotchas: the absence rule with a **generic** worked example (a multi-word phrase wrapped across a line break defeats a single-line grep); the relocated-coverage case (a never-fires guard whose concern is guarded elsewhere is not unguarded). No repo-specific incident names.
- [ ] **Live tracer run:** `/overengineering:justify docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md` in this session. Integration probe, not a deliverable.
- [ ] **Remove the tracer artifact** at the path the run's opening line names (`.work/overengineering/<branch-slug>/findings.md`), so a later `audit` or `delta` on this branch does not merge or bootstrap from it.
- [ ] **Discovery measurement (ADR 0003 clauses 1-2):** run the discovery probe on this repository once, record the candidate count and how many the operator confirms as real candidates, and write both numbers into the PR body's `## Verification` section. If the operator confirms none, discovery mode is cut from V1 and the Brief's assumption 3 is amended.

**Sanity Check:**

- `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/overengineering/skills" bash plugins/skill-quality/scripts/check-skill.sh justify` prints a line matching `^CHECK-SKILL .*: PASS`.
- `bash scripts/check-skill-precompute-compose.sh --strict --paths plugins/overengineering/skills/justify/SKILL.md` exit 0.
- `bash scripts/check-skill-portability.sh --paths plugins/overengineering/skills/justify/SKILL.md plugins/overengineering/context/justification-lane.md` exit 0.
- Every slash handle in SKILL.md resolves: `grep -oE '`/?[a-z0-9-]+:[a-z0-9-]+`' plugins/overengineering/skills/justify/SKILL.md | tr -d '`/' | sort -u | while IFS=: read p s; do test -d "plugins/$p/skills/$s" || echo "UNRESOLVED $p:$s"; done` prints nothing.
- `grep -cE '#[a-z]' plugins/overengineering/skills/justify/SKILL.md` prints `0`.
- Tracer output contains a finding heading (`###`) followed by `**Layer:** decision-records`, `**Verdict:**` one of the six tokens, and `**Basis:**` one of the three values; its frontmatter shows `mode: targeted` and `schema: 2`.
- After removal: `test ! -f ".work/overengineering/$(git symbolic-ref --quiet --short HEAD | tr '/' '-')/findings.md" && echo CLEAN` prints `CLEAN` (adjust the slug form to what the tracer's opening line printed, and record it).
- `git status --porcelain | grep -vE '^(A|M|\?\?) +(plugins/overengineering/|docs/topics/justify-existence/)'` prints nothing.
- Discovery measurement recorded: the two numbers appear in `.work/justify-existence/plan-checklist.md` under Phase 4 pending the PR body.

### Phase 5: Plugin surfaces [TODO]

- [ ] `.claude-plugin/plugin.json`: `version` 0.3.6 → **0.4.0**; description gains one clause naming the justification lane; `keywords` gain `justification`, `justify`.
- [ ] `CHANGELOG.md`: `## [0.4.0]` with `### Added` (the `justify` lane; `justification-lane.md`) and `### Changed` (findings artifact schema 2: five layers, `Basis`, `mode`/`targets`, targeted merge clause, `justify` id forms, `package:` prefix; `realign`, `delta`, `audit` accept schema 2; `delta` coverage for targeted runs).
- [ ] `README.md`: fourth row in the skill table; line 18 "The shared method all three skills apply" reworded to "The shared method every skill applies", so `check-skill-count-claims.sh` has nothing to fail on.
- [ ] `.claude-plugin/marketplace.json`: `overengineering` entry `tags` synced to the **full** keyword set (it already lacks `delta`; the sync closes that too). Category stays `quality`.
- [ ] `node scripts/generate-catalog.mjs` to regenerate `docs/CATALOG.md`.

**File inventory (Phase 5):**

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/overengineering/.claude-plugin/plugin.json` | MODIFY | version, description, keywords |
| [ ] `plugins/overengineering/CHANGELOG.md` | MODIFY | `## [0.4.0]` |
| [ ] `plugins/overengineering/README.md` | MODIFY | fourth row; count claim reworded |
| [ ] `.claude-plugin/marketplace.json` | MODIFY | tags synced to keywords |
| [ ] `docs/CATALOG.md` | MODIFY (generated) | regen |
| [ ] `.claude/settings.json` | KEEP | `overengineering@melodic-software` already enabled |
| [ ] `scripts/skill-leaf-name-registry.txt` | KEEP | `justify` collides with no other plugin |

**Sanity Check:**

- `git fetch origin main && bash scripts/check-changelog-parity.sh --check && bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.
- `bash scripts/check-skill-count-claims.sh --check` exit 0.
- `node scripts/generate-catalog.mjs --check` exit 0.
- `bash scripts/check-plugin-catalog-enablement.sh` exit 0; `bash scripts/check-skill-leaf-names.sh --check` exit 0.
- `jq -e '.version == "0.4.0"' plugins/overengineering/.claude-plugin/plugin.json` exit 0.
- `diff <(jq -r '.keywords[]' plugins/overengineering/.claude-plugin/plugin.json | sort) <(jq -r '.plugins[] | select(.name=="overengineering") | .tags[]' .claude-plugin/marketplace.json | sort)` prints nothing.
- `grep -cE 'all three skills' plugins/overengineering/README.md` prints `0`.

### Phase 6: Gate sweep, peer announcement, PR [TODO]

- [ ] `bash scripts/affected-tests.sh --explain --run` exit 0.
- [ ] Listing budget: `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/ > .work/justify-existence/listing-budget-after.txt`; compare the aggregate line against `listing-budget-before.txt` and record the delta; the `justify` entry may add, the aggregate must not exceed the budget.
- [ ] `bash scripts/check-purged-em-dashes.sh --check` exit 0 (covers `README.md` and `skills/*/SKILL.md`, including the new one).
- [ ] `/ai-slop:audit` scoped to **created files and added lines only**: the new `SKILL.md`, `justification-lane.md`, `evals.json`, fixtures, and `git diff -U0 origin/main...HEAD -- <each modified file> | grep '^+'` for modified context docs, which carry pre-existing em dashes outside this plan's scope.
- [ ] **Peer announcement, before the PR exists.** Six sessions work this repo in parallel. Send each live peer (discover via the remote-session list; message via a persistent-session trigger created, fired, and deleted) one message stating: this branch, the PR title, and the full file list; that no contended file (`lib/hook-utils.sh` and copies, `plugins/*/hooks/**`, `docs/conventions/hook-*`, `docs/adr/**`, `scripts/check-*.sh`) is touched; and that `plugins/overengineering/**` is this lane's. Wait for no reply; the announcement is the obligation.
- [ ] Commit per phase via `/source-control:commit`; open the PR as **draft** via `/source-control:pull-request create` with a body meeting `.claude/rules/pr-body-contract.md` (`No related issue: <reason>` or `Closes #<n>`; `## Summary`, `## Fix`, `## Verification` including the discovery measurement numbers, `## Related`). Flip to ready once CI is green.

**Sanity Check:**

- `bash scripts/affected-tests.sh` (list mode) exit 0 and prints at least one suite; `bash scripts/affected-tests.sh --run` exit 0.
- Footprint: `git diff --name-only origin/main...HEAD | grep -vE '^(plugins/overengineering/|docs/topics/justify-existence/|docs/CATALOG\.md$|\.claude-plugin/marketplace\.json$)'` prints nothing.
- `test -s .work/justify-existence/listing-budget-after.txt && echo OK` prints `OK`.
- The PR exists as a draft; its body's first non-empty line matches `^(No related issue: |Closes #|Fixes #|Resolves #)` and `grep -cE '^## (Summary|Fix|Verification|Related)$'` over the body prints `4`.

### Files Affected (whole plan)

| File | Action |
|---|---|
| `plugins/overengineering/context/justification-lane.md` | Create |
| `plugins/overengineering/skills/justify/SKILL.md` | Create |
| `plugins/overengineering/skills/justify/evals/evals.json` | Create |
| `plugins/overengineering/skills/justify/evals/fixtures/**` (decision-0001.md, vendored/{a,b}/util.txt, vendored/REGISTRY.txt, plugins-manifest.md, lonely-doc.md, convention-doc.md, hooks.json, CLAUDE.md, SKILL.md) | Create |
| `docs/topics/justify-existence/design/design-resolution.md` | Create (done at plan time) |
| `docs/topics/justify-existence/DEVIATIONS.md` | Create only if implementation deviates from a named test boundary |
| `plugins/overengineering/context/findings-artifact.md` | Modify |
| `plugins/overengineering/skills/{audit,realign,delta}/SKILL.md` | Modify |
| `plugins/overengineering/skills/delta/context/baseline-model.md` | Modify |
| `plugins/overengineering/.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md` | Modify |
| `.claude-plugin/marketplace.json` | Modify |
| `docs/CATALOG.md` | Modify (generated) |
| `docs/topics/justify-existence/PLAN.md` | Modify (this file; phase tags) |

### Dependencies

- Depends on: `scrutiny-method.md` "Lane binding" (unchanged), `surface-walk.md` lane-independent sections and "Layer 1"–"Layer 10" probes (unchanged, pointed at), `report-template.md` (unchanged), `reference/topic-docs.md` for the artifact home (unchanged), `product-code-lane.md` "4. Protected-class defaults" (unchanged, pointed at by the `source` layer).
- Depended on by: `realign`, `delta`, and `audit` (schema 2 acceptance is Phase 1), the catalog generator, the listing-budget estimate, the orphaned-fixtures and shell-portability gates.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| New plugin `justification` (interview Q6) | ADR 0017 fixes lanes as sibling skills; would require vendoring three files under a sync gate and a cross-plugin route | ADR 0017 is superseded, or the operator rules the name outweighs the build cost |
| Separate artifact type `justification-findings` | `realign`/`delta` would not consume it, undercutting the reason OD1 was chosen | `realign` grows a multi-type reader, or the lane's verdicts are never meant to be realigned |
| Reuse `scope` semantics for pointed runs | Merge rule 3 would close every un-examined finding in the target's layer | never |
| Routed targets write a row under a justify layer with `Verdict: UNPROVEN` | Produces a spine row for an item another producer owns; its id would collide with or shadow `audit`'s | `audit` learns to skip ids from another producer |
| Force targets onto the existing ten layers | A README filed under `agent-instructions` is a false spine value carried forever | never |
| Drop `source` from V1 | Contradicts the Brief's "any line of code"; the protected-class gap is closed by pointing at the product-code lane's §4 instead | the product-code lane's skill ships, at which point `source` hands over under a schema bump |
| Repo-wide sweep as bare invocation | The operator excluded it; ADR 0003's 23.7% case | the operator asks for a sweep mode and a corpus check reports acceptable precision |

### Test strategy

- Test-first: Phase 3 evals precede the Phase 4 body they grade. Output-based: every case asserts on the report's observable shape (verdict token, `Basis`, tiers, `mode`/`targets`, route with no row, absence of a sweep), never on internal steps.
- Test boundaries: `/overengineering:justify <target>` (new, this plan introduces it); the findings artifact at schema 2 (existing contract, modified here, including `mode`/`targets` and the targeted merge clause); the route to `/overengineering:audit` (existing sibling, no row written). No other boundary; a boundary picked during implementation that is not named here is a deviation logged to `DEVIATIONS.md` beside this file.
- Static gates as regression suite: `check-skill.sh`, `check-evals-quality.sh`, `check-listing-budget.sh`, `check-skill-precompute-compose.sh --strict`, `check-skill-portability.sh`, `check-orphaned-fixtures.sh --check`, `check-shell-portability.sh`, `check-purged-em-dashes.sh --check`, `check-changelog-parity.sh` (both modes), `check-skill-count-claims.sh --check`, `generate-catalog.mjs --check`, `check-plugin-catalog-enablement.sh`, `check-skill-leaf-names.sh --check`, `affected-tests.sh --run`, `markdownlint-cli2`, em-dash grep on added lines, `/ai-slop:audit` on created files and added lines.
- Regression for the migration: `realign`, `delta`, and `audit` bodies name schema 1 and 2 as accepted (grep); the spine definition is unchanged (`grep -cE 'id, layer, artifact, verdict, status' plugins/overengineering/context/findings-artifact.md` prints ≥ `1`); `delta`'s eval `unwalked-layer-is-coverage-never-a-closure` still describes the walk mode and is not weakened.
- The live tracer run (Phase 4) is the single end-to-end probe, on an attached branch; the detached-checkout behaviour is inherited by pointer and covered by `audit`'s own evals. Model-graded eval runs are the operator's to schedule via `claude plugin eval` and are not a mechanical gate here.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Description exceeds the per-entry listing cap or regresses the shared budget | Med | Med | Draft to the cap; Phase 3 captures the baseline, Phase 6 compares; trim trigger phrases before anything else |
| Schema 2 breaks a reader nobody grepped for | Low | High | Pre-flight grep is Phase 1's first item; the migration is prose-only; schema is versioned so a reader that stops does so visibly |
| The targeted-run merge clause is misread and a targeted run still closes findings | Low | High | Rule stated ahead of rule 3 in the contract; eval 2 asserts `mode: targeted`; `delta` gains the coverage sentence |
| The five layers prove wrong on a real target during the tracer run | Med | Med | Do not widen in-phase; record the mismatch, stop, and `/planning:plan review` |
| Sibling lanes edit `plugins/overengineering/**` concurrently | Low | Med | No peer declared it; announcement before the PR; `git fetch` and a rebase check at Phase 6 |
| `check-skill-count-claims` fires on README line 18 | High | Low | Reword to name no count in Phase 5 |
| `Basis` invites `class-inferred` KEEPs as the easy default | Med | Med | Lane §8 makes an unconsulted row UNPROVEN; eval 6 rejects the class-as-verdict shape |
| Fixtures trip repo-wide gates | Med | Low | `.txt` for shell-shaped fixtures; every fixture in a `files[]`; both gates in Phase 3's checks |
| Discovery mode ships with unknown precision | Med | Med | Phase 4 measures on this repo and records the numbers in the PR body; zero confirmed candidates cuts the mode |

## Blast radius

**MEDIUM.** About 20 files, all inside one plugin plus its catalog and marketplace rows; a versioned schema bump on a plugin-internal contract with prose-only consumers, now including two frontmatter keys and a merge-rule clause; fully reversible by revert. Stress-test triggers matched: "new skill creation that composes other skills" (composes `audit` and `planning:interview`) and a contract change consumed by three sibling skills. Step 4 formal stress-test: **runs**.

## Stress-test summary

**Step 3 (fresh-context plan reviewer), 2026-09-05:** 23 findings, 5 CRITICAL / 11 IMPORTANT / 7 SUGGESTION. Every contract claim was verified against the files before acting; all held. Resolutions carried into the Plan above: targeted run mode (`mode`, `targets`, merge clause) in the schema 2 bump; routed targets write no row; the lane's own `check`/`claim` forms and `package:` prefix; `Basis` vocabulary redefined so a KEEP is never `unexamined`; routing rule stated first and layers defined by exclusion; `source` binds the product-code lane's protected classes by pointer; ablation gate marked not applicable on the lane's layers; eval 6 moved off an enforcement fixture; routing eval added for CLAUDE.md and SKILL.md; discovery mode measured in Phase 4; detached-checkout behaviour inherited by pointer; tracer artifact removed; every Sanity Check rewritten as an exact, exit-code-correct, portable command; fixture gates added; listing-budget baseline captured; ai-slop gate scoped to added lines; repo specifics moved out of shipped docs; Boundary handles placed in SKILL.md; no `#anchor` pointers; `Basis` blind spot in `delta` recorded as chosen; compaction confirm added to the no-target ladder; peer-announcement essentials inlined.

**Step 4 (`/planning:devils-advocate`):** pending; this section is extended with its verified findings before approval.

## Execution shape

**Fully sequential: 1 → 2 → 3 → 4 → 5 → 6.** Phases 3 and 5 are file-disjoint from every other phase and could run in parallel with 2 and 4 respectively, but the independent work is well under 100 LOC each and the whole plan is judgment-heavy prose authored to one voice; parallel agents would multiply token cost for no wall-clock saving worth the coordination. Sequential is the default, so no fallback is needed.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | contract edits to shared prose; wording must match the sibling skills' voice |
| 2 | main-session | the lane doc is the design core; judgment-heavy |
| 3 | main-session | evals encode acceptance criteria; needs the interview context |
| 4 | main-session | the skill body plus a live run and a measurement that need the operator present |
| 5 | main-session | small mechanical edits plus a generated file; not worth a dispatch |
| 6 | main-session | gate commands, the peer announcement, and the PR |

## Open questions

None at approval time. Q15 (unattended mode) stays deferred in the Brief with a USER-RESERVED arbiter.

## Handoff to implementation

### User-approval gates

- **[FALLBACK, confirm or override]** If `check-skill.sh` fails the per-entry cap on the `justify` description, the implementer trims trigger phrases first and the "Not for" clause second, never the quoted triggers that name the object. Surface the trimmed description before committing.
- **[FALLBACK, confirm or override]** If the Phase 4 tracer run shows a real target that fits none of the five layers and is not routed, the implementer stops and re-plans via `/planning:plan review` rather than adding a layer in-phase (a layer is a schema-level enum value).
- **[FALLBACK, confirm or override]** If the Phase 4 discovery measurement yields zero operator-confirmed candidates, discovery mode is cut from V1 and Brief assumption 3 is amended; the operator confirms the cut.
- Any scope expansion beyond the files listed above.

### Execution shape ([EXEC-SHAPE] tagged)

- `[EXEC-SHAPE]` Contract migration first, evals before the skill body, plugin surfaces after the tracer run.
- `[EXEC-SHAPE]` Sequential, all main-session, as tabled above.
- `[EXEC-SHAPE]` Targeted run mode expressed as `mode: targeted` plus `targets`, with the merge clause placed ahead of rule 3, in the same schema 2 bump OD4 approved.
- `[EXEC-SHAPE]` Routed targets write no artifact row; the inline report carries the route.
- `[EXEC-SHAPE]` `check = overengineering/justify/rule-<layer>`, `claim = artifact-item`, prefix `package:<name>`.
- `[EXEC-SHAPE]` `Basis` semantics: `measured` = tiers consulted; `class-inferred` = §6 oracle or §7 class without a consult; `unexamined` legal only with UNPROVEN.
- `[EXEC-SHAPE]` `source` layer kept in V1 with the product-code lane's §4 protected classes by pointer, and a hand-over rule.
- `[EXEC-SHAPE]` Ablation gate recorded `n/a` on the lane's five layers.
- `[EXEC-SHAPE]` Lane doc filename `context/justification-lane.md`, mirroring `context/product-code-lane.md`.
- `[EXEC-SHAPE]` Version bump 0.3.6 → 0.4.0 (a new skill is a minor bump under the plugin's declared semver); marketplace tags synced to the full keyword set.
- `[EXEC-SHAPE]` ADR 0017's `surface-walk.md` extraction is not performed; the lane points at the enforcement lane's copy intra-plugin.
- `[EXEC-SHAPE]` Sanity-check criteria per phase as written above.

### Mechanical work

- Commit boundaries: one commit per phase (1 contract; 2 lane doc; 3 evals and baseline; 4 skill body; 5 surfaces), each via `/source-control:commit`; PLAN.md phase tags advance in the same commit as the phase.
- Verification checkpoints: each phase's Sanity Check runs green before its commit; Phase 6 runs the whole gate list.
- Sequential fallback: not applicable (already sequential).
- The PR is opened as a draft after the peer announcement; flip to ready when Phase 6 is green.
