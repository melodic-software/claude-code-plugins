# audit-native-overlap

## Brief

### TLDR

- Repair the native-overlap tooling so it reports honestly on Claude Code 2.1.263: the inventory extractor's bundled-skill lane, per-lane integrity, the reverse-parity blind spot, and the seeded-pairs drift.
- Move the marketplace posture from route-only to compose-where-sensible: a skill runs the native surface as a named step when it resolves and layers its own value around it.
- Add a per-row `integration` field (`route`, `wrap`, `suggest`) to the native-surfaces store, separate from `verdict`, and a `suggest` grammar to the native-references convention.
- Degrade gracefully: when a native surface does not resolve, skip the step, report it with the gating axes, offer the enable path, never re-implement the native job.
- Deliver as one parent issue with per-unit sub-issues: the tooling fix first, then claude-ops, then every other plugin holding a store row, one unit in flight at a time.

### Goal

A run of `/claude-ops:audit-native-overlap` on the current Claude Code build tells the truth lane by lane instead of collapsing to `broken`, and the skills this marketplace ships stop competing with the native surfaces they overlap: where a bundled skill does a strict subset of a skill's job, the skill composes it as a step and adds its own value (deeper inventory, reconciliation, its own agents); where a built-in command does related work a skill cannot invoke, the skill tells the user it exists at the moment that matters; and in every session where the native surface is gated, disabled, or absent, the skill still completes its own part and says what it skipped and why.

### Constraints

- A skill never asserts that a native surface is present, absent, enabled, or unavailable. The native-references convention's presence-gate rule holds for every new phrase and body section.
- A skill never invokes a target it cannot identify. Bundled skills: name in the listing plus an advisory description check, skip with a warning on mismatch. Plugin skills (any marketplace, including melodic-software): the namespaced `plugin:skill` form, plus marketplace-qualified provenance from `claude plugin list` when the CLI resolves. Built-in commands: never invoked.
- Whether a session is unattended is declared by the caller, never sniffed. An unattended run records a built-in suggestion in its output instead of asking.
- Verdicts stay human-gated. No component is edited before its store row carries a verdict and an `integration` value.
- The sweep contract stands: one plugin is one unit, closed only when its PR merges green, never two units in flight.
- Every touched description must fit the 1,536-character per-entry cap after baking; trimming existing text to make room is allowed and gated by `/skill-quality:check`.
- Baked text is self-contained: no phrase or Boundary section cites a file outside its own plugin.
- Plain-bullet acceptance criteria (`acceptance_criteria_format` resolved to `free-text` from the default; the repo declares no convention home).

### Acceptance criteria

- `inventory.py --binary-only` on Claude Code 2.1.263 reports integrity `ok` or `degraded` with a non-empty bundled-skill lane, its eval suite passes, and `validated_against` moves to 2.1.263.
- `overlap.py detect` on an inventory with exactly one broken lane exits 3, writes the candidates file, states per-lane floors, and marks only that lane's rows as not re-derivable.
- `overlap.py self-check` flags a frontmatter description that names a bundled surface behind a presence condition without a gate token.
- Every store row carries `integration` with one of `route`, `wrap`, `suggest`; the self-check rejects any other value, rejects `wrap` on a built-in command row, and rejects `wrap` or `suggest` on a session-provided row.
- The generated view renders the `integration` column and `--check` stays in sync.
- The two human-added `audit-skill-visibility` rows appear in `reference/canonical-pairs.json`, and a consumer-repo `detect` proposes them.
- The native-references convention documents three grammars (`route` phrase, `wrap` Boundary section, `suggest` body sentence) with the class table stating which grammar each provenance class may use.
- A wrapped skill, run where the native surface resolves, invokes it as a named step and reports the native result alongside its own.
- A wrapped skill, run where the native surface does not resolve, completes its own part and reports the skipped step naming the four gating axes and the enable path.
- While a bundled skill is present under `skillOverrides: name-only`, the wrapping skill treats it as not resolving.
- A skill with a `suggest` row surfaces the suggestion at the start of the run when the built-in command covers everything the skill does, and at the end when coverage is partial, phrased conditionally.
- Every touched skill passes `/skill-quality:check`, and each sweep unit's plugin takes its version bump and CHANGELOG entry.
- The parent issue quotes the affected store rows, and each sub-issue names its unit and its predecessor.

### Captured assumptions

