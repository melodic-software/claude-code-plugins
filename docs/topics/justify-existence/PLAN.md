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

- ~~**ADR 0018 clause 2.** No cross-plugin path citation into `overengineering`'s private files. The shared scrutiny method is vendored into `plugins/justification/` and registered in `scripts/cross-plugin-source-registry.txt` so `check-cross-plugin-source-drift.sh --check` gates drift (ADR 0019).~~ Superseded by OD1: the skill lives inside `overengineering`, so the method is cited intra-plugin via `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` (ADR 0018 clause 1). Nothing is vendored.
- ~~**Enforcement-layer targets route, presence-gated.**~~ Superseded by OD1: enforcement-kind targets route to the sibling `/overengineering:audit`; no presence gate is needed inside one plugin. The finding still records `Routed-to`.
- **Two gates, reported separately.** The ablation rubric (`docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook", durable tier exempt) and the ADR 0003 precision bar (no class exemption) are independent. A verdict row states which gate it answers. A fused verdict is a defect.
- **Retire costs more than keep.** A RETIRE row names where the search looked and what a counterexample would look like, and is refused when the search was a single document or a single query form.
- **Absence checks vary the query form** (line wrap, hyphenation, casing, synonyms) before "not found" becomes a finding. A single-form grep is not a search.
- **Check for a sanctioning ADR and a maintaining gate before calling any pattern debt.** The canonical negative case is `lib/hook-utils.sh`: 17 byte-identical copies sanctioned by ADR 0019 and actively maintained by a CI drift gate.
- **Read-only on the target.** The only write is the findings artifact at the memory-tier home `overengineering` already resolves; never to the audited artifact. The artifact is `type: overengineering-findings` and is never `type: review-findings` (see Correction above).
- **No repo-wide sweep.** A bare invocation follows the fallback ladder in the acceptance criteria; it never enumerates the repository.
- **Portable.** Satisfies `docs/PLUGIN-PHILOSOPHY.md` "Design boundary": no dependence on this organization's paths, names, forge, or MCP servers. Consumer-specific evidence tiers are discovered from the consumer's own CLAUDE.md, installed MCP servers, and tool search.
- **One skill.** The no-target discovery behaviour is a mode of `justify`, not a sibling. Listing entry must survive `skill-quality:check listing-budget`.
- **House prose style.** No em dashes in SKILL.md, README, or plugin manifests; `/ai-slop:audit` clean.
- **Repo process.** `scripts/affected-tests.sh --run` before push; PR opened as draft; PR body satisfies `.claude/rules/pr-body-contract.md`; announce to the five sibling sessions before opening the PR (coordination protocol in the ledger).
- **Files this lane does not touch:** `docs/PLUGIN-PHILOSOPHY.md`, `lib/hook-utils.sh` and its copies, `plugins/*/hooks/**`, `docs/conventions/hook-*`, `scripts/check-*.sh`, `docs/adr/**` without prior announcement.

### Acceptance criteria

- ~~`plugins/justification/` exists with `.claude-plugin/plugin.json`, `skills/audit/SKILL.md`, `README.md`, `CHANGELOG.md`, and `skills/audit/evals/evals.json`; `.claude-plugin/marketplace.json` carries the entry with `"category": "quality"`; `docs/CATALOG.md` is regenerated.~~ Superseded by OD1: `plugins/overengineering/skills/justify/SKILL.md` and `skills/justify/evals/evals.json` exist; `plugins/overengineering/context/justification-lane.md` exists; `plugin.json` version is bumped with a matching `CHANGELOG.md` entry; `README.md` lists the fourth skill; `docs/CATALOG.md` is regenerated with the repo's own tooling.
- ~~`skill-quality:check justification` passes~~ `CHECK_SKILL_SKILLS_ROOT=<repo> plugins/skill-quality/scripts/check-skill.sh plugins/overengineering/skills/justify` reports PASS; `check-listing-budget.sh` does not regress.
- `/overengineering:justify <file>` on a named artifact produces a report in which every verdict row carries: one of the six §6 tokens; a `Basis` value from `measured` / `class-inferred` / `unexamined`; the evidence tiers consulted with each marked silent or unavailable when it returned nothing; and, for RETIRE, the search locations and the counterexample shape.
- `/overengineering:justify` with no target does not sweep. It uses conversation context if any exists; otherwise offers git-history discovery of old, low-churn candidates; otherwise asks the operator. The chosen branch is stated in the output.
- An enforcement-kind target produces a finding whose `Routed-to` names `/overengineering:audit`.
- ~~The vendored method file is listed in `scripts/cross-plugin-source-registry.txt`.~~ Superseded by OD4: `findings-artifact.md` declares `schema: 2`, its `Layer` enum carries the five new values, its per-finding table carries `Basis`, and `realign` and `delta` each state they accept schema 2.
- SKILL.md carries a Boundary section naming, by slash handle, the incumbents it defers to: `overengineering:audit`, `code-tidying:audit-dead-code`, `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue`, `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise`, `claude-config:audit-instructions`, `claude-config:unhobble`, `claude-ops:audit-native-overlap`, `improvement:find`; and the scrutiny pairing `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast`.
- `evals/evals.json` includes at least these cases: (a) the `lib/hook-utils.sh` 17-copy vendoring is NOT reported as debt; (b) the 20-of-20 hook-bearing-plugins case is NOT reported as 20 violations (14 are hooks plus their own setup skill; only 6 bundle unrelated skills); (c) a RETIRE row without named search locations is rejected; (d) a fused verdict that does not name its gate is rejected; (e) a bare invocation does not enumerate the repository.
- When the operator's answer to an evidence-tier question is "I don't know", the item is recorded UNPROVEN with the tier named, not resolved either way.

### Captured assumptions

- The operator's phrase "don't make videos" was a dictation slip for: do not conclude an artifact is unjustified merely because its justification is not in the repository. Revisit if the operator corrects the reading.
- ~~Findings conform to the repo's detector-findings convention, as `provenance` and `overengineering` already do.~~ Corrected 2026-09-05: findings are `type: overengineering-findings` per `plugins/overengineering/context/findings-artifact.md`, which deliberately refuses the fix relay. The inline report comes first per the operator's Q8 answer.
- ADR 0003's precision bar governs the no-target discovery mode, because that mode emits candidates over a corpus. Discovery mode ships only after a check on this repository reports its candidate count and how many the operator confirmed as real. Revisit if discovery mode is cut from V1.
- The `overengineering` §6 ladder tokens are stable enough to adopt verbatim. Revisit if `overengineering` changes its ladder; inside one plugin that change and this lane move together.
- V1 is attended-only, derived from the operator's answers to Q7 ("if not 100% sure, ask") and Q8 ("report first, then discuss"). See Q15.
- ~~`justification` is the plugin name.~~ Superseded by OD1/OD2: the handle is `/overengineering:justify <target>`. Revisit if it reads wrongly in use.

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

**What**: Add a third lane skill, `justify`, to `plugins/overengineering/`, binding the existing scrutiny method to a new lane whose item is whatever artifact the operator points at, and extend the shared findings artifact so the lane's verdicts land where `realign` and `delta` already read.
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
| `plugins/overengineering/context/findings-artifact.md` | Frontmatter; Layer vocabulary; Per-finding fields; The stable spine / free prose split | team (plugin-internal contract) |
| `docs/CATALOG-TAXONOMY.md` | Form rule; Assignment principle | team |
| `.claude/rules/vendor-docs-are-not-style.md`, `.claude/rules/pr-body-contract.md` | whole | team (ambient, cited for completeness) |

### Approach

Build technique: **tracer bullet** on the kept slice. There is no viability unknown (the method exists and has two lanes); the risk is integration, so the thinnest working `justify` SKILL.md runs end-to-end on one real target before any polish. Contract changes land first so the lane doc and skill body cite fields that exist. Evals are written before the skill body they grade (test-first; the eval is the skill's observable-behavior spec, per `/tdd:principles` "Test before or after? Before" and "Output-based first").

Order: contract migration (1) → lane binding doc (2) → evals, red (3) → SKILL.md thin slice plus live tracer run, green (4) → plugin surfaces (5) → gate sweep (6).

### Phase 1: Extend the shared findings artifact to schema 2 [TODO]

Contract migration. Pre-flight consumer check is the first work item.

- [ ] **Pre-flight (FIRST):** confirm no script parses the artifact. `grep -rln "overengineering-findings" plugins/ scripts/ --include='*.sh' --include='*.mjs' --include='*.py' --include='*.json'` must return only `plugins/overengineering/skills/realign/evals/evals.json` (an eval mention, not a parser). Consumers are the prose skills `realign` and `delta` only. Record the result in this phase.
- [ ] `context/findings-artifact.md` "Frontmatter": `schema` contract row reads "currently `2`"; keep the stop-on-unrecognized rule.
- [ ] `context/findings-artifact.md` "Layer vocabulary": append `decision-records` · `documents` · `components` · `dependencies` · `source` after `external-integrations`, keeping the "eleventh layer means a schema bump" sentence and noting that the five are the justification lane's layers and route nothing to the enforcement lane.
- [ ] `context/findings-artifact.md` "Per-finding fields": add row `Basis` | Spine: no | Required: always | one of `measured` / `class-inferred` / `unexamined`; a verdict resting on a §2 tier 1-3 citation is `measured`; one resting on §6's non-derivable-oracle clause or a §7 class match without a tier 1-3 citation is `class-inferred`; one where the evidence tiers were not consulted is `unexamined`. State that a KEEP tagged `unexamined` is triage, never a conclusion.
- [ ] `skills/realign/SKILL.md`: where it reads the artifact's `schema`, accept `1` or `2`; on `2`, `Basis` is displayed with the finding and never changes gating.
- [ ] `skills/delta/SKILL.md` and `skills/delta/context/baseline-model.md`: accept schema `1` or `2`; state that `Basis` is prose, outside the spine, and never enters the diff.
- [ ] `skills/audit/SKILL.md`: one sentence that the enforcement lane writes `schema: 2` artifacts from this version and always sets `Basis` (`measured` when a tier 1-3 citation is present, else `class-inferred`).

**File inventory (Phase 1):**

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/overengineering/context/findings-artifact.md` | MODIFY | enum, `Basis` row, `schema: 2` |
| [ ] `plugins/overengineering/skills/realign/SKILL.md` | MODIFY | accept schema 2 |
| [ ] `plugins/overengineering/skills/delta/SKILL.md` | MODIFY | accept schema 2 |
| [ ] `plugins/overengineering/skills/delta/context/baseline-model.md` | MODIFY | `Basis` outside the spine |
| [ ] `plugins/overengineering/skills/audit/SKILL.md` | MODIFY | writes schema 2, sets `Basis` |
| [ ] `plugins/overengineering/context/product-code-lane.md` | KEEP | its layer set is a specification ahead of its skill; not this lane's to change |

**Sanity Check:**

- `grep -c 'decision-records\|documents\|components\|dependencies\|source' plugins/overengineering/context/findings-artifact.md` ≥ 5, and `grep -n 'schema.*currently \`2\`' plugins/overengineering/context/findings-artifact.md` returns one line.
- `grep -n '^| \`Basis\`' plugins/overengineering/context/findings-artifact.md` returns one row whose Spine column is `no`.
- `grep -l 'schema.*2' plugins/overengineering/skills/realign/SKILL.md plugins/overengineering/skills/delta/SKILL.md plugins/overengineering/skills/audit/SKILL.md` lists all three.
- `grep -c $'\xe2\x80\x94' <each modified file>` returns 0 for the lines this phase added (`git diff -U0 | grep '^+' | grep -c $'\xe2\x80\x94'` = 0).

### Phase 2: Lane binding doc `context/justification-lane.md` [TODO]

Mirror `context/product-code-lane.md`'s shape. Supplies the four things "Lane binding" asks for, plus this lane's rules from the Brief. Every bare `§N` is a section of `scrutiny-method.md`.

- [ ] Header paragraph: the method is not restated; this document supplies only the lane's four things; status **shipping** (not specification).
- [ ] §1 Item inventory: the item is what the operator points at, at the granularity pointed at. Aggregating-container rule (link intra-plugin to `../skills/audit/context/surface-walk.md` "Granularity"): a pointed-at file is the container; per-member sub-verdicts only where the file's own structure lists members mechanically (an ADR's numbered decisions, a pipeline's jobs, a manifest's entries).
- [ ] §2 Layer vocabulary and discovery probes, one subsection per layer: `decision-records` (ADRs, decision logs: probe = status line, date, superseding record, citing files); `documents` (markdown and prose docs: probe = inbound links, last substantive commit, whether a generator owns it); `components` (plugins, skills, agents, hooks manifests as units: probe = listing presence, invocation evidence where the consumer records it, catalog entry); `dependencies` (declared packages, pinned tools: probe = import or call sites, lockfile presence, upstream status); `source` (code constructs when no product-code lane skill is installed: probe = call sites and the §3 liveness questions; hands over to the product-code lane when it ships). Enforcement kinds are **not** layers here; they route (Boundary below).
- [ ] §3 Evidence sources mapped onto the §2 tiers, this lane's table: tier 1 runtime or usage records the consumer keeps; tier 2 the introducing commit, its PR and linked issue, churn, revert history (the lane's workhorse); tier 3 incidents; tier 4 operator attestation **and** consumer-installed external context (ticketing, meeting-transcript MCP servers) recorded as attestation with date and source; tier 5 the artifact's own text, ADR rationale, comments. Auto-escalation: consult tiers in order, stop when a verdict is earned, name every tier consulted and whether it was silent or unavailable. **Ask-when-unsure:** when tiers 1-3 are silent and tier 4 could exist, ask the operator whether external context exists before writing UNPROVEN.
- [ ] §4 Protected-class defaults extending §7: accepted ADRs with citing consumers (retirement is a re-decision); license, security, and compliance documents; anything with declared external consumers; the intentionally-dormant class carries directly (a compatibility note with a stated removal date is not a finding).
- [ ] §5 Preflight additions beyond `surface-walk.md` "Preflight": **sanctioning-record probe** (an ADR, convention doc, or registry entry that sanctions the pattern, and a gate that maintains it; `lib/hook-utils.sh` under ADR 0019 is the canonical case, and a sanctioned, gated pattern is never debt); **query-form variation** for every absence claim (line wrap, hyphenation, casing, synonyms; a single-form grep is not a search); **retire-costs-more**: a RETIRE row names the surfaces searched and the counterexample shape, and the lane refuses a RETIRE whose search was one document.
- [ ] §6 The two gates, stated once: the ablation question (would a better model still need this; durable tier exempt) and the earned-keep question (does this configuration earn its carry cost; no class exemption). A row names which it answers; a fused row is a defect. Point at `docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook" and ADR 0003 by title, not path (they are outside the plugin).
- [ ] §7 `Basis` assignment rule, pointing at `findings-artifact.md` "Per-finding fields" for the vocabulary; the rule that `unexamined` KEEPs are triage.
- [ ] §8 Boundary against existing owners (mirrors product-code-lane §6): enforcement kinds → `/overengineering:audit` (sibling, always present); instruction text → `claude-config:audit-instructions` and `claude-config:unhobble`; comments → `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue`; unreachable code → `code-tidying:audit-dead-code`; doc derivability and noise → `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise`; native duplication → `claude-ops:audit-native-overlap`; cross-dimension ranking → `improvement:find`; scrutiny pairing → `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast`. Every non-sibling route is presence-gated with the inline fallback recorded in `Routed-to`.
- [ ] §9 The §10 YAGNI boundary restated for arbitrary artifacts: the remedy is refactor or remove, decided by the operator; the lane never proposes additions.

**Sanity Check:**

- `grep -c '^## ' plugins/overengineering/context/justification-lane.md` ≥ 9.
- Every `§N` cited resolves: `grep -o '§[0-9]\+' plugins/overengineering/context/justification-lane.md | sort -u` is a subset of `grep -o '^## [0-9]\+' plugins/overengineering/context/scrutiny-method.md | grep -o '[0-9]\+'`.
- Every `/plugin:skill` handle in the Boundary section resolves under `plugins/` (the repo's `skill-reference-verify` PostToolUse hook reports zero UNRESOLVED_SKILL on save).
- `markdownlint-cli2 plugins/overengineering/context/justification-lane.md` exit 0; em-dash count 0.

### Phase 3: Evals first, red [TODO]

Write the observable-behavior spec before the skill body. Fixtures are self-contained under `skills/justify/evals/fixtures/` so the cases are portable; no case points at a live repo path.

- [ ] `skills/justify/evals/evals.json`, `skill_name: justify`, cases (ids 1-7):
  1. `bare-invocation-does-not-sweep`: prompt `/overengineering:justify` with no target and no conversation context; expects the fallback ladder stated, git-age discovery **offered** not run, no repository enumeration, no file written.
  2. `pointed-target-full-row`: prompt on `fixtures/adr-0001-sample.md`; expects one finding with all six-token verdict, `Basis`, tiers consulted with silent/unavailable marked, `Layer: decision-records`, `schema: 2` artifact.
  3. `sanctioned-vendoring-is-not-debt`: fixture pair `fixtures/vendored/a/util.sh` and `fixtures/vendored/b/util.sh` byte-identical plus `fixtures/vendored/REGISTRY.txt` sanctioning them; expects KEEP or UNPROVEN, never RETIRE or CONSOLIDATE, with the sanctioning record cited.
  4. `bundled-setup-skill-is-not-a-violation`: fixture `fixtures/plugins-manifest.md` describing 20 hook-bearing plugins of which 14 ship hooks plus their own `setup` skill; expects the report to distinguish the 14 from the 6 and to refuse a 20-violation count.
  5. `retire-without-search-is-refused`: prompt asks for a RETIRE on `fixtures/lonely-doc.md` after "I grepped once"; expects the lane to refuse the RETIRE until search surfaces and query forms are named, recording UNPROVEN meanwhile.
  6. `fused-verdict-is-rejected`: fixture `fixtures/policy-gate.sh` (a deny-gate whose class is policy) with a request to "mark it keep because it is policy"; expects two separately named gate answers (ablation: KEEP class; earned-keep: UNPROVEN or the measured answer) and a refusal to fuse them.
  7. `enforcement-kind-routes-to-audit`: fixture `fixtures/hooks.json`; expects `Routed-to: /overengineering:audit` and no lane-local verdict.
- [ ] Fixtures listed above, each minimal and self-describing.

**Sanity Check:**

- `CHECK_SKILL_SKILLS_ROOT=<repo> bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/overengineering/skills/justify` exit 0 (schema valid; trigger, happy-path, refusal, anti-pattern coverage present).
- Every path in `evals.json` `files[]` exists: `jq -r '.evals[].files[]' … | while read f; do test -f "plugins/overengineering/skills/justify/$f" || echo MISSING $f; done` prints nothing.
- At this point `skills/justify/SKILL.md` does not exist yet: `test ! -f plugins/overengineering/skills/justify/SKILL.md` (red).

### Phase 4: `skills/justify/SKILL.md`, thin slice, then the live tracer run [TODO]

Model on `skills/audit/SKILL.md`'s section order. Composes the method by pointer; restates nothing.

- [ ] Frontmatter: `description` under the per-entry cap, first clause naming the object ("Justify the existence of any artifact you point at…"), quoted triggers ("justify this", "does this need to exist", "why is this here", "is this still valid", "earn its keep", "justify the existence of"), the no-target behaviour, "Not for" the enforcement surface (route to `audit`) and remedies (route to owners); `argument-hint: "<target> | (none: conversation context, then offered git-age discovery, then ask)"`; `user-invocable: true`; `disable-model-invocation: false`; `shell: bash`; `metadata.workflow-stage: anytime`; `metadata.summary`.
- [ ] Pre-computed context: **one** git injection line only (`#1619`): branch via `git symbolic-ref --quiet --short HEAD`.
- [ ] Purpose; the method pointer paragraph (`${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md`) and the lane pointer (`${CLAUDE_PLUGIN_ROOT}/context/justification-lane.md`); Read-only contract (reuse audit's wording by pointer to its section, state the one write).
- [ ] Arguments: `<target>` grammar (path, path:line, path#heading, or a free-text name resolved against the tree with the query-form rule); no target → the ladder: conversation context; else **offer** `git log --diff-filter=A --format='%ad %h %s' -- <root>` age-ranked candidates and wait; else ask. Never enumerate.
- [ ] Before the walk: `surface-walk.md` "Preflight" by intra-plugin link plus the lane's §5 additions.
- [ ] The walk: the per-item loop by link; a pointed target is one item unless the container rule splits it.
- [ ] Verdicts and evidence: §6 verbatim by pointer; `Basis` on every row; the two gates named per row.
- [ ] Intent checkpoints: attended only in V1; report first, then the discussion; reuse `planning:interview` mechanics when installed, inline numbered questions otherwise; "I don't know" → UNPROVEN with the tier named.
- [ ] Neighbor routing and Boundary: the lane's §8 by pointer, with the enforcement route to the sibling stated inline.
- [ ] The report: hand off to `../audit/context/report-template.md`.
- [ ] Gotchas: the absence rule with the `one mechanism per concern` line-wrap incident as the worked example; the recursive-catch case (a never-fires guard whose coverage is relocated, not absent).
- [ ] **Live tracer run:** invoke `/overengineering:justify docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md` in this session. It is the integration probe, not a deliverable; the findings artifact it writes lands in the memory tier and is discarded.

**Sanity Check:**

- `CHECK_SKILL_SKILLS_ROOT=<repo> bash plugins/skill-quality/scripts/check-skill.sh plugins/overengineering/skills/justify` reports PASS with 0 errors.
- `bash scripts/check-skill-precompute-compose.sh --strict --paths plugins/overengineering/skills/justify/SKILL.md` exit 0.
- `bash scripts/check-skill-portability.sh --paths plugins/overengineering/skills/justify/SKILL.md plugins/overengineering/context/justification-lane.md` exit 0.
- Tracer run output contains a `###` finding heading with `**Verdict:**` one of the six tokens, `**Basis:**` one of the three values, `**Layer:** decision-records`; `git status --porcelain` shows no change outside `plugins/overengineering/` and `docs/topics/justify-existence/` (the artifact landed in the memory tier).
- Evals 2, 5, 6, 7 now describe behaviour the body specifies (green by inspection; model-graded runs are the operator's `claude plugin eval` call, out of this plan's mechanical scope).

### Phase 5: Plugin surfaces [TODO]

- [ ] `.claude-plugin/plugin.json`: `version` 0.3.6 → **0.4.0**; description gains one clause naming the justification lane; `keywords` gain `justification`, `justify`, `provenance-currency`.
- [ ] `CHANGELOG.md`: `## [0.4.0]` with `### Added` (the `justify` lane; `justification-lane.md`), `### Changed` (findings artifact schema 2: five layers, `Basis`; `realign`/`delta`/`audit` accept and write schema 2).
- [ ] `README.md`: fourth row in the skill table; line 18 "The shared method all three skills apply" reworded to name no count ("The shared method every skill applies"), so `check-skill-count-claims.sh` has nothing to fail on.
- [ ] `.claude-plugin/marketplace.json`: `overengineering` entry `tags` mirror the new keywords; category stays `quality`.
- [ ] `node scripts/generate-catalog.mjs` to regenerate `docs/CATALOG.md` (never hand-edit the block).

**File inventory (Phase 5):**

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/overengineering/.claude-plugin/plugin.json` | MODIFY | version, description, keywords |
| [ ] `plugins/overengineering/CHANGELOG.md` | MODIFY | `## [0.4.0]` |
| [ ] `plugins/overengineering/README.md` | MODIFY | fourth row; count claim reworded |
| [ ] `.claude-plugin/marketplace.json` | MODIFY | tags |
| [ ] `docs/CATALOG.md` | MODIFY (generated) | regen |
| [ ] `.claude/settings.json` | KEEP | `overengineering@melodic-software` already enabled |
| [ ] `scripts/skill-leaf-name-registry.txt` | KEEP | `justify` collides with no other plugin |

**Sanity Check:**

- `bash scripts/check-changelog-parity.sh --check` exit 0 and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.
- `bash scripts/check-skill-count-claims.sh --check` exit 0.
- `node scripts/generate-catalog.mjs --check` exit 0.
- `bash scripts/check-plugin-catalog-enablement.sh` exit 0; `bash scripts/check-skill-leaf-names.sh --check` exit 0.
- `jq . plugins/overengineering/.claude-plugin/plugin.json .claude-plugin/marketplace.json >/dev/null` exit 0.

### Phase 6: Gate sweep and hand-off to PR [TODO]

- [ ] `bash scripts/affected-tests.sh --run` exit 0 (add `--explain` to record why each suite ran).
- [ ] `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/` shows no regression against the pre-change estimate captured before Phase 4.
- [ ] `/ai-slop:audit` over every file this plan created or modified: zero findings at the default tolerance.
- [ ] Announce the PR to the five sibling sessions per the ledger's coordination protocol (branch, title, file list), **before** opening it.
- [ ] `/source-control:commit` per phase or per coherent group; `/source-control:pull-request create` as **draft**, body to `.claude/rules/pr-body-contract.md`.

**Sanity Check:**

- `bash scripts/affected-tests.sh` (list mode) names ≥1 suite and exits 0; `--run` exits 0.
- `git diff --name-only origin/main...HEAD | grep -vE '^(plugins/overengineering/|docs/topics/justify-existence/|docs/CATALOG.md|.claude-plugin/marketplace.json)$'` prints nothing (no file outside the declared footprint).
- The PR exists as draft with `## Summary`, `## Fix`, `## Verification`, `## Related` non-empty and a leading `No related issue:` or `Closes #` line.

### Files Affected (whole plan, 14 files, 6 create / 8 modify)

| File | Action |
|---|---|
| `plugins/overengineering/context/justification-lane.md` | Create |
| `plugins/overengineering/skills/justify/SKILL.md` | Create |
| `plugins/overengineering/skills/justify/evals/evals.json` | Create |
| `plugins/overengineering/skills/justify/evals/fixtures/**` (≈6 files) | Create |
| `docs/topics/justify-existence/design/design-resolution.md` | Create (done at plan time) |
| `plugins/overengineering/context/findings-artifact.md` | Modify |
| `plugins/overengineering/skills/{audit,realign,delta}/SKILL.md` | Modify |
| `plugins/overengineering/skills/delta/context/baseline-model.md` | Modify |
| `plugins/overengineering/.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md` | Modify |
| `.claude-plugin/marketplace.json` | Modify |
| `docs/CATALOG.md` | Modify (generated) |
| `docs/topics/justify-existence/PLAN.md` | Modify (this file; phase tags) |

### Dependencies

- Depends on: `scrutiny-method.md` "Lane binding" (unchanged), `surface-walk.md` lane-independent sections (unchanged, linked), `report-template.md` (unchanged), `reference/topic-docs.md` for the artifact home (unchanged).
- Depended on by: `realign` and `delta` (schema 2 acceptance is this plan's Phase 1), the catalog generator, the listing-budget estimate.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| New plugin `justification` (interview Q6) | ADR 0017 fixes lanes as sibling skills; requires vendoring three files under a sync gate and a cross-plugin route | ADR 0017 is superseded, or the operator rules the name outweighs the build cost |
| Separate artifact type `justification-findings` | `realign`/`delta` would not consume it, undercutting the reason OD1 was chosen | `realign` grows a multi-type reader, or the lane's verdicts are never meant to be realigned |
| Force targets onto the existing ten layers | A README filed under `agent-instructions` is a false spine value carried forever | never |
| Vendor `scrutiny-method.md` under ADR 0019 | Unnecessary once the skill is intra-plugin | the lane is moved out of the plugin |
| Repo-wide sweep as bare invocation | The operator excluded it; ADR 0003's 23.7% case | the operator asks for a sweep mode and a corpus check reports acceptable precision |

### Test strategy

- Test-first: Phase 3 evals precede the Phase 4 body they grade. Output-based: every case asserts on the report's observable shape (verdict token, `Basis`, tiers, `Routed-to`, absence of a sweep), never on internal steps.
- Test boundaries: `/overengineering:justify <target>` (new, this plan introduces it); the findings artifact at schema 2 (existing contract, modified here); the `Routed-to: /overengineering:audit` route (existing sibling). No other boundary; a boundary picked during implementation that is not named here is a deviation logged to `DEVIATIONS.md` beside this file.
- Static gates as regression suite: `check-skill.sh`, `check-evals-quality.sh`, `check-listing-budget.sh`, `check-skill-precompute-compose.sh --strict`, `check-skill-portability.sh`, `check-changelog-parity.sh` (both modes), `check-skill-count-claims.sh --check`, `generate-catalog.mjs --check`, `check-plugin-catalog-enablement.sh`, `check-skill-leaf-names.sh --check`, `affected-tests.sh --run`, `markdownlint-cli2`, em-dash grep, `/ai-slop:audit`.
- Regression for the migration: `realign` and `delta` bodies name schema 1 and 2 both as accepted (grep); the spine definition is unchanged (`grep -n 'id, layer, artifact, verdict, status' findings-artifact.md` still matches).
- The live tracer run (Phase 4) is the single end-to-end probe; model-graded eval runs are the operator's to schedule via `claude plugin eval` and are not a mechanical gate here.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Description exceeds the per-entry listing cap or regresses the shared budget | Med | Med | Draft to the cap; capture `check-listing-budget.sh` before Phase 4 and compare after; trim trigger phrases before anything else |
| Schema 2 breaks a reader nobody grepped for | Low | High | Pre-flight grep is Phase 1's first item; the migration is prose-only; schema is versioned so a reader that stops does so visibly |
| The five layers prove wrong on a real target during the tracer run | Med | Med | Do not widen in-phase; record the mismatch, stop, and `/planning:plan review` |
| Sibling lanes edit `plugins/overengineering/**` concurrently | Low | Med | No peer declared it; PR announcement before opening; `git fetch` and rebase check at Phase 6 |
| `check-skill-count-claims` fires on README line 18 | High | Low | Reword to name no count in Phase 5 |
| The `Basis` rule invites `class-inferred` KEEPs as the easy default | Med | Med | The lane doc states `unexamined` and `class-inferred` KEEPs are triage; eval 6 rejects the fused shape |

## Blast radius

**MEDIUM.** 14 files, all inside one plugin plus its catalog and marketplace rows; a versioned schema bump on a plugin-internal contract with prose-only consumers; fully reversible by revert. Stress-test triggers matched: "new skill creation that composes other skills" (composes `audit` and `planning:interview`) and a contract change consumed by two sibling skills. Step 4 formal stress-test: **runs**.

## Stress-test summary

Pending Step 3 (fresh-context plan reviewer) and Step 4 (`/planning:devils-advocate`); this section is rewritten with their verified findings before approval.

## Execution shape

**Fully sequential: 1 → 2 → 3 → 4 → 5 → 6.** Phases 3 and 5 are file-disjoint from every other phase and could run in parallel with 2 and 4 respectively, but the independent work is well under 100 LOC each and the whole plan is judgment-heavy prose authored to one voice; parallel agents would multiply token cost for no wall-clock saving worth the coordination. Sequential fallback is the default, so none is needed.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | contract edits to shared prose; wording must match the sibling skills' voice |
| 2 | main-session | the lane doc is the design core; judgment-heavy |
| 3 | main-session | evals encode acceptance criteria; needs the interview context |
| 4 | main-session | the skill body plus a live run that needs the operator present |
| 5 | main-session | small mechanical edits plus a generated file; not worth a dispatch |
| 6 | main-session | gate commands and the PR, which needs the peer announcement |

## Open questions

None at approval time. Q15 (unattended mode) stays deferred in the Brief with a USER-RESERVED arbiter.

## Handoff to implementation

### User-approval gates

- **[FALLBACK, confirm or override]** If `check-skill.sh` fails the per-entry cap on the `justify` description, the implementer trims trigger phrases first and the "Not for" clause second, never the quoted triggers that name the object. Surface the trimmed description before committing.
- **[FALLBACK, confirm or override]** If the Phase 4 tracer run shows a real target that fits none of the five layers, the implementer stops and re-plans via `/planning:plan review` rather than adding a layer in-phase (a layer is a schema-level enum value).
- Any scope expansion beyond the 14 files above.

### Execution shape ([EXEC-SHAPE] tagged)

- `[EXEC-SHAPE]` Contract migration first, evals before the skill body, plugin surfaces after the tracer run.
- `[EXEC-SHAPE]` Sequential, all main-session, as tabled above.
- `[EXEC-SHAPE]` Lane doc filename `context/justification-lane.md`, mirroring `context/product-code-lane.md`.
- `[EXEC-SHAPE]` Version bump 0.3.6 → 0.4.0 (a new skill is a minor bump under the plugin's declared semver).
- `[EXEC-SHAPE]` ADR 0017's `surface-walk.md` extraction is not performed; the lane links the enforcement lane's copy intra-plugin, as `product-code-lane.md` does during the transition.
- `[EXEC-SHAPE]` Sanity-check criteria per phase as written above.

### Mechanical work

- Commit boundaries: one commit per phase (Phase 1 contract; Phase 2 lane doc; Phase 3 evals; Phase 4 skill body; Phase 5 surfaces), each via `/source-control:commit`; PLAN.md phase tags advance in the same commit as the phase.
- Verification checkpoints: each phase's Sanity Check runs green before its commit; Phase 6 runs the whole gate list.
- Sequential fallback: not applicable (already sequential).
- The PR is opened as a draft after the peer announcement; flip to ready when Phase 6 is green.
