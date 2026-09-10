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

<!-- populated by /planning:plan -->