- The two coverage cases above (native absent, `name-only` override) are the author's proposal; the user approved the Brief as a whole without ruling on them separately. Revisit if a sweep unit finds a third trigger or state the wrapped skill must handle.
- Wrap candidates on the current store are the bundled-skill rows: `doctor` (three rows), `simplify` (two), `run`, `design` (two), and the plugin-backed `security-review`. `code-review` against the CI lane is expected to stay `route` because a CI lane cannot type into a session. Each row's final `integration` value is still a human verdict recorded in the store. Revisit if a row's verdict moves to `superseded`.
- Built-in command rows (`export`, `skill-doctor`) and the `design` access command take `suggest`. Revisit if Claude Code exposes a built-in command through the Skill tool.
- The `skill-doctor` row keeps its `gated` marker on the docs basis (v2.1.252+, absent when feature-flag fetching is skipped); the extractor's `gated: false` reading is a heuristic blind to feature-flag gates. Revisit when the extractor learns to read that gate.
- `design` is two surfaces sharing one name: the canvas bundled skill (the store row) and a gated built-in access command. The row's evidence must name both. Revisit if either is renamed.
- Replace (our skill retired in favor of the native one) is expressed by the existing `superseded` verdict, so `integration` needs no `replace` value. Revisit if a row reaches `superseded` and still needs a runtime relationship.
- The extractor fix targets the 2.1.263 bundle layout, where the readable export map no longer carries `registerBundledSkill:()=>…`; the new registration shape is an implementation finding for the plan. Revisit on the next CLI release that moves `validated_against` again.
- Session-provided rows (`morning`) stay `defer` with `integration: route` withheld until an in-session capture protocol exists.

### Out-of-scope

- Re-implementing any native job inside a marketplace skill as a fallback.
- Retiring any skill under `superseded` in this effort.
- Wrapping or suggesting session-provided skills.
- The improvement items beyond the four broken ones: a `recheck` subcommand for trigger evaluation, a marker-basis field, name-collision keying in `detect`, an apply-time per-entry cap precheck, durable report output from a bare run, and a `reverify` helper. These are filed as follow-up scope in the parent issue, not built here.

### Deferred questions

- none; every registered question closed answered.

## Plan

### Goal

**What:** repair the native-overlap tooling for Claude Code 2.1.263, add the `integration` axis to the store and the `wrap` and `suggest` grammars to the native-references convention, then sweep every plugin holding a store row, one closed unit at a time.
**Why:** the 2026-09-08 run reported `broken` for one stale lookup pattern and could re-derive nothing, and the fleet's skills still compete with the bundled surfaces they overlap instead of composing them.

### Standards grounding

No standards index resolves (`.claude/standards.yaml` absent, `docs/standards/` absent). Inferred from repository context, rung 4 of the ladder: this repository's standards live under `docs/conventions/`. Loaded for the surfaces this plan touches: `native-references` (phrase grammar, Boundary section, self-containment, enforceability tiers), `seam-phrasing` (gate plus fallback plus ownership framing, the install-recipe carve-out), `upstream-drift` (four-part verification records for every upstream fact a body restates), `rendered-views` (markdown is the record; the generated view stays markdown), `invocation-mode` (every touched skill keeps its explicit `disable-model-invocation` key), `topic-docs` (contract slice pruned before merge), and the path rule `.claude/rules/skill-bodies-state-current-rules.md` (bodies state the current rule, never the incident; `## Next` placement). The `standards` convention itself and the two personal layers contributed nothing. Persisting an index at `docs/standards/README.md` is an offer for the user, not a write this plan makes.

### Approach

Nine closed units, executed strictly in sequence per the sweep contract (one plugin is one unit, closed only when its PR merges green, never two in flight). Phases 1 to 3 form the tooling-fix unit. Phase 4 is the policy unit. Phases 5 to 11 are the sweep, one plugin each. Phase 0 files the tracker container that carries the rest.

Build technique: the one viability unknown (recovering bundled-skill registrations from the 2.1.263 layout) was resolved upstream by a throwaway spike during planning. Its findings are stated as facts in Phase 1, so no phase carries a might-abandon risk. The kept slice is Phase 1 itself: a walking skeleton whose sanity check is the real binary reporting a non-empty lane.

Spike findings (2026-09-10, `node_modules/.bin/claude` 2.1.263, Linux): the bundle is a `// @bun @bytecode` layout fragmented into hundreds of printable runs; the readable export map the extractor keys on (`registerBundledSkill:()=>xu`) no longer exists in source text, its name surviving only in a symbol table; bundled-skill registrations are calls to a minified local function (`eo({name:"doctor",aliases:["checkup"],…})`) that sit in runs smaller than the extractor's single-longest-run selection; the built-in command table still sits in the largest run, which is why the builtin lane extracted. Joining every printable run and deriving the registrar identifier from the `doctor` canary registration recovers 36 registrations, 18 with literal names and 18 with hoisted-constant names that the existing constant map resolves once the joined source includes the runs the constants live in.

