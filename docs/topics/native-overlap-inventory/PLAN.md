# Native overlap inventory

## Brief

**TLDR:** Add a `claude-ops:audit-native-overlap` sibling skill that maps native Claude Code
surfaces (built-in CLI commands, bundled skills) against the current repo's plugin skills and
agents, records human-gated per-overlap verdicts in a committed verdict/record store (the SSOT)
rendered into a generated registry view (`docs/NATIVE-SURFACES.md`) whose rows carry recheck
triggers, and — only behind an explicit apply step — bakes routing-effective, presence-gated
native references into component descriptions plus Boundary sections in bodies, with a
deterministic store/registry freshness + parity check wired into CI.

### Goal

Every marketplace component whose purpose materially overlaps a native surface carries truthful,
routing-effective guidance about when to prefer or compose the native equivalent, sourced from a
single registry that announces its own staleness instead of decaying silently.

### Locked decisions

1. **Packaging** — new sibling skill in `claude-ops` (working name `audit-native-overlap`).
   Bare invocation is a read-only report; mutation only behind an explicit apply step (codified
   `audit` verb contract). Must be repo-generic: it targets "the current repo's plugin tree", never
   a hardcoded melodic-software layout (claude-ops ships to external consumers).
2. **Registry** — a two-part shape (amended post-validation: a generated doc cannot be the SSOT,
   or regeneration destroys human verdicts). The **SSOT is a committed, hand-editable
   verdict/record store** (a data file; exact path/format is Q13) holding, per overlap: native
   surface (with hidden/gated markers), our component, verdict + reason, evidence, observation
   record, and a four-part upstream-drift record with a per-row **recheck trigger** (a date alone
   does not qualify). `docs/NATIVE-SURFACES.md` is the **generated view** over that store
   (marker-fenced, never hand-edited, `--check` drift-gated like `docs/CATALOG.md`). Observation
   records distinguish their evidence class: *extraction-evidence* ("extracted from binary
   v<X> on <date>") vs *live-roster observation* ("observed in <env> session on <date>") — never a
   static availability assertion. Seeded candidate pairs stay in skill reference data (candidates,
   not verdicts).
3. **Baked guidance** — routing-effective text lives in frontmatter *descriptions* (in model
   context **by default, subject to the listing budget**: descriptions degrade to name-only when
   the 1%-of-window aggregate budget overflows, least-invoked first — and this repo's fleet
   currently exceeds that budget several-fold, so a baked phrase is the best available surface,
   not a guaranteed one), phrased as a read-time presence gate ("when the bundled X skill
   resolves in your session, prefer it for …; this skill for …"), within description budget. The
   audit report therefore includes a **budget-exposure section** (composing the existing advisory
   `check-listing-budget.sh`) and the store records a per-row "phrase may be budget-dropped"
   caveat where it applies. The
   body gets a fuller Boundary section where warranted (the `review` plugin's organic pattern is
   the model). Baked text is self-contained — shipped plugins never cite the registry doc (broken
   ref at install time). The native-reference phrasing gets its own owner convention doc
   (seam-phrasing covers cross-plugin references only).
4. **Verdict enum** — `prefer-native` / `prefer-ours` (reason required) / `complementary` /
   `superseded` / `defer` (undetermined: gated, experimental, or unverifiable surfaces). No blanket
   preference rule.
5. **Verdict authority** — candidates auto-detected with evidence; every verdict human-gated
   before any component file is modified.
6. **Detection posture** — floor-honest: consume `inventory.py` output with its integrity status
   carried into the report, seed from a hand-curated canonical-pairs list, allow human-added
   candidates. Honest under-recall over confident completeness. Two substrates, named explicitly:
   native-side rows come from `inventory.py` JSON; **target-side enumeration is the skill's own
   repo-tree scan** (`plugins/*/skills/*/SKILL.md` + `plugins/*/agents/*.md` frontmatter) —
   inventory.py scans installed trees, not necessarily the audited repo's.
7. **V1 sources** — built-in CLI commands + bundled skills (verdict-bearing, with hidden/gated
   markers). Cloud/session-provided skills: observation-only rows (defer verdict allowed, no baked
   lines) until an in-session capture protocol exists.
8. **V1 targets** — this repo's plugin skills and agents. Agents are registry-rows-only (no
   agent-file edits — role prompts load post-dispatch; actionable lines live at the dispatching
   skill's surfaces).
9. **Freshness** — a deterministic self-check script (exit 0 ok / 1 broken / 3 degraded), shipped
   as a skill deliverable and wired into CI or a loop lane. Its deterministic scope (amended
   post-validation — offline CI cannot decide that an upstream *event* fired): per-row trigger
   **presence**, record well-formedness, store↔generated-view parity, store↔baked-line parity, and
   locally decidable comparisons (e.g. store-recorded cli_version vs the current binary/inventory
   snapshot). Evaluating whether an event-based trigger actually *fired* (re-fetching the basis)
   is a session act performed by the audit skill's report, not by CI. `/claude-ops:changelog` is
   an on-demand semantic diff aid, not the refresh trigger (it has never completed an automated
   run here and is blind to server-side drift).
10. **Foreign-repo posture** (added post-validation) — the skill is repo-generic: store/registry
    paths are configurable (claude-ops userConfig precedent), and in a repo without this
    marketplace's conventions tree or CI gates, bare invocation degrades to report-only with the
    baking/apply machinery unavailable rather than erroring. CI wiring is a this-repo deliverable,
    not a skill deliverable.

### Constraints

- Naming grammar and `audit` mutation contract per `docs/PLUGIN-PHILOSOPHY.md`; skill `name`
  matches directory; portability checks (`check-skill-portability.sh`) must pass.
- Cross-plugin file imports forbidden — detection must reuse
  `${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py` from within claude-ops (same-plugin
  reuse only), which forces the packaging decision.
- Description edits respect the per-entry character cap and listing budget; presence-gated
  phrasing only — natives are plan/host/`disableBundledSkills`-gated, so any static availability
  assertion is wrong somewhere by construction.
- Repo process: PRs required, squash merge, Conventional Commits titles; fresh-docs mandate on
  manifest/schema claims; never hand-copy external docs — state the rule, link the source.
- Convention registry one-owner rule: the native-reference phrasing convention lands in an owner
  doc before any fleet-wide application.

### Acceptance criteria

1. `plugins/claude-ops/skills/audit-native-overlap/` exists, passes `skill-quality:check` and the
   repo's deterministic check scripts; bare invocation produces a report and mutates nothing.
2. The verdict/record store exists with at least the seeded canonical pairs at **skill-level
   target granularity with a source-class field** (bundled skill `code-review` vs
   `review:code-review`; bundled skill `simplify` vs `code-tidying:tidy` and
   `code-tidying:batch-simplify`; built-in command `security-review` vs
   `review:security-review`; bundled skill `run` vs `testing:run-e2e`; plus peers found during
   detection), every row carrying a verdict from the 5-value enum, evidence, a class-tagged
   observation record, and a per-row recheck trigger + verified date — the **initial verdict
   session is part of this build** (the PR author is the human gate) — and
   `docs/NATIVE-SURFACES.md` is generated from it.
3. The self-check script exits 0/1/3 and fails on trigger-less rows, malformed records,
   store↔view drift, store↔baked-line parity breaks, and failed locally-decidable comparisons
   (per locked decision 9's deterministic scope); it is wired into CI (or a loop lane) in the
   same change set, with an explicit exit-3 policy (Q15).
4. The native-reference phrasing convention doc exists with a registered owner.
5. The apply step, given approved verdicts, emits description phrases + Boundary sections, is
   **demonstrated on a claude-ops-internal component** (claude-ops is already bumping in this
   change set; other plugins' edits are sweep units under Q14), and parity is
   **direction-sensitive**: every baked line must trace to a store row, while a verdict row
   without a baked line is legal pending-sweep state. Nothing is applied on bare invocation.
6. The execution contract for the baking sweep (bulk application) is **written into the skill**:
   one plugin at a time — apply, verify (parity check + `skill-quality:check` + plugin version
   bump + CHANGELOG note), PR, close; a unit is closed only when its PR merges green. Sweep
   *execution* is Q14 (USER-RESERVED), not part of this build.

### Captured assumptions

- `inventory.py`'s JSON is the detection substrate, but its integrity block guards
  *extraction-level* drift only, not the emitter's own top-level key names (validated against
  `inventory.py:596-672`) — so the consumer MUST assert `schema == 1`, presence-check every key it
  reads, and report a missing key as `broken` consumer-side. This is a requirement, not an option.
- claude-ops takes a minor version bump for the new skill (additive change, semver minor). The
  bump drags two coupled edits into the same change set: the plugin.json "Ten skills: …"
  description rewrite and `docs/CATALOG.md` regeneration.
- The seeded canonical-pairs list is maintained in the skill's reference data (candidates only);
  verdicts live in the committed store; the registry doc is generated output.

### Out-of-scope

- MCP tools as sources (`mcp-tools:audit` owns that domain); our hooks as targets; our commands as
  targets (component class is empty — `commands/` is Prohibited).
- Cloud-lane capture protocol (in-session roster probe) — deferred post-V1; until then cloud rows
  are observation-only.
- Telemetry-driven verdict evidence (skill-usage.jsonl routing data) — post-V1 enhancement.
- Automatic verdicts or automatic baking of any kind.
- The undocumented bundled keep-set behavior (bundled descriptions possibly protected from budget
  dropping — single-source binary evidence, MEDIUM): no registry row or phrasing guidance builds
  on it until a live probe confirms it (post-V1; the routing asymmetry it would imply is noted in
  the phrasing convention doc as an open consideration, nothing more).

### Deferred questions

- Q12 (arbiter: /planning:plan): registry self-check placement — ci.yml gate vs loop-lane step vs
  both; pick with plan-time knowledge of CI cost and lane cadence.
- Q13 (arbiter: /planning:plan): exact registry column layout and generation format (single table
  vs per-source-lane sections), and where the seeded canonical-pairs data file lives inside the
  skill.
- Q14 (arbiter: USER-RESERVED): whether/when to run the fleet-wide baking sweep after the skill
  lands — the sweep touches many plugins' descriptions (routing-affecting) and is a separate
  human go/no-go beyond this build.
- Q15 (arbiter: /planning:plan): the wired gate's exit-3 policy under chronic degradation — the
  substrate is `degraded` on every run today (`VALIDATED_AGAINST = "2.1.228"` vs vendored binary
  2.1.232 vs upstream 2.1.241) — and whether bumping `VALIDATED_AGAINST` (with revalidation) is
  in this change set's scope.

## Plan

*(empty — /planning:plan fills this)*
