# Native overlap: fix the tooling, then route to compose

## Status (graduated 2026-09-11)

This is the approved plan for the native-overlap effort tracked in
melodic-software/claude-code-plugins#4047, graduated from the topic slice
`docs/topics/audit-native-overlap/` when unit 1 shipped, so the remaining units have a durable
contract to resume from. The design resolution it references is
[`native-overlap-integration-design.md`](native-overlap-integration-design.md). The interview
ledger and plan checklist lived in the gitignored memory tier and are not graduated; every decision
they held is in `## Brief`, `## Open questions`, and Phase 4 below.

- Unit 1 (#4048) shipped in #4092: Phases 1 to 3 are done, with each phase's deviations recorded
  under its heading. The audit-native-overlap description was trimmed under the 1,024-character
  Skills API cap in the same PR, so Phase 5 no longer owns that finding.
- Main moved while unit 1 was in flight. The native-references convention reached 1.1.0 (#4058):
  every non-`defer` extraction row lands with a Boundary section naming its surface as a code span,
  the overlap self-check fails (exit 1) on a row without one, Boundary-only baking may batch across
  plugins, and those sections were baked across code-tidying, review, testing, visualization,
  prototype, and claude-ops. Three `claude-api` rows were added (`claude-config:audit-instructions`,
  `evals:methodology`, `playbooks:fable-5`), so the store holds 19 rows.
- Consequences for the remaining units, to apply when unit 2 starts: Phase 4's major bump builds
  on 1.1.0, not 1.0.1, and keeps its Boundary-section rule; the Phase 4 row count is 21 (19 plus
  the two `export` rows), and the three `claude-api` rows take an `integration` value at the Phase
  4 gate (`route` on today's evidence: each component already owns its job and carries its
  Boundary section); the sweep units' Boundary work is already done, so each unit is its
  description phrase, Native step, or suggest sentence only, and Phase 5 through Phase 11 shrink
  accordingly.
- Units 2 to 9 are deferred as filed (#4049 to #4056) with the notes above recorded on each issue.
  Unit 2 is C4 (`work-class: structural`, `needs-human`); a person reviews and merges it.

## Brief

**Spec container:** melodic-software/claude-code-plugins#4047

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

Scope note, 2026-09-10, added at planning after the fresh-context review: three statements about `defer` rows disagreed (the assumption above says `route` is withheld for `morning`, the acceptance criterion says every row carries `integration`, and the plan's verdict pass proposes `route`). The acceptance criterion is the stronger, approved statement, so every row carries `integration`, `morning` included, with `route` as the only value a `defer` row may take. The assumption's "withheld" is superseded by this note.

Scope note, 2026-09-10, added at planning after the devil's-advocate pass: the wrap-candidate assumption above rests on model-invocability that the 2.1.263 binary contradicts. Each bundled-skill registration carries an invocation-control field, and `doctor`, `design`, `design-sync`, `batch`, `debug`, and `run-skill-generator` are registered with model invocation disabled, which the official skills reference defines as "Claude cannot invoke" and this repository's invocation-mode convention restates as "cannot be invoked by any other skill". `simplify` and `run` are registered model-invocable. So the three `doctor` rows and the two `design` rows cannot take `wrap` on any host; their available integrations are `route` and `suggest`. This changes which rows the sweep can compose and is the user's decision, recorded under `## Open questions` as USER-RESERVED, not resolved here.

Scope note, 2026-09-11, added after the round-4 re-interview and its two-validator research pass (independent fresh-context Fable 5.1 and Opus agents against the official skills, commands, settings-reference, sub-agents, env-vars, and errors references, the 2.1.263 binary bytes, and this repository's conventions): the previous scope note over-reads `design`. On 2.1.263 the name `design` carries two bundled-skill registrations: the design canvas skill (registered by `registerDesignCanvasSkill`, `userInvocable`, no invocation-control field, so model-invocable, gated on the artifact capability) and the claude.ai/design hub (registered model-disabled, gated on a design-sync entitlement), plus a `local` access command. Both `design` store rows describe the canvas, which is model-invocable and present in this session's own roster, so those rows do not carry `model-invocation-disabled` and `wrap` is admissible for them; the user's accepted value is `route` on job merits (both components already own their artifact-producing job, so there is no sub-step to wrap), revisitable in Phases 9 and 10. The `doctor` rows stand as model-disabled. The marker must therefore be keyed per registration, not per name, which Phase 1 now carries. The assumption above that built-in commands are never exposed through the Skill tool has also fired on its premise: the official skills reference exposes `/init` and `/security-review` through the Skill tool, so reach is a per-surface property the store records as evidence, and the class rules are a floor, not the determinant. The `export` and `skill-doctor` rows still take `suggest` because those two commands are non-prompt command types the Skill tool never lists.

### Out-of-scope

- Re-implementing any native job inside a marketplace skill as a fallback.
- Retiring any skill under `superseded` in this effort.
- Wrapping or suggesting session-provided skills.
- The improvement items beyond the four broken ones: a `recheck` subcommand for trigger evaluation, a marker-basis field, name-collision keying in `detect` (the bundled-vs-bundled case moved into Phase 1 on 2026-09-11; the seeded-vs-observed case stays here), an apply-time per-entry cap precheck, durable report output from a bare run, and a `reverify` helper. These are filed as follow-up scope in the parent issue, not built here.
- Two follow-ups surfaced by the 2026-09-11 validation, filed on the parent issue: `/verify` has no store row although it is the closest bundled analogue to `testing:run-e2e` and `verification:confirm` (candidate pairs `verify` x `testing:run-e2e` and `verify` x `verification:confirm`; it is model-disabled by a flag-driven field, so `suggest` at most); and a Native step identity check cannot see behaviour drift under a correct identity (the `simplify` two-prompt split), so a post-step assertion on what the surface reported doing is a candidate grammar addition.

### Deferred questions

- none; every registered question closed answered.

## Plan

### Goal

**What:** repair the native-overlap tooling for Claude Code 2.1.263, add the `integration` axis to the store and the `wrap` and `suggest` grammars to the native-references convention, then sweep every plugin holding a store row, one closed unit at a time.
**Why:** the 2026-09-08 run reported `broken` for one stale lookup pattern and could re-derive nothing, and the fleet's skills still compete with the bundled surfaces they overlap instead of composing them.

### Standards grounding

No standards index resolves (`.claude/standards.yaml` absent, `docs/standards/` absent). Inferred from repository context, rung 4 of the ladder: this repository's standards live under `docs/conventions/`. Loaded for the surfaces this plan touches: `native-references` (phrase grammar, Boundary section, self-containment, one owning description per plugin, enforceability tiers, versioning rule), `seam-phrasing` (gate plus fallback plus ownership framing, the install-recipe carve-out, and the owner of any wrap of a marketplace plugin), `upstream-drift` (four-part verification records for every upstream fact a body restates), `rendered-views` (markdown is the record; the generated view stays markdown), `invocation-mode` (every touched skill keeps its explicit `disable-model-invocation` key; a model-disabled skill cannot be invoked by another skill), `topic-docs` (contract slice pruned before merge), the path rule `.claude/rules/skill-bodies-state-current-rules.md` (bodies state the current rule, never the incident; `## Next` placement), and `.claude/rules/vendor-docs-are-not-style.md` (no em dashes in instruction surfaces). The `standards` convention itself and the two personal layers contributed nothing. Persisting an index at `docs/standards/README.md` is an offer for the user, not a write this plan makes.

### Approach

Nine closed units, executed strictly in sequence per the sweep contract (one plugin is one unit, closed only when its PR merges green, never two in flight). Phases 1 to 3 form the tooling-fix unit. Phase 4 is the policy unit and settles every verdict, with its pre-flights, before any sweep unit starts. Phases 5 to 11 are the sweep, one plugin each. Phase 0 files the tracker container that carries the rest.

Build technique: the one viability unknown (recovering bundled-skill registrations from the 2.1.263 layout) was resolved by two throwaway probes during planning, the second of which corrected the first. The kept slice is Phase 1: a walking skeleton whose sanity check is the real binary reporting the named surfaces the store depends on.

Probe findings (2026-09-10, `node_modules/.bin/claude` 2.1.263, Linux ELF): the bundle is a `// @bun @bytecode` layout fragmented into thousands of printable runs; the CJS getter shape the extractor keys on (`registerBundledSkill:()=>xu`) is gone, replaced by an ESM export list (`eo as registerBundledSkill`) that names the registrar directly; bundled-skill registrations are calls to that minified function (`eo({name:"doctor",aliases:["checkup"],…})`) scattered across runs as small as 1.3 KB, so a size floor of 64 KiB recovers 13 names while a 256-byte floor recovers 33; a global constant map over the joined source produced one phantom name (`ehrpd`, a telecom string bound to a same-named identifier in an unrelated chunk), so constants resolve within their own chunk only; the built-in command table sits in the largest run, which is why the builtin lane extracted. Every registration carries `userInvocable` and `disableModelInvocation` fields; `doctor`, `design`, `design-sync`, `batch`, `debug`, and `run-skill-generator` are model-disabled, `simplify` and `run` are model-invocable, and `doctor` also carries `terminalOriented`, the documented-by-code reason it is absent on web and cloud hosts. A 256-byte regex floor runs in about 3 seconds on the 215 MB file; a 64 KiB floor takes minutes because the regex backtracks on every shorter run.

Literals every unit's sanity check greps for, fixed here so the grammar and the checks agree:

- Wrap heading: `## Native step: <name> (<class>)`, for example `## Native step: simplify (bundled skill)`.
- Suggest sentence shape: `If /<name> is available in your session (<basis>), run it for <job>.` The reverse-parity scan keys on the shape `If /` … `is available in your session (`, never on the bare phrase, because that phrase already occurs in unrelated prose in the fleet.
- Axis line, verbatim in every skip report: `settings or environment, plan, platform or provider, host surface`.
- Skip report opener: `did not resolve in this session`.
- Unattended declaration: the bare argument `unattended`, following the `overengineering:audit` precedent.
- Version bumps: "next minor at PR time" for every touched plugin; no literal numbers, because claude-ops receives unrelated PRs weekly.

### Phase 0: File the parent issue and its sub-issues [DONE]

Executed by `/work-items:decompose` after this plan is approved; the plan fixes the shape so decompose does not re-derive it.

Done 2026-09-10: container #4047; sub-issues #4048 (unit 1, tooling fix), #4049 (unit 2, policy), #4050 (claude-ops), #4051 (code-tidying), #4052 (testing), #4053 (review), #4054 (visualization), #4055 (prototype), #4056 (session-flow), each attached as a native sub-issue of #4047 and each naming its predecessor in its `## Blocked by` section. Deviation: the native blocked-by dependency edges were not written, because the session's GitHub token could not drive the tracker seam and the GitHub MCP surface exposes no dependency verb; the edges are body text only until a session with seam access runs `link-blocks` for the eight predecessor pairs.

1. **Search before create.** Query open issues for `native-overlap`, `audit-native-overlap`, `native-surfaces`, and `inventory.py 2.1.263`. A match with the same scope is the pivot path: attach this Brief to it as a comment and use it as the parent instead of creating one. Record the search outcome in the sanity check.
2. Create the parent issue: body is the Brief verbatim, followed by a `## Affected store rows` section quoting every row of `docs/native-surfaces/records.json` by native name, component, verdict, and current `integration` (or `pending` before Phase 4), and a `## Follow-up scope` section listing the improvement items from `### Out-of-scope` plus the two tooling findings the devil's-advocate pass surfaced that the tooling unit does not absorb (the registrar-export advisory's blindness to the ESM form, and phantom constant names). Sub-issue PRs cite their sub-issue with the closing keyword the PR-body contract expects; the issue body itself carries no closing keyword.
3. Publish all nine sub-issues at once with native dependency edges, blockers-first, each blocked on its predecessor, so the sweep contract's one-unit-in-flight rule is carried by the edges rather than by withholding issues. Sub-issues 3 to 9 name their unit as "integration values written in Phase 4 decide the unit's content".

**Sanity Check:**

- The search ran and its result (no match, or the matched issue number) is written into the parent issue body.
- `gh issue view <parent> --json body -q .body | grep -c "## Affected store rows"` prints 1 and `… | grep -c '`doctor`'` prints at least 3; nine linked sub-issues exist and eight of them are blocked.

### Phase 1: Extractor bundled-skill lane on 2.1.263 [DONE]

Done 2026-09-11. Deviation from step 3 as planned: bundle markers are not module boundaries in the bytecode layout (the hoisted name constants sit about 8.7 MB and 173 marker occurrences ahead of their registrations, measured on 2.1.263), so a marker-scoped constant map resolves nothing. The rule built instead is locality: a computed name resolves to its nearest preceding `ident="kebab"` binding, a farther binding never wins over a nearer one (the `ehrpd` phantom is the negative fixture), a single-character identifier is trusted only within a 64 KiB window (which recovers the design canvas `var r="design"` and refuses a loop variable bound megabytes away), and a loop or template-literal registration is a `dynamic_roster` note. A call to the registrar identifier whose object carries no `name:` is another module's function and is counted apart. Measured wall clock on this container: about 14 seconds (region pass 4 s, brace map 5 s, name resolution 2 s), so the sanity bound below is 30 seconds, not 15.

Files: `plugins/claude-ops/skills/inventory/scripts/inventory.py` (MODIFY), `plugins/claude-ops/skills/inventory/scripts/test_inventory.py` (MODIFY).

1. **Red, region selection.** `read_bundle` gets its first unit tests, driven with bytes fixtures: (a) a marker followed by a run above 1 MB carrying only command registrations, then non-printable bytes, then a 2 KB run carrying `eo({name:"doctor",aliases:["checkup"]…})`, then a third run carrying the hoisted constant for a second registration; assert the returned source contains all three. (b) The same layout wrapped in a PE-shaped container (an `MZ` header). (c) The legacy single-run layout still returns the same source as today. (d) A registration in a run smaller than the floor is either recovered or counted in `sources.binary.runs_below_floor`, never silently lost.
2. **Red, registrar discovery.** Three fixtures, one per route: the CJS getter (`registerBundledSkill:()=>xu`), the ESM export list (`eo as registerBundledSkill`), and neither of those but the canary present. `bundled_skill_notes.registrar_route` reads `export-map`, `esm-export`, or `canary`; with none, the lane is broken with the existing error text.
3. **Red, constant resolution.** A constant bound in one chunk and reused as a registration name in another chunk resolves only when the binding sits in the same chunk (between consecutive bundle markers); the `ehrpd` shape (same identifier bound to a different string in an unrelated chunk) is a negative fixture; identifiers of length 1 are always unresolved; a loop registration (`for(… of …)eo({name:e,…})`) is recorded as a `dynamic_roster` note, not one unresolved identifier.
4. **Red, invocation fields.** Each registration records `user_invocable`, `disable_model_invocation`, `terminal_oriented`, and `survives_kill_switch` when present. A function-valued `disable_model_invocation` (the `verify` registration's shape) is recorded as `true` with a `flag_driven: true` note, matching the serializer's own reading.
4b. **Red, same-name bundled collision.** Two bundled registrations sharing one name (on 2.1.263, `design`: the canvas skill from `registerDesignCanvasSkill`, model-invocable, and the claude.ai/design hub, model-disabled) are both kept, keyed by registrar, under `bundled_skills.<name>` as a list of registrations with a `collision: true` note, never merged and never last-writer-wins; the fixture is the two `design` objects. `detect` and the Phase 4 marker read pick the registration whose description matches the row's evidence and record which.
5. **Green.** Region rule, stated exactly: from the first bundle marker to end of file, every printable run of at least 256 bytes, found with one `re.finditer(rb"[\t\n\r\x20-\x7e]{256,}")` pass, joined with newlines; `sources.binary` records `runs`, `joined_bytes`, `region_rule`, `runs_below_floor`, and `elapsed_seconds`. The longest-run path stays as the fallback when no marker is found. Registrar discovery order: CJS getter, ESM export list, canary. The registrar-shaped-export advisory scan gains the ESM form (`\w+ as (register[A-Za-z]*(?:Skill|Command|Agent))`) and `KNOWN_REGISTRAR_EXPORTS` gains `registerDesignCanvasSkill` and `registerWorkflowAuthoringSkill`.
6. `VALIDATED_AGAINST` moves to `2.1.263` in Phase 3, not here.

**Sanity Check:**

- `python3 plugins/claude-ops/skills/inventory/scripts/test_inventory.py` exits 0 and `grep -c "def test_read_bundle" plugins/claude-ops/skills/inventory/scripts/test_inventory.py` prints at least 4.
- `time python3 plugins/claude-ops/skills/inventory/scripts/inventory.py --binary-only --out /tmp/inv.json` exits 0 in under 30 seconds of wall clock (measured about 14 seconds), and `jq -e '[.bundled_skills.doctor, .bundled_skills.simplify, .bundled_skills.run, .bundled_skills.design, .bundled_skills["code-review"]] | all(. != null)' /tmp/inv.json` prints `true`, and `jq -e '.plugin_backed["security-review"] != null' /tmp/inv.json` prints `true`.
- `jq -e '.bundled_skills.doctor.disable_model_invocation == true and .bundled_skills.simplify.disable_model_invocation == false and .bundled_skills.doctor.terminal_oriented == true' /tmp/inv.json` prints `true`; `jq -r .bundled_skill_notes.registrar_route /tmp/inv.json` prints `esm-export`; `jq -r .integrity.status /tmp/inv.json` prints `ok` or `degraded`, never `broken`; `jq '.bundled_skills | keys' /tmp/inv.json` does not contain `ehrpd`.
- `jq -e '.bundled_skills.design | (type == "array" and length == 2) and (map(.disable_model_invocation) | sort == [false, true])' /tmp/inv.json` prints `true` (the canvas and hub registrations both kept).

### Phase 2: Per-lane integrity and honest exits in both tools [DONE]

Done 2026-09-11 as planned, plus a `plugin_backed` canary (`security-review`) so that lane has a break condition of its own, and `re_derivable: null` for session-provided and marketplace candidates, which have no extraction lane. A name collision in the extraction is listed in the candidate's evidence per registration with its invocation mode; the pairs file carries no description to match against, so `detect` records every registration and the Phase 4 marker read picks the one the row's evidence names.

Files: `inventory.py` (MODIFY), `test_inventory.py` (MODIFY), `plugins/claude-ops/skills/inventory/reference/extraction.md` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` (MODIFY), `plugins/claude-ops/skills/inventory/SKILL.md` (MODIFY, the integrity paragraph), `plugins/claude-ops/skills/audit-native-overlap/SKILL.md` (MODIFY, "The two substrates" and "Detection posture").

Pre-flight consumer check, first work item: `Grep` for readers of the integrity block. Known today: `overlap.py cmd_detect` (reads `integrity.status`, `cli_version`, `validated_against`), `inventory.py --self-check` (maps status to exit through `{"ok": 0, "broken": 1, "degraded": 3}`), `inventory/reference/extraction.md` (documents the block), `inventory/evals/evals.json` (expectations name the status), and `scripts/validate-plugins.sh` (reads overlap's exit code only). Record any further reader the grep finds before editing.

One rule for one state, stated exactly: top-level `integrity.status` becomes the worst lane; `broken` at the top level means every lane is broken or the binary is unreadable; a run with at least one healthy lane is at most `degraded`. The existing exit mappings in both tools already send `degraded` to 3 and `broken` to 1, so the exit code contract does not change; what changes is which state a single broken lane produces.

1. **Red.** `check_integrity` returns `lanes` with `{status, problems, advisories}` for `builtin_commands`, `bundled_skills`, and `plugin_backed`. Tests: a broken bundled lane with a healthy builtin lane yields lane statuses `ok`/`broken`/`ok` and top-level `degraded` carrying the bundled lane's problem as an advisory prefixed with the lane name; all lanes broken yields top-level `broken`; an unreadable binary yields `broken`.
2. **Red.** `cmd_detect` on an inventory with one broken lane states per-lane floors in `integrity` and marks every candidate whose lane is broken with `re_derivable: false`. The lane is decided by the seeded class when the native name is absent from the extraction, and by the observed class when it is present; a candidate is marked in both directions when either class maps to the broken lane. A fixture with a synthetic collision (one name seeded bundled, observed builtin) asserts the both-directions rule; the plan makes no claim that the fixed extractor reproduces the 2026-09-08 collision, because `build_report` drops a builtin whose name a bundled skill also carries. An inventory without `lanes` keeps today's behaviour.
3. **Green** both; update `extraction.md` and the evals expectations to the per-lane wording.
4. Re-word the audit-native-overlap SKILL.md rule from "if it reports broken, the report carries no native-side counts at all" to per-lane: counts are omitted only for a broken lane; the report names the lane and its cause.

**Sanity Check:**

- `python3 plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` and `python3 plugins/claude-ops/skills/inventory/scripts/test_inventory.py` exit 0.
- A fixture inventory with `lanes.bundled_skills.status == "broken"` and healthy other lanes makes `overlap.py detect … --out /tmp/c.json` exit 3 and `jq '[.candidates[] | select(.re_derivable == false)] | length' /tmp/c.json` prints a number greater than 0.
- `grep -c "no native-side counts at all" plugins/claude-ops/skills/audit-native-overlap/SKILL.md` prints 0.

### Phase 3: Reverse-parity blind spot, seeded pairs, evals, claude-ops release [DONE]

Done 2026-09-11. Two additions: the presence-mention advisory requires an availability word in the clause (`available`, `installed`, `enabled`, `present`, `resolves`, `exists`, `ships`), so "use when the user asks about a built-in command" is not a presence condition, and it judges the gate token per clause, since `prototype:explore-directions` carries the marketplace token in one clause and the ungated design mention in another. `--upstream-sha` now repeats, one value per upstream repository the store cites: the store records commits in two repositories (`anthropics/claude-code` for the `skill-doctor` row, `anthropics/claude-plugins-official` for the playground rows), so one value always drifted and the sanity check below could never hold as written. The Windows run was not reachable from this container; the CHANGELOG states the Linux-only basis.

Files: `overlap.py` (MODIFY), `test_overlap.py` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/reference/canonical-pairs.json` (MODIFY), `plugins/claude-ops/skills/inventory/evals/evals.json` (MODIFY only where an expectation names the old build or the old integrity wording), `plugins/claude-ops/.claude-plugin/plugin.json` (MODIFY), `plugins/claude-ops/CHANGELOG.md` (MODIFY). The native-references Enforceability row ("candidate check named, not built" becomes built) is edited in Phase 4's convention bump, not here, so the convention takes one versioned change.

1. **Red.** Self-check flags a frontmatter description that names a native surface by class and name behind a presence condition (`bundled|built-in|plugin-backed built-in|session-provided` followed within a few words by `skill|command`, inside a clause starting `when|where|if`) without the gate token. Fixture: the `visualize` wording "where the bundled design skill is available". Negative fixtures: a description carrying the token; a seam-phrasing "if that plugin is installed" clause; a Not-for clause that names a surface with no presence condition.
2. **Green.** The flag is an advisory (exit 3), not a break, because the two live cases are legitimate pending rows; the message names the row to add or the token to use.
3. Seed the two `audit-skill-visibility` pairs (`doctor` bundled-skill, `skill-doctor` builtin-command) into `canonical-pairs.json` with a `why`; `test_shipped_canonical_pairs_file_validates` covers the shape.
4. Eval re-validation, stated exactly: the repo's evals are `evals.json` in the skill-quality format, and `claude plugin eval` consumes `case.yaml` or `prompt.md` plus graders, so the CLI runner does not apply. "Evals pass" means `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/claude-ops/skills/inventory/evals/evals.json` exits 0 and `check-jsonschema` validates the file, after any expectation that names 2.1.228 or the old integrity wording is updated. Then set `VALIDATED_AGAINST = "2.1.263"`.
5. Windows basis: where a Windows host with the 2.1.263 `claude.exe` is reachable (the fleet's desktop over `/fleet:reach`), run `inventory.py --binary-only --self-check` there and record the result; where it is not, the CHANGELOG entry states that 2.1.263 was validated on the Linux ELF container only and the PE path is covered by the Phase 1 fixture.
6. Bump `claude-ops` to the next minor at PR time (additive `integrity.lanes`, the two new registrar routes, new advisories, new registration fields), write the CHANGELOG entry stating the rules, not the incident.
7. Open the unit's PR as a draft, body per the PR-body contract, quoting the two seeded pairs; flip to ready when green.

**Sanity Check:**

- `python3 overlap.py self-check --upstream-sha ed404106fcd80ba98ecb7c851e531dcb626d13b7 --upstream-sha d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b` exits 3 with no problems, and its advisories are exactly the version-drift advisory (until Phase 4 refreshes observations) plus two reverse-parity advisories naming `visualization:visualize` and `prototype:explore-directions` (`… 2>&1 | grep -c "presence condition without a gate token"` prints 2).
- `jq '.pairs | length' canonical-pairs.json` prints 16 and `jq '.pairs[] | select(.native.name=="skill-doctor")' canonical-pairs.json` is non-empty.
- `grep -n 'VALIDATED_AGAINST = "2.1.263"' inventory.py` matches; `jq -r .version plugins/claude-ops/.claude-plugin/plugin.json` is greater than `0.45.2`; `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/claude-ops/skills/inventory/evals/evals.json` exits 0; `scripts/affected-tests.sh --run` passes.

### Phase 4: Policy unit, the `integration` axis and the two new grammars [TODO]

Files: `docs/native-surfaces/records.json` (MODIFY, every row, plus two new rows), `docs/NATIVE-SURFACES.md` (regenerated), `overlap.py` (MODIFY), `test_overlap.py` (MODIFY), `docs/conventions/native-references/README.md` (MODIFY), `docs/conventions/native-references/CHANGELOG.md` (MODIFY), `plugins/claude-ops/skills/audit-native-overlap/SKILL.md` (MODIFY, "Verdicts and the human gate", "The apply step"), `plugins/claude-ops/.claude-plugin/plugin.json` and `CHANGELOG.md` (MODIFY).

Pre-flight consumer check, first work item: `Grep` for readers of `records.json` and of the `baked` object; today they are `overlap.py` and the generated view only. The change is additive.

0. **Pre-flights, answered 2026-09-11 by the two-validator research pass and quoted in the PR body before any verdict is written.** (a) Model-invocability per row, keyed per registration from the Phase 1 extraction: `doctor` and `design-sync` disabled; `simplify`, `run`, `code-review`, and the design canvas skill enabled (the model-disabled `design` registration is the claude.ai/design hub, which no row describes). (b) `simplify` takes a `[<target>]` argument and its prompt prepends the review target, so `batch-simplify` scopes it per file set. (c) CI lane: `allowed-tools` grants and never restricts, so the `security-review` skill's frontmatter proves nothing about reach; the row takes `route` because the lane runs a pinned reusable workflow in `melodic-software/ci-workflows` whose tool allowlist and plugin roster this repository does not control, and because the native command is unusable there (it diffs against `origin/HEAD`, which the Actions checkout does not provide; the skill body already records this), even though the official skills reference lists `/security-review` among the built-ins the Skill tool can invoke.
1. **Red, schema.** `validate_row` requires `integration` in `route|wrap|suggest` with the class rules from `design/design-resolution.md`: `builtin-command` takes `route` or `suggest`; `bundled-skill`, `plugin-backed-builtin`, and `marketplace-plugin` take `route` or `wrap`; a `bundled-skill` row carrying the new marker `model-invocation-disabled` takes `suggest` only (a route phrase on a surface the model never lists is dead text); `session-skill` takes `route`; a `defer` verdict takes `route`. `NATIVE_MARKERS` gains `model-invocation-disabled`, set from the extraction registration the row's evidence names, never from the bare name. Every `wrap` or `suggest` row carries an evidence line naming the observed invocation mode (the class rules are a floor; Skill-tool reach is per surface). `baked` gains booleans `native_step` (true only with `wrap`) and `suggest_sentence` (true only with `suggest`). One test per rule.
2. **Red, parity.** Forward parity for `native_step` looks for the literal `## Native step: <name> (<class>)` heading in the component body; forward parity for `suggest_sentence` looks for the suggest sentence shape in the body. Reverse parity gains a body scan for the suggest sentence shape only (`If /` … `is available in your session (`), with the `claude-ops:changelog` prose line as a negative fixture, so a body carrying the shape with no store row is an orphan.
3. **Green.** Render the view with an `Integration` column in the summary table and an `Integration:` line per row.
4. **Convention, one major bump.** Add the `wrap` grammar: the body section `## Native step: <name> (<class>)` carrying, in order, the gate token; the identity check by class (bundled: name in the listing, invoke by alias where the Skill tool resolves one, advisory description check; a description that reads as a different surface is a likely user or project shadow, so skip with a warning; a name with no description, which `name-only` and budget overflow both produce, is invoked with a stated "identity confirmed by name alone" warning, matching the playgrounds precedent; plugin: namespaced form plus marketplace provenance when the CLI resolves); the mutation clause (a mutating surface may be wrapped only where the wrapping skill's own contract mutates the same thing, the invocation passes an explicit scope or report-only argument, the skill fingerprints what the surface may write before the step and diffs after, and an unexpected diff is reported as a fourth state, "mutation detected after a scoped invocation", with the run exiting degraded); the invocation form; what our part adds before or after; the skip-and-report contract for the states `did not resolve in this session`, invocation refused by the tool or permissions (the report names the refusal reason and never retries: not in the session's skills allowlist, disabled for model invocation by `disableBundledSkills` or `skillOverrides`, or a permission deny, which is alias-aware, so `Skill(review)` blocks the bundled `code-review`), identity mismatch, and a fifth state, resolved but degraded (the native surface ran a weaker procedure and said so, as `simplify` does when the Agent tool is absent and it falls back to a single pass; the wrapper relays the surface's own disclosure into its report and never restates the step as the documented full procedure), each naming the axis line and the enable path; a note that the wrapped body enters context once and stays there, so a Native step is priced like any other body load; and the `unattended` argument, declared by the caller, under which the skill records instead of asks and never invokes a mutating surface. Add the `suggest` grammar: the sentence shape above, addressed to the person, where `<basis>` is a same-file four-part verification record per upstream-drift that names the surface's own gate (for `/doctor`, `DISABLE_DOCTOR_COMMAND` or a `skillOverrides` entry, since it is the one registration that survives `disableBundledSkills`; for every other bundled skill, `disableBundledSkills` as well), placed at the start of the run when coverage is total and at the end when partial, and where a model-disabled bundled skill is suggested as `/<name>` typed by the person exactly as a built-in command is; the wording is "reserved for the person to run", never "cannot be invoked" as an absolute; unattended runs record it in output. State explicitly that the suggest token `is available in your session (` differs from the route token by design (the route token is a condition the model observes in its listing, the suggest token one the person checks), that it is not the rejected assertion phrasing `always available`, and that parity keys on the sentence shape. Add the class table with the `marketplace-plugin` row naming seam-phrasing as the owner of that class's wrap grammar and the model-disabled bundled-skill row (`suggest` only). Amend the one-owner rule: one owning description phrase per plugin per surface stays; a second skill in the same plugin carries a Native step or suggest section with a same-plugin pointer to the owner's Boundary, never a second phrase; the rule governs description phrases only, so sibling skills may each carry a suggest sentence for the same surface. Flip the Enforceability row for the gate-token check to built (Phase 3 built it). This is a major version of the convention on the convention's own trigger list: an enforceability verdict changes and the canonical-token clause gains a second token; the one-owner amendment in the Boundary section contributes. The CHANGELOG entry cites those triggers, not the Boundary section alone.
5. **Re-derive observations.** Run `detect` on the Phase 1 extraction and refresh `observation.detail` and `recheck.verified` to 2.1.263 for every extraction-class row whose native surface the extraction resolves and whose evidence still holds, so the version advisory clears; rows whose evidence moved keep their old record and gain an evidence line saying what moved; every bundled-skill row gains or drops the `model-invocation-disabled` marker from the registration its evidence names. Reason-text corrections in the same pass: the `export` row's "built-ins are user-invoked only" becomes the per-surface reason (`/export` and `/skill-doctor` are non-prompt command types the Skill tool never lists; `/init` and `/security-review` are prompt-typed and reachable); the `security-review` row's reason drops any `allowed-tools` basis for the CI-harness and `origin/HEAD` basis; the `code-review` row's reason rests on cost and shape (the native surface fans out its own agents; the CI lane cannot be typed into a session), not reach; the two `design` rows name the canvas registration, the hub registration, and the `local` access command, with the recheck trigger widened to "which registrar wins `isEnabled`"; the `morning` row gains this session's roster as a second live observation; the `skill-doctor` row notes the native report excludes bundled skills. This step runs before step 6, since the `design` conclusions change under a 2.1.263 read.
6. **Verdict pass, values confirmed by the user on 2026-09-11 and validated by the research pass; the PR body quotes this table and the user re-confirms it there.** `wrap` for `run` (run-e2e) and `simplify` (batch-simplify); `suggest` for all three `doctor` rows (audit-install-state and audit-skill-visibility own a sentence each; audit-performance carries a pointer-carrying sentence, since a `route` row cannot carry the sentence Phase 5 writes it and a route phrase on a model-disabled surface is dead text), for `skill-doctor`, and for the three `export` rows; `route` for `code-review`, `security-review`, `morning`, the two `playground` rows, the two `design` rows (on job merits, not reach; `wrap` is admissible and stays a Phase 9 and 10 revisit), `design-sync`, and `tidy` (`simplify` works the current diff, tidy works a rotated lane of resting code with no diff, and `simplify` applies fixes where tidy is structure-only). Two new rows: `export` against `session-flow:handoff` and `export` against `session-flow:retro`, both `suggest`, because each body carries a suggest sentence and every baked line must trace to a row. Each row's evidence gains the substrate observations from the 2026-09-08 report where they apply (`skill-doctor` gate basis; `design` name collision) and the `budget_caveat` note that `audit-performance` and `audit-skill-visibility` have under 60 characters of description headroom.
7. **Apply step.** Update the skill body: preconditions add "the row's `integration` is not `route` when a Native step or suggest sentence is to be written" and "the row does not carry `model-invocation-disabled` when a Native step is to be written"; the emitted artefacts add the Native step section and the suggest sentence; the per-entry cap precheck is a hard precondition (`description` plus `when_to_use` after baking at most 1,536 characters, measured by `bash plugins/skill-quality/scripts/check-skill.sh <skill>`); every wrapped or suggesting skill declares the `unattended` argument in its `argument-hint`.
8. Bump `claude-ops` to the next minor at PR time; draft PR; ready when green.

**Sanity Check:**

- `python3 overlap.py self-check --upstream-sha ed404106fcd80ba98ecb7c851e531dcb626d13b7 --upstream-sha d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b` exits 0 with no problems and no advisories; `jq '[.rows[] | select(.integration == null)] | length' docs/native-surfaces/records.json` prints 0; `jq '.rows | length' docs/native-surfaces/records.json` prints 18; `python3 overlap.py generate --check` exits 0.
- `grep -c "## Native step: <name> (<class>)" docs/conventions/native-references/README.md` prints at least 1; `grep -c "is available in your session (" docs/conventions/native-references/README.md` prints at least 1; `grep -c "marketplace-plugin" docs/conventions/native-references/README.md` prints at least 1; `grep -c "model-invocation-disabled" docs/conventions/native-references/README.md` prints at least 1.
- `jq '[.rows[] | select(.native.class=="builtin-command" and .integration=="wrap")] | length' records.json` prints 0; `jq '[.rows[] | select((.native.markers | index("model-invocation-disabled")) and .integration!="suggest")] | length' records.json` prints 0; `jq '[.rows[] | select(.native.name=="design" and (.native.markers | index("model-invocation-disabled")))] | length' records.json` prints 0; `jq '[.rows[] | select(.verdict=="defer" and .integration!="route")] | length' records.json` prints 0; `jq '[.rows[] | select(.integration=="suggest")] | length' records.json` prints 7 and `jq '[.rows[] | select(.integration=="wrap")] | length' records.json` prints 2.

### Phase 5: Sweep unit, claude-ops [TODO]

Files: `plugins/claude-ops/skills/audit-install-state/SKILL.md`, `audit-skill-visibility/SKILL.md`, `audit-performance/SKILL.md` (MODIFY), `records.json` and the view (baked flags), `plugins/claude-ops/.claude-plugin/plugin.json` and `CHANGELOG.md` (MODIFY). `morning-brief` is KEEP (defer row).

A suggest unit, confirmed 2026-09-11: `doctor` is model-disabled, so no skill in this plugin can compose it, and all three `doctor` rows take `suggest`. The suggest bases name `DISABLE_DOCTOR_COMMAND` and the `skillOverrides` entry as the gate, not `disableBundledSkills`, which `/doctor` alone survives.

1. `audit-install-state`: keep the description phrase; replace the Boundary section's routing paragraph with the suggest sentence for `/doctor` at the end of the run (coverage is partial: doctor fixes, this skill inventories), its basis pointing at the section's existing verification record; declare `unattended` and record the suggestion under it.
2. `audit-skill-visibility`: a suggest sentence for `/skill-doctor` at the start of the run (its coverage of "unused versus cost" is the whole ask when the user wants only that list) and one for `/doctor` at the end, both with bases pointing at the skill's existing verification record; declare `unattended`.
3. `audit-performance`: no description change. A suggest sentence for `/doctor` at the end of the run that opens with a same-plugin pointer to audit-install-state's section for the shared surface facts; declare `unattended`.
4. Set `baked.suggest_sentence` on the four rows; regenerate the view; run the skill-quality check per touched skill; bump to the next minor; draft PR quoting the four store rows; ready when green.

**Sanity Check:**

- `bash plugins/skill-quality/scripts/check-skill.sh <skill>` passes for each of the three skills (its per-entry cap check covers the description length).
- `python3 overlap.py self-check --upstream-sha ed404106fcd80ba98ecb7c851e531dcb626d13b7 --upstream-sha d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b` exits 0; `grep -c "If /doctor is available in your session (" plugins/claude-ops/skills/audit-install-state/SKILL.md` prints 1; `grep -c "unattended" plugins/claude-ops/skills/audit-install-state/SKILL.md` prints at least 2 (argument-hint and body).
- In this cloud session, invoking `/claude-ops:audit-install-state unattended` yields a report whose final section records the `/doctor` suggestion without asking; the transcript excerpt is quoted in the PR body.

### Phase 6: Sweep unit, code-tidying [TODO]

Files: `plugins/code-tidying/skills/tidy/SKILL.md`, `batch-simplify/SKILL.md` (MODIFY), `records.json` and the view, `plugins/code-tidying/.claude-plugin/plugin.json` and `CHANGELOG.md`.

The first wrap unit. `simplify` is model-invocable and mutates the working tree, which is batch-simplify's own contract, so the mutation clause is satisfied by scope: the invocation names the file set, the pre-step fingerprint is the set of tracked files outside that scope, and any change outside it is the fourth state.

1. `batch-simplify`: `## Native step: simplify (bundled skill)` invoking `simplify` over the scope the Phase 4 pre-flight established when it resolves, our batching and ordering around it; the three-state skip report; `unattended` declared, under which the step still runs because the skill's own contract already edits files unattended.
2. `tidy`: phrase only unless the human gate chose `wrap`; if `wrap`, the Native step runs `simplify` on the lane's changed files after the structural tidyings and states that the resulting PR is no longer structure-only.
3. Baked flags, view, skill-quality check, next minor, draft PR, ready when green.

**Sanity Check:**

- skill-quality check passes for both skills; `python3 overlap.py self-check --upstream-sha ed404106fcd80ba98ecb7c851e531dcb626d13b7 --upstream-sha d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b` exits 0; `grep -c "## Native step: simplify (bundled skill)" plugins/code-tidying/skills/batch-simplify/SKILL.md` prints 1.
- Positive path in this cloud session, where `simplify` resolves: invoking `/code-tidying:batch-simplify` over a small changed set yields a report with a `Native step` result block and no change outside the named scope; negative path on a host with `disableBundledSkills` set: the report carries `did not resolve in this session` and the axis line; both transcript excerpts are quoted in the PR body.

### Phase 7: Sweep unit, testing [TODO]

Files: `plugins/testing/skills/run-e2e/SKILL.md` (MODIFY), `records.json` and the view, `plugins/testing/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. `run-e2e`: phrase plus `## Native step: run (bundled skill)` that launches the app through `run` when it resolves and layers evidence capture (screenshots, responses, logs) on top; the three-state skip report falling back to the skill's own launch playbook; `unattended` declared. `run` starts processes rather than editing files, so the mutation clause's fingerprint is the tracked tree, which must be unchanged after the step. Identity check: the official skill precedence lets a project skill named `run` shadow the bundled one, and the bundled `run` itself defers to a project skill that covers launching the app, so a listed `run` whose description reads as a project launcher is a legitimate target, not a mismatch; the step records which it invoked.
2. Baked flags, view, skill-quality check, next minor, draft PR, ready when green.

**Sanity Check:**

- skill-quality check passes; self-check with the pinned SHA exits 0; `grep -c "settings or environment, plan, platform or provider, host surface" plugins/testing/skills/run-e2e/SKILL.md` prints at least 1; positive and negative transcript excerpts quoted in the PR body.

### Phase 8: Sweep unit, review [TODO]

Files: `plugins/review/skills/code-review/SKILL.md`, `plugins/review/skills/security-review/SKILL.md` (MODIFY, phrase only), `records.json` and the view, `plugins/review/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. Both skills: the route phrase only, per the Phase 4 pre-flight (c). No `allowed-tools` change.
2. Baked flags, view, skill-quality check, next minor, draft PR, ready when green.

**Sanity Check:**

- skill-quality check passes for both; self-check with the pinned SHA exits 0; `jq -r '.rows[] | select(.component.plugin=="review") | .integration' records.json` prints `route` twice.

### Phase 9: Sweep unit, visualization [TODO]

Files: `plugins/visualization/skills/visualize/SKILL.md` (MODIFY), `records.json` and the view, `plugins/visualization/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. Bring the description's "where the bundled design skill is available" under the gate token so the reverse-parity advisory from Phase 3 closes; set `baked.description_phrase`.
2. The row is `route` (confirmed 2026-09-11): the design canvas skill is model-invocable, so the gate-token phrase is live, and the existing Boundary is kept with its evidence naming the canvas registration, the model-disabled hub registration, and the `local` access command. `wrap` is admissible here and is the one revisit this phase may raise before it starts: a Native step would only make sense if visualize gained a sub-step the canvas skill performs, which today it does not. The `design-sync` row stays `defer`.
3. Baked flags, view, skill-quality check, next minor, draft PR, ready when green.

**Sanity Check:**

- `python3 overlap.py self-check --upstream-sha ed404106fcd80ba98ecb7c851e531dcb626d13b7 2>&1 | grep -c "visualization:visualize"` prints 0; skill-quality check passes.

### Phase 10: Sweep unit, prototype [TODO]

Files: `plugins/prototype/skills/explore-directions/SKILL.md` (MODIFY), `records.json` and the view, `plugins/prototype/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. Same treatment as Phase 9 for the `design` row; the existing `playground` phrase (`installed from its marketplace`) is untouched.
2. Baked flags, view, skill-quality check, next minor, draft PR, ready when green.

**Sanity Check:**

- `python3 overlap.py self-check --upstream-sha ed404106fcd80ba98ecb7c851e531dcb626d13b7 2>&1 | grep -c "prototype:explore-directions"` prints 0; skill-quality check passes.

### Phase 11: Sweep unit, session-flow [TODO]

Files: `plugins/session-flow/skills/clean-stop/SKILL.md`, `handoff/SKILL.md`, `retro/SKILL.md` (MODIFY), `records.json` and the view, `plugins/session-flow/.claude-plugin/plugin.json` and `CHANGELOG.md`.

1. Re-phrase the three existing `/export` suggestion sites to the `suggest` sentence shape (the basis pointing at a same-file verification record, end-of-run placement, which is where they already sit); each of the three skills declares `unattended` and records the suggestion in output under it.
2. Set `baked.suggest_sentence` on the three `export` rows (clean-stop, handoff, retro); `integration: suggest` was written in Phase 4.
3. View, skill-quality check, next minor, draft PR, ready when green.

**Sanity Check:**

- `grep -c "If /export is available in your session (" plugins/session-flow/skills/clean-stop/SKILL.md plugins/session-flow/skills/handoff/SKILL.md plugins/session-flow/skills/retro/SKILL.md` prints 1 or more for each file; skill-quality check passes for the three skills; self-check with the pinned SHA exits 0 with no orphan advisory.

### Files affected (whole plan)

| File | Action | Phase |
|---|---|---|
| `plugins/claude-ops/skills/inventory/scripts/inventory.py` | MODIFY | 1, 2, 3 |
| `plugins/claude-ops/skills/inventory/scripts/test_inventory.py` | MODIFY | 1, 2 |
| `plugins/claude-ops/skills/inventory/reference/extraction.md` | MODIFY | 2 |
| `plugins/claude-ops/skills/inventory/evals/evals.json` | MODIFY if an expectation names the old build or wording | 2, 3 |
| `plugins/claude-ops/skills/inventory/SKILL.md` | MODIFY | 2 |
| `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` | MODIFY | 2, 3, 4 |
| `plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` | MODIFY | 2, 3, 4 |
| `plugins/claude-ops/skills/audit-native-overlap/reference/canonical-pairs.json` | MODIFY | 3 |
| `plugins/claude-ops/skills/audit-native-overlap/SKILL.md` | MODIFY | 2, 4 |
| `docs/native-surfaces/records.json` | MODIFY | 4, 5 to 11 |
| `docs/NATIVE-SURFACES.md` | REGENERATE | 4, 5 to 11 |
| `docs/conventions/native-references/README.md`, `CHANGELOG.md` | MODIFY (one major bump) | 4 |
| `plugins/claude-ops/.claude-plugin/plugin.json`, `CHANGELOG.md` | MODIFY | 3, 4, 5 |
| `plugins/claude-ops/skills/{audit-install-state,audit-skill-visibility,audit-performance}/SKILL.md` | MODIFY | 5 |
| `plugins/claude-ops/skills/morning-brief/SKILL.md` | KEEP | 5 |
| `plugins/code-tidying/skills/{tidy,batch-simplify}/SKILL.md` plus manifest and CHANGELOG | MODIFY | 6 |
| `plugins/testing/skills/run-e2e/SKILL.md` plus manifest and CHANGELOG | MODIFY | 7 |
| `plugins/review/skills/{code-review,security-review}/SKILL.md` plus manifest and CHANGELOG | MODIFY (phrase only) | 8 |
| `plugins/visualization/skills/visualize/SKILL.md` plus manifest and CHANGELOG | MODIFY | 9 |
| `plugins/prototype/skills/explore-directions/SKILL.md` plus manifest and CHANGELOG | MODIFY | 10 |
| `plugins/session-flow/skills/{clean-stop,handoff,retro}/SKILL.md` plus manifest and CHANGELOG | MODIFY | 11 |
| `scripts/validate-plugins.sh` | KEEP (exit-code contract unchanged) | 2 |

### Test strategy

TDD throughout, Red-Green-Refactor per work item, with Red items restricted to behaviour that does not exist yet (the Phase 2 exit mappings already exist and are not claimed as Red). Test boundaries, all existing public interfaces:

- `inventory.py` functions `read_bundle` (first tests, the regression boundary for the actual bug), `extract_bundled_skills`, `discover_registrar`, `build_const_map`, and `check_integrity`, driven by `test_inventory.py` with synthetic bundles (existing pattern) plus the fragmented-run, PE-container, legacy, below-floor, three-registrar-route, cross-chunk-constant, and phantom-name fixtures; the real binary is the Phase 1 sanity check, not a unit test.
- `overlap.py` functions `validate_row`, `check_baked_parity`, `cmd_detect`, `cmd_self_check`, `render_view`, driven by `test_overlap.py`'s `TempRepo` fixture (existing pattern), with the synthetic collision, marker, and suggest-shape fixtures added.
- Skill bodies are verified by `plugins/skill-quality/scripts/check-skill.sh` per touched skill and by `overlap.py self-check` parity, both deterministic.
- Behavioural criteria are verified twice per wrap unit: the positive path (surface resolves, native result reported, no change outside scope) in this cloud session for `simplify` and `run`, which resolve here, and the negative path on a host with `disableBundledSkills` set, with both transcript excerpts quoted in the PR body. Suggest units verify the unattended recording path in this session.
- `scripts/affected-tests.sh --run` closes every unit before its PR.

Test type per change: unit for the Python engines, contract for the store and view, static for skill bodies, one manual runtime probe per path per unit for the composition and degradation behaviour. No test is skipped, disabled, or quarantined to reach green.

### Alternatives considered

- **Canary-derived registrar as the primary route.** Rejected after the second probe: the ESM export list names the registrar directly and survives a reordering of the `doctor` object; the canary stays as the third route. Switch condition: a build with neither the CJS getter nor an ESM export list.
- **A 64 KiB run floor.** Rejected: measured on the real binary it recovers 13 of 33 names and the regex takes minutes. Switch condition: a build that stops fragmenting the bundle.
- **Fold the policy unit into the tooling-fix PR.** Rejected: mixes a repair with a routing-policy change and hides the human verdict pass inside a bug fix. Switch condition: the user prefers one review over two.
- **Reuse the `resolves in your session` token for `suggest`.** Rejected: a built-in command or a model-disabled skill never appears in the model's listing, so the token's read-time meaning does not hold; the suggest sentence is addressed to the person who can check. Switch condition: Claude Code starts listing those surfaces to the model.
- **Treat a name-only listing as "not resolving".** Rejected: the model cannot tell `skillOverrides: name-only` from a budget-dropped description, and the playgrounds precedent already rules that a present name is not evidence of absence. Switch condition: the listing starts marking overridden entries.
- **Wrap `doctor` anyway through a report-only argument.** Rejected: the registration disables model invocation, so no skill can reach it regardless of arguments. Switch condition: a release flips the flag, which the Phase 1 field and the row's recheck trigger will show. The binary carries an undocumented exception (a skill the person typed by name in the same turn may be invoked from the main session), which the plan does not design on.
- **Wrap the design canvas on visualize and explore-directions.** Admissible after the 2026-09-11 finding that the canvas registration is model-invocable; rejected on job merits, because both components already own the artifact-producing job and have no sub-step the canvas skill performs. Switch condition: the user chooses `wrap` at Phase 9 or 10, or either component gains such a sub-step.
- **One gate token for both grammars.** Rejected: the route token names a condition the model observes in its listing and the suggest token one the person checks; parity keys on the sentence shape either way. The near-collision with the rejected phrasing `always available` is an accepted authoring hazard the convention names. Switch condition: the shape-keyed parity proves insufficient in practice.
- **Move #4049 to `work-class: scoped` and `agent-ready` once the verdicts are recorded.** Rejected by both validators on the repository's own definitions: the unit adds a required field to the store and takes a major version of a convention that calls itself a contract, which is C4 by `work-classes.md`, and a C4 item never carries `agent-ready`. A carve-out of the data work would be feature-shaped C3 and still human-gated at the work-loop admission gate. Switch condition: the admission gate admits feature-shaped C3, or the convention bump leaves the unit.
- **Wrap every bundled row uniformly, no human pass.** Rejected by the Brief.
- **Run the sweep as parallel per-plugin agents.** Rejected: the sweep contract forbids two units in flight because description edits are routing-affecting. Switch condition: the contract is amended.

### Risks and mitigations

- **A later CLI release changes the registration shape again.** Three discovery routes plus per-lane integrity make the failure a named broken lane, not a silent short list; the registrar-export advisory now sees the ESM form. Mitigation is the existing eval re-validation trigger.
- **A wrapped mutating surface writes outside its scope.** The mutation clause's fingerprint-and-diff makes that a reported fourth state; `unattended` never invokes a mutating surface. `[FALLBACK, confirm or override]`: on a detected out-of-scope change the run exits degraded and the unit's PR body records it.
- **The Skill tool refuses the invocation headless or in a subagent.** The three-state skip report makes a refusal a reported state, not a silent one; `AskUserQuestion` is absent in subagents and under `--permission-prompts none`, so a wrapped skill never depends on the native surface asking a question.
- **The reverse-parity heuristic produces false positives on prose.** It is an advisory, keyed on a class word plus `skill|command` inside a presence clause, with negative fixtures for seam-phrasing and Not-for clauses; the suggest scan keys on the full sentence shape.
- **Nine sequential PRs take weeks.** Accepted by the Brief; the parent issue tracks progress and each unit is independently valuable.

## Blast radius

MEDIUM. Files: over 30 across eight plugins and one convention at a major bump. Other sessions: the store, the generated view, `inventory.py --self-check`, and `validate-plugins.sh` are shared CI surfaces; every change is additive and the exit-code contracts are unchanged. Reversible by git revert per unit. Two stress-test triggers matched: a new convention grammar (constrains future skill authoring) and a multi-step implementation touching undocumented binary layout.

## Stress-test summary

Fresh-context plan review (Step 3): 1 critical, 14 important, 8 suggestions; every finding verified against the code or docs and folded in. Devil's-advocate pass (Step 4): 2 critical, 6 high, 5 medium, 4 low; every finding re-verified on the binary and the repository before it was applied. The two critical findings changed the plan's substance: the 64 KiB region rule was replaced by a 256-byte rule with chunk-scoped constant resolution and the ESM export list as the primary registrar route, and the discovery that `doctor` and `design` are registered model-disabled moved their rows from `wrap` to `suggest` or `route`, which is now a USER-RESERVED question because it changes the Brief's wrap-candidate assumption. One research-iterate loop ran (a second binary probe); no third was needed. Round-4 validation (2026-09-11): two independent fresh-context validators (Fable 5.1, Opus) checked the seven policy decisions against the official references, the binary, and the conventions; both confirmed every integration value, both rejected the `agent-ready` flip for #4049, and both found that `design` is two bundled registrations (the canvas is model-invocable) and that `allowed-tools` never restricts reach; those corrections are folded into Phases 1, 4, 5, 7, 9 and 10 and the Brief's third scope note. Reports: scratchpad `validation-fable.md` and `validation-opus.md`, quoted in the #4049 body.

## Execution shape

Fully sequential. Phase 0 gates everything; Phases 1 to 3 share `inventory.py` and `overlap.py`; Phase 4 gates every sweep unit because it writes the `integration` values and runs every pre-flight; Phases 5 to 11 are serialized by the sweep contract. No parallel wave is recommended. `[EXEC-SHAPE]`

| Phase | Surface | Basis |
|---|---|---|
| 0 | main session via `/work-items:decompose` | tracker write with a search-before-create pivot |
| 1 to 3 | main session | judgment-heavy: binary layout, integrity semantics, evals |
| 4 | main session | pre-flights and the human verdict pass row by row |
| 5 to 11 | main session, or one sub-agent worker per unit with the unit's SKILL.md files as its ALLOWED list and `records.json`, `PLAN.md`, other plugins FORBIDDEN | mechanical per unit once the grammar exists; still one unit at a time; the runtime probes stay main-session because subagents lack the question tool |

Sequential fallback: not applicable, the shape is already sequential.

## Open questions

- Resolved 2026-09-11 (round-4 re-interview, user accepted all recommendations conditioned on a two-validator research pass, which confirmed every value and amended four bases; ledger `.work/audit-native-overlap/interview-checklist.md`): the three `doctor` rows take `suggest`; the two `design` rows and `design-sync` take `route`, the `design` rows on job merits because the canvas registration is model-invocable; `tidy` takes `route`; `simplify` on batch-simplify and `run` on run-e2e take `wrap`; the remaining rows take the bundle values in Phase 4 step 6; the convention change is a major bump on the enforceability and token triggers; #4049 stays `work-class: structural` and `needs-human` with the verdict table recorded in its body as the C4 plan approval. The `name-only` coverage case stays as downgraded (name present, description absent, invoke with a warning). **arbiter: USER, validated**
- None open.

## Handoff to implementation

### User-approval gates

- Every `integration` value written in Phase 4 (confirmed by the user on 2026-09-11 and validated; the PR body quotes the table and the user re-confirms it there as the C4 plan approval). #4049 stays human-gated: `work-class: structural`, `needs-human`, human review and human merge.
- The mutation-clause fourth state when it fires in a wrap unit.
- Creating each sweep sub-issue's PR only after its predecessor unit closes.

### Execution shape ([EXEC-SHAPE] tagged)

- Policy schema as its own unit (Phase 4) rather than inside the tooling fix.
- The suggest sentence shape and its parity keyed on the shape, not the bare phrase.
- `baked.native_step` and `baked.suggest_sentence` as the third and fourth baked flags; `model-invocation-disabled` as a third native marker set from the extraction.
- Two new store rows for the `export` suggestion sites in `handoff` and `retro`, so parity is enforceable.
- The amended one-owner rule: pointer-carrying Native step or suggest sections in sibling skills, never a second phrase.
- One major bump of the native-references convention in Phase 4, carrying the Phase 3 enforceability flip.
- Unit order after claude-ops: code-tidying, testing, review, visualization, prototype, session-flow.
- "Next minor at PR time" for every touched plugin, matching claude-ops's one-version-per-PR CHANGELOG practice.
- The Phase 1 region rule (first marker to end of file, runs of at least 256 bytes, one regex pass), registrar route order (CJS getter, ESM export, canary), and chunk-scoped constant resolution.
- Sub-issues published all at once with dependency edges, blocked, rather than created one at a time.

### Mechanical work

- One draft PR per unit, body per the PR-body contract, closing keyword pointing at the unit's sub-issue, affected store rows quoted.
- Before each push: `scripts/affected-tests.sh --run`, `python3 overlap.py self-check --upstream-sha <pinned>`, `python3 overlap.py generate --check`, `check-skill.sh` per touched skill, markdownlint on touched markdown.
- The contract slice `docs/topics/audit-native-overlap/` is pruned in the final commit of the last unit's PR per the topic-docs convention.
- Phase tags advance `[TODO]` to `[DOING]` to `[DONE]` in this file, edited only from the main session.