### Phase 0: File the parent issue and its first sub-issue [TODO]

Executed by `/work-items:decompose` after this plan is approved; the plan fixes the shape so decompose does not re-derive it.

1. **Search before create.** Query open issues for `native-overlap`, `audit-native-overlap`, `native-surfaces`, and `inventory.py 2.1.263`. A match with the same scope is the pivot path: attach this Brief to it as a comment and use it as the parent instead of creating one. Record the search outcome in the sanity check.
2. Create the parent issue carrying the Brief verbatim as its body, opened with the closing-keyword line the PR-body contract expects each sub-issue's PR to cite, and the improvement items from `### Out-of-scope` listed as follow-up scope.
3. Create sub-issue 1 (tooling fix, Phases 1 to 3) only. Later sub-issues are created one at a time when their predecessor unit closes, because each wrap unit's precondition is a store row with a human verdict and an `integration` value, and those are written in Phase 4.

**Sanity Check:**

- The search ran and its result (no match, or the matched issue number) is written into the parent issue body.
- `gh issue view <parent>` shows the body opening with `## Brief` and a `### Out-of-scope` section; exactly one open sub-issue is linked.

### Phase 1: Extractor bundled-skill lane on 2.1.263 [TODO]

Files: `plugins/claude-ops/skills/inventory/scripts/inventory.py` (MODIFY), `plugins/claude-ops/skills/inventory/scripts/test_inventory.py` (MODIFY).

1. **Red.** Add a fixture that mimics the 2.1.263 shape: two printable runs separated by non-printable bytes, the export map absent, registrations as `eo({name:…})` with one canary literal (`name:"doctor",aliases:["checkup"]`) and one hoisted-constant name whose definition sits in the other run. Assert `extract_bundled_skills` resolves both and that `discover_registrar` returning `None` no longer empties the lane.
2. **Green, region selection.** Replace single-longest-run selection with the union of every printable run at or above a floor between the first and last bundle marker, joined with newlines, recorded in `sources.binary` as `runs` and `joined_bytes`. Keep the longest-run path as the fallback when no marker is found.
3. **Green, registrar discovery.** Keep the export-map discovery first. When it returns `None`, derive the registrar from the canary registration (the callee identifier immediately preceding `({name:"doctor",aliases:["checkup"]`). Record which route resolved in `bundled_skill_notes.registrar_route` (`export-map` or `canary`). When neither resolves, the lane is broken with the existing error text.
4. **Refactor.** The constant map builds over the joined source so hoisted names resolve across run boundaries. Unresolved dynamic names stay an advisory floor, as today.
5. Update `VALIDATED_AGAINST` to `2.1.263` only after the evals in Phase 3 pass.

**Sanity Check:**

- `python3 plugins/claude-ops/skills/inventory/scripts/test_inventory.py` exits 0 with the new fixture tests present (`grep -c "canary" test_inventory.py` ≥ 2).
- `python3 plugins/claude-ops/skills/inventory/scripts/inventory.py --binary-only --out /tmp/inv.json` exits 0 and `python3 -c "import json;d=json.load(open('/tmp/inv.json'));assert len(d['bundled_skills'])>=18 and 'doctor' in d['bundled_skills'] and 'simplify' in d['bundled_skills']"` passes.
- `jq -r .integrity.status /tmp/inv.json` prints `ok` or `degraded`, never `broken`.

### Phase 2: Per-lane integrity and honest detect exits [TODO]

Files: `inventory.py` (MODIFY), `test_inventory.py` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` (MODIFY), `plugins/claude-ops/skills/inventory/SKILL.md` (MODIFY, the integrity paragraph), `plugins/claude-ops/skills/audit-native-overlap/SKILL.md` (MODIFY, "The two substrates" and "Detection posture").

Pre-flight consumer check, first work item: `Grep` for `integrity` and `"status"` readers across `plugins/*/skills/*/scripts/*.py`, `plugins/*/hooks/**`, and `scripts/*.sh`; today the known consumers are `overlap.py` (reads `integrity.status`, `cli_version`, `validated_against`) and `scripts/validate-plugins.sh` (reads overlap's exit code only). The change is additive (a new `integrity.lanes` key beside the unchanged top-level `status`), so no consumer breaks; document the parse paths in the commit body.

1. **Red.** `check_integrity` returns `lanes` with one `{status, problems, advisories}` per lane (`builtin_commands`, `bundled_skills`, `plugin_backed`); the top-level `status` is the worst lane. Tests: a broken bundled lane with a healthy builtin lane yields top-level `broken`, lane statuses `ok`/`broken`/`ok`.
2. **Red.** `cmd_detect` on an inventory whose `lanes` show one broken lane exits 3, writes candidates, states per-lane floors in `integrity`, and marks candidates in the broken lane with `re_derivable: false`. Exit 1 is reserved for an unusable inventory (bad schema, missing key, every lane broken). An inventory without `lanes` keeps today's behaviour.
3. **Green** both.
4. Re-word the SKILL.md rule from "if it reports broken, the report carries no native-side counts at all" to per-lane: counts are omitted only for the broken lane; the report names the lane and its cause.

**Sanity Check:**

- `python3 plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` and `python3 plugins/claude-ops/skills/inventory/scripts/test_inventory.py` exit 0.
- A fixture inventory with `lanes.bundled_skills.status == "broken"` makes `overlap.py detect … --out /tmp/c.json` exit 3 and `jq '[.candidates[] | select(.re_derivable == false)] | length' /tmp/c.json` prints a number greater than 0.
- `grep -c "no native-side counts at all" plugins/claude-ops/skills/audit-native-overlap/SKILL.md` prints 0.

### Phase 3: Reverse-parity blind spot, seeded pairs, evals, claude-ops release [TODO]

Files: `overlap.py` (MODIFY), `test_overlap.py` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/reference/canonical-pairs.json` (MODIFY), `plugins/claude-ops/skills/inventory/evals/evals.json` (MODIFY where an expectation names 2.1.228), `plugins/claude-ops/.claude-plugin/plugin.json` (MODIFY), `plugins/claude-ops/CHANGELOG.md` (MODIFY), `docs/conventions/native-references/README.md` (MODIFY, the Enforceability row moves from "candidate check named, not built" to built), `docs/conventions/native-references/CHANGELOG.md` (MODIFY).

1. **Red.** Self-check flags a frontmatter description that names a native surface by class and name behind a presence condition (`bundled|built-in|plugin-backed built-in|session-provided` followed within a few words by `skill|command`, inside a clause starting `when|where|if`) without the gate token. Fixture: the `visualize` wording "where the bundled design skill is available". Negative fixtures: a description carrying the token; a seam-phrasing "if that plugin is installed" clause; a Not-for clause that names a surface with no presence condition.
2. **Green.** The flag is an advisory (exit 3), not a break, because the two live cases are legitimate pending rows; the message names the row to add or the token to use.
3. Seed the two `audit-skill-visibility` pairs (`doctor` bundled-skill, `skill-doctor` builtin-command) into `canonical-pairs.json` with a `why`; `test_shipped_canonical_pairs_file_validates` covers the shape.
4. Re-validate the inventory evals against 2.1.263: run the repo's eval lint (`bash plugins/skill-quality/scripts/check-evals-quality.sh` over the inventory skill) and, where `claude plugin eval` is available in the session, the live suite; update any expectation that names the old build; then set `VALIDATED_AGAINST = "2.1.263"`.
5. Bump `claude-ops` to `0.46.0` (additive `integrity.lanes`, new advisory), write the CHANGELOG entry stating the rules, not the incident.
6. Open the unit's PR as a draft, body per the PR-body contract, quoting the two seeded pairs; flip to ready when green.

**Sanity Check:**

- `python3 overlap.py self-check` exits 3 with exactly two reverse-parity advisories naming `visualization:visualize` and `prototype:explore-directions` (`… self-check 2>&1 | grep -c "presence condition without a gate token"` prints 2).
- `jq '.pairs | length' canonical-pairs.json` prints 16 and `jq '.pairs[] | select(.native.name=="skill-doctor")' canonical-pairs.json` is non-empty.
- `grep -n 'VALIDATED_AGAINST = "2.1.263"' inventory.py` matches; `jq -r .version plugins/claude-ops/.claude-plugin/plugin.json` prints `0.46.0`; `scripts/affected-tests.sh --run` passes.

### Phase 4: Policy unit, the `integration` axis and the two new grammars [TODO]

Files: `docs/native-surfaces/records.json` (MODIFY, every row), `docs/NATIVE-SURFACES.md` (regenerated), `overlap.py` (MODIFY), `test_overlap.py` (MODIFY), `docs/conventions/native-references/README.md` (MODIFY), `docs/conventions/native-references/CHANGELOG.md` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/SKILL.md` (MODIFY, "Verdicts and the human gate", "The apply step"), `plugins/claude-ops/.claude-plugin/plugin.json` and `CHANGELOG.md` (MODIFY).

Pre-flight consumer check, first work item: `Grep` for readers of `records.json` and of the `baked` object; today they are `overlap.py` and the generated view only. The change is additive.

1. **Red.** `validate_row` requires `integration` in `route|wrap|suggest`; rejects `wrap` on a `builtin-command` row; rejects anything but `route` on a `session-skill` row; rejects anything but `route` on a `defer` verdict; `baked` gains a boolean `native_step`, true only with `integration == "wrap"`. Forward parity for `native_step` looks for a `## Native step` heading in the body. Reverse parity gains the `suggest` token (`available in your build`) as a third per-class token.
2. **Green.** Render the view with an `Integration` column in the summary table and an `Integration:` line per row.
3. **Convention.** Add the `wrap` grammar (body section `## Native step, <name> (<class>)` carrying: the gate token, the identity check by class, the invocation form, what our part adds before or after, the skip-and-report contract naming the four gating axes and the enable path) and the `suggest` grammar (body sentence `If /<command> is available in your build (<basis>), run it for <job>.`, placed at the start when coverage is total and at the end when partial; unattended runs record it in output). Add the class table: bundled-skill and plugin-backed-builtin take `route` or `wrap`; builtin-command takes `route` or `suggest`; session-skill takes `route`. Bump the convention's minor version and write its CHANGELOG entry.
4. **Human verdict pass.** Propose an `integration` value per row in the PR body and write it only as the user confirms: `wrap` for the seven bundled-skill and plugin-backed rows, `route` for `code-review`, `morning`, and the two `playground` rows, `suggest` for `export` and `skill-doctor`, and `route` for the `design` rows unless the user chooses `wrap` for a gated preview. Each row's evidence gains the two substrate observations from the 2026-09-08 report where they apply (`skill-doctor` gate basis; `design` name collision).
5. Update the apply step in the skill body: preconditions add "the row's `integration` is not `route`-only pending", the emitted artefacts add the Native step section and the suggest sentence, and the per-entry cap precheck is stated as a hard precondition (`description` plus `when_to_use` after baking ≤ 1,536 characters, measured with the skill-quality check).
6. Bump `claude-ops` to `0.47.0`; draft PR; ready when green.

**Sanity Check:**

- `python3 overlap.py self-check` exits 0 or 3 with no problems; `jq '[.rows[] | select(.integration == null)] | length' docs/native-surfaces/records.json` prints 0; `python3 overlap.py generate --check` exits 0.
- `grep -c "## Native step" docs/conventions/native-references/README.md` ≥ 1 and `grep -c "available in your build" docs/conventions/native-references/README.md` ≥ 1.
- `jq '[.rows[] | select(.native.class=="builtin-command" and .integration=="wrap")] | length' records.json` prints 0.

### Phase 5: Sweep unit, claude-ops [TODO]

Files: `plugins/claude-ops/skills/audit-install-state/SKILL.md`, `audit-skill-visibility/SKILL.md`, `audit-performance/SKILL.md` (MODIFY), `records.json` and the view (baked flags), `plugins/claude-ops/.claude-plugin/plugin.json` and `CHANGELOG.md` (MODIFY). `morning-brief` is KEEP (defer row).

1. `audit-install-state`: replace the route-only Boundary with a `## Native step, doctor (bundled skill)` section that invokes `doctor` when it resolves (identity: name in the listing, alias `checkup` where the Skill tool resolves it, advisory description check, skip with a warning on mismatch), runs its own inventory after, reports the native result beside its own, and on absence reports the skip naming the four gating axes and the `skillOverrides`/`DISABLE_DOCTOR_COMMAND` enable path. The description phrase stays.
2. `audit-skill-visibility`: same wrap for `doctor`; a `suggest` sentence for `/skill-doctor` at the start of the run (its coverage of "unused versus cost" is the whole ask when the user wants only that list) phrased conditionally with the v2.1.252 and feature-flag basis; unattended runs record it.
3. `audit-performance`: trim the description below the cap first (target ≤ 1,380 characters so the phrase fits), then add the phrase and the `## Native step, doctor` section for the health-and-fix pass only.
4. Set `baked` flags on the four rows; regenerate the view; run `/skill-quality:check` per touched skill; bump to `0.48.0`; draft PR quoting the four store rows; ready when green.

**Sanity Check:**

- `bash plugins/skill-quality/scripts/check-skill.sh` passes for each of the three skills, and `python3 scratch/desc_lengths.py` (or the skill-quality per-entry check) shows every touched `description` ≤ 1,536.
- `python3 overlap.py self-check` exits 0 or 3 with no problems; `grep -c "## Native step" plugins/claude-ops/skills/audit-install-state/SKILL.md` prints 1.
- In a session where `doctor` does not resolve, invoking `/claude-ops:audit-install-state` produces a report that contains the string "did not resolve in this session" and the four axes; recorded as a transcript excerpt in the PR body.

### Phase 6: Sweep unit, code-tidying [TODO]

Files: `plugins/code-tidying/skills/tidy/SKILL.md`, `batch-simplify/SKILL.md` (MODIFY), `records.json` and the view, `plugins/code-tidying/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. `batch-simplify`: `## Native step, simplify (bundled skill)` invoking `simplify` per file group when it resolves, our batching and ordering around it; skip-and-report on absence.
2. `tidy`: phrase plus Native step invoking `simplify` on the lane's changed files after the structural tidyings, where the row's human verdict is `wrap`; else phrase only.
3. Baked flags, view, skill-quality, minor bump, draft PR, ready when green.

**Sanity Check:**

- skill-quality check passes for both skills; self-check clean; `grep -c "## Native step" plugins/code-tidying/skills/batch-simplify/SKILL.md` prints 1.

### Phase 7: Sweep unit, testing [TODO]

Files: `plugins/testing/skills/run-e2e/SKILL.md` (MODIFY), `records.json` and the view, `plugins/testing/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. `run-e2e`: phrase plus `## Native step, run (bundled skill)` that launches the app through `run` when it resolves and layers evidence capture (screenshots, responses, logs) on top; skip-and-report on absence, falling back to the skill's own launch playbook.
2. Baked flags, view, skill-quality, minor bump, draft PR, ready when green.

**Sanity Check:**

- skill-quality check passes; self-check clean; the Native step section names all four gating axes (`grep -c "plan" …` is not enough, so assert the literal list line via `grep -c "settings or environment, plan, platform or provider, host surface"` prints 1).

### Phase 8: Sweep unit, review [TODO]

Files: `plugins/review/skills/security-review/SKILL.md` (MODIFY if the human verdict is `wrap`; else KEEP), `plugins/review/skills/code-review/SKILL.md` (phrase only, `route`), `records.json` and the view, `plugins/review/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. `security-review`: where the row is `wrap`, a Native step that runs the plugin-backed `security-review` on the PR head as its first pass and layers the lane's logic and Actions findings; where the CI lane cannot invoke skills, the row stays `route` and the phrase alone is baked. This is decided at the Phase 4 human verdict pass, not here.
2. `code-review`: phrase only.
3. Baked flags, view, skill-quality, minor bump, draft PR, ready when green.

**Sanity Check:**

- skill-quality check passes for both; self-check clean; `jq '.rows[] | select(.component.skill=="code-review") | .integration' records.json` prints `"route"`.

### Phase 9: Sweep unit, visualization [TODO]

Files: `plugins/visualization/skills/visualize/SKILL.md` (MODIFY), `records.json` and the view, `plugins/visualization/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. Bring the description's "where the bundled design skill is available" under the gate token so the reverse-parity advisory from Phase 3 closes; set `baked.description_phrase`.
2. Where the `design` row is `wrap`, add a Native step for the canvas that invokes `design` when it resolves and reports the preview gate on absence; where `route`, the existing Boundary is kept and the `design-sync` row stays `defer`.
3. Baked flags, view, skill-quality, minor bump, draft PR, ready when green.

**Sanity Check:**

- `python3 overlap.py self-check 2>&1 | grep -c "visualization:visualize"` prints 0; skill-quality check passes.

### Phase 10: Sweep unit, prototype [TODO]

Files: `plugins/prototype/skills/explore-directions/SKILL.md` (MODIFY), `records.json` and the view, `plugins/prototype/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. Same treatment as Phase 9 for the `design` row; the existing `playground` phrase (`installed from its marketplace`) is untouched.
2. Baked flags, view, skill-quality, minor bump, draft PR, ready when green.

**Sanity Check:**

- `python3 overlap.py self-check 2>&1 | grep -c "prototype:explore-directions"` prints 0; skill-quality check passes.

### Phase 11: Sweep unit, session-flow [TODO]

Files: `plugins/session-flow/skills/clean-stop/SKILL.md`, `handoff/SKILL.md`, `retro/SKILL.md` (MODIFY), `records.json` and the view, `plugins/session-flow/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. Re-phrase the three existing `/export` suggestion sites to the `suggest` grammar (conditional wording with the basis; end-of-run placement, which is where they already sit); unattended runs record the suggestion.
2. Set `baked.boundary_section` false and a new evidence line naming the three sites; `integration: suggest` was written in Phase 4.
3. View, skill-quality, minor bump, draft PR, ready when green.

**Sanity Check:**

- `grep -c "available in your build" plugins/session-flow/skills/clean-stop/SKILL.md` ≥ 1; skill-quality check passes for the three skills; self-check clean.

### Files affected (whole plan)

| File | Action | Phase |
|---|---|---|
| `plugins/claude-ops/skills/inventory/scripts/inventory.py` | MODIFY | 1, 2, 3 |
| `plugins/claude-ops/skills/inventory/scripts/test_inventory.py` | MODIFY | 1, 2 |
| `plugins/claude-ops/skills/inventory/evals/evals.json` | MODIFY | 3 |
| `plugins/claude-ops/skills/inventory/SKILL.md` | MODIFY | 2 |
| `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` | MODIFY | 2, 3, 4 |
| `plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` | MODIFY | 2, 3, 4 |
| `plugins/claude-ops/skills/audit-native-overlap/reference/canonical-pairs.json` | MODIFY | 3 |
| `plugins/claude-ops/skills/audit-native-overlap/SKILL.md` | MODIFY | 2, 4 |
| `docs/native-surfaces/records.json` | MODIFY | 4, 5 to 11 |
| `docs/NATIVE-SURFACES.md` | REGENERATE | 4, 5 to 11 |
| `docs/conventions/native-references/README.md`, `CHANGELOG.md` | MODIFY | 3, 4 |
| `plugins/claude-ops/.claude-plugin/plugin.json`, `CHANGELOG.md` | MODIFY | 3, 4, 5 |
| `plugins/claude-ops/skills/{audit-install-state,audit-skill-visibility,audit-performance}/SKILL.md` | MODIFY | 5 |
| `plugins/claude-ops/skills/morning-brief/SKILL.md` | KEEP | 5 |
| `plugins/code-tidying/skills/{tidy,batch-simplify}/SKILL.md` plus manifest and CHANGELOG | MODIFY | 6 |
| `plugins/testing/skills/run-e2e/SKILL.md` plus manifest and CHANGELOG | MODIFY | 7 |
| `plugins/review/skills/{code-review,security-review}/SKILL.md` plus manifest and CHANGELOG | MODIFY | 8 |
| `plugins/visualization/skills/visualize/SKILL.md` plus manifest and CHANGELOG | MODIFY | 9 |
| `plugins/prototype/skills/explore-directions/SKILL.md` plus manifest and CHANGELOG | MODIFY | 10 |
| `plugins/session-flow/skills/{clean-stop,handoff,retro}/SKILL.md` plus manifest and CHANGELOG | MODIFY | 11 |
| `scripts/validate-plugins.sh` | KEEP (exit-code contract unchanged) | 2 |

### Test strategy

TDD throughout, Red-Green-Refactor per work item. Test boundaries, all existing public interfaces:

- `inventory.py` functions `extract_bundled_skills`, `discover_registrar`, `check_integrity`, and the bundle-region selector, driven by `test_inventory.py` with synthetic bundles (existing pattern) plus one fragmented-run fixture; the real binary is the Phase 1 sanity check, not a unit test.
- `overlap.py` functions `validate_row`, `check_baked_parity`, `cmd_detect`, `cmd_self_check`, `render_view`, driven by `test_overlap.py`'s `TempRepo` fixture (existing pattern).
- Skill bodies are verified by `plugins/skill-quality/scripts/check-skill.sh` per touched skill and by `overlap.py self-check` parity, both deterministic.
- Behavioural criteria (the wrapped skill degrading in a session without the surface) are verified once per unit by a live invocation in this cloud session, where `doctor` does not resolve, with the transcript excerpt quoted in the PR body.
- `scripts/affected-tests.sh --run` closes every unit before its PR.

Test type per change: unit for the Python engines, contract for the store and view, static for skill bodies, one manual runtime probe per unit for the degradation path. No test is skipped, disabled, or quarantined to reach green.

### Alternatives considered

- **Fix the extractor by keying on the symbol-table entry for `registerBundledSkill`.** Rejected: the symbol table names the function but does not locate the calls. Switch condition: a build where the canary registration disappears but the export map returns.
- **Fold the policy unit into the tooling-fix PR.** Rejected: mixes a repair with a routing-policy change and hides the human verdict pass inside a bug fix. Switch condition: the user prefers one review over two.
- **Reuse the `resolves in your session` token for `suggest`.** Rejected: a built-in command never appears in the model's listing, so the token's read-time meaning does not hold; `available in your build` says what the model can actually not know. Switch condition: Claude Code starts listing built-in commands to the model.
- **Wrap every bundled row uniformly, no human pass.** Rejected by the Brief.
- **Run the sweep as parallel per-plugin agents.** Rejected: the sweep contract forbids two units in flight because description edits are routing-affecting. Switch condition: the contract is amended.

### Risks and mitigations

- **A later CLI release changes the registration shape again.** The two-route discovery (export map, then canary) plus per-lane integrity makes the failure a named broken lane, not a silent short list. Mitigation is the existing eval re-validation trigger.
- **The Skill tool may not resolve a bundled skill by alias.** Phase 5 verifies alias invocation in a live session before relying on it; the fallback is name plus advisory description. `[FALLBACK, confirm or override]`
- **The reverse-parity heuristic produces false positives on prose.** It is an advisory, keyed on a class word plus `skill|command` inside a presence clause, with negative fixtures for seam-phrasing and Not-for clauses.
- **Trimming `audit-performance`'s description loses trigger phrases.** The skill-quality trigger-phrase check runs against HEAD and reports drops; the PR body lists every removed phrase.
- **Nine sequential PRs take weeks.** Accepted by the Brief; the parent issue tracks progress and each unit is independently valuable.

## Blast radius

MEDIUM. Files: over 30 across eight plugins and two conventions. Other sessions: the store, the generated view, and `validate-plugins.sh` are shared CI surfaces, but the exit-code contract is unchanged and every change is additive. Reversible by git revert per unit. Two stress-test triggers match: a new convention grammar (constrains future skill authoring) and a multi-step implementation touching undocumented binary layout.

## Stress-test summary

Pending: fresh-context plan review (Step 3) and `/planning:devils-advocate` (Step 4) run before presentation; findings and fixes are recorded here.

## Execution shape

Fully sequential. Phase 0 gates everything; Phases 1 to 3 share `inventory.py` and `overlap.py`; Phase 4 gates every sweep unit because it writes the `integration` values the apply step requires; Phases 5 to 11 are serialized by the sweep contract. No parallel wave is recommended. `[EXEC-SHAPE]`

| Phase | Surface | Basis |
|---|---|---|
| 0 | main session via `/work-items:decompose` | tracker write with a search-before-create pivot |
| 1 to 3 | main session | judgment-heavy: binary layout, integrity semantics, evals |
| 4 | main session | human verdict pass row by row |
| 5 to 11 | main session, or one sub-agent worker per unit with the unit's SKILL.md files as its ALLOWED list and `records.json`, `PLAN.md`, other plugins FORBIDDEN | mechanical per unit once the grammar exists; still one unit at a time |

Sequential fallback: not applicable, the shape is already sequential.

## Open questions

- Phase 8: whether the CI `security-review` lane can invoke the plugin-backed skill at all, decided at the Phase 4 verdict pass with a live check of the lane's workflow permissions. **arbiter: USER-RESERVED**
- Phase 9 and 10: `wrap` versus `route` for the gated `design` canvas rows. **arbiter: USER-RESERVED**

## Handoff to implementation

### User-approval gates

- Every `integration` value written in Phase 4 (the human verdict pass; the plan proposes, the user confirms row by row).
- Any description trim that drops a trigger phrase reported by the skill-quality check (Phase 5, `audit-performance`).
- The alias-invocation fallback in Phase 5 if alias resolution fails.
- Creating each sweep sub-issue after its predecessor closes.

### Execution shape ([EXEC-SHAPE] tagged)

- Policy schema as its own unit (Phase 4) rather than inside the tooling fix.
- `available in your build` as the `suggest` token.
- `baked.native_step` as the third baked flag.
- Unit order after claude-ops: code-tidying, testing, review, visualization, prototype, session-flow (row count, then value of the wrap, then least-gated surface first).
- Minor version bump per unit for every touched plugin (additive changes).

### Mechanical work

- One draft PR per unit, body per the PR-body contract, closing keyword pointing at the unit's sub-issue, affected store rows quoted.
- Before each push: `scripts/affected-tests.sh --run`, `python3 overlap.py self-check`, `python3 overlap.py generate --check`, `check-skill.sh` per touched skill, markdownlint on touched markdown.
- The contract slice `docs/topics/audit-native-overlap/` is pruned in the final commit of the last unit's PR per the topic-docs convention.
- Phase tags advance `[TODO]` to `[DOING]` to `[DONE]` in this file, edited only from the main session.
