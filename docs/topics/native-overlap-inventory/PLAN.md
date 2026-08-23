# Native overlap inventory

## Brief

**TLDR:** Add a `claude-ops:audit-native-overlap` sibling skill that maps native Claude Code
surfaces (built-in CLI commands, bundled skills) against the current repo's plugin skills and
agents, records human-gated per-overlap verdicts in a generated SSOT registry
(`docs/NATIVE-SURFACES.md`) whose rows carry recheck triggers, and — only behind an explicit apply
step — bakes routing-effective, presence-gated native references into component descriptions plus
Boundary sections in bodies, with a deterministic registry freshness/parity check wired into CI.

### Goal

Every marketplace component whose purpose materially overlaps a native surface carries truthful,
routing-effective guidance about when to prefer or compose the native equivalent, sourced from a
single registry that announces its own staleness instead of decaying silently.

### Locked decisions

1. **Packaging** — new sibling skill in `claude-ops` (working name `audit-native-overlap`).
   Bare invocation is a read-only report; mutation only behind an explicit apply step (codified
   `audit` verb contract). Must be repo-generic: it targets "the current repo's plugin tree", never
   a hardcoded melodic-software layout (claude-ops ships to external consumers).
2. **Registry** — generated SSOT at `docs/NATIVE-SURFACES.md`. One row per overlap: native surface
   (with hidden/gated markers), our component, verdict + reason, evidence, environment observation
   record ("observed in <env> on <date>" — never a static availability assertion), and a four-part
   upstream-drift record with a per-row **recheck trigger** (a date alone does not qualify).
3. **Baked guidance** — routing-effective text lives in frontmatter *descriptions* (the surface
   always in model context), phrased as a read-time presence gate ("when the bundled X skill
   resolves in your session, prefer it for …; this skill for …"), within description budget. The
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
   candidates. Honest under-recall over confident completeness.
7. **V1 sources** — built-in CLI commands + bundled skills (verdict-bearing, with hidden/gated
   markers). Cloud/session-provided skills: observation-only rows (defer verdict allowed, no baked
   lines) until an in-session capture protocol exists.
8. **V1 targets** — this repo's plugin skills and agents. Agents are registry-rows-only (no
   agent-file edits — role prompts load post-dispatch; actionable lines live at the dispatching
   skill's surfaces).
9. **Freshness** — a deterministic registry self-check script (exit 0 ok / 1 broken / 3 degraded),
   shipped as a skill deliverable and wired into CI or a loop lane, keyed on per-row recheck
   triggers; plus a registry↔baked-line parity check. `/claude-ops:changelog` is an on-demand
   semantic diff aid, not the refresh trigger (it has never completed an automated run here and is
   blind to server-side drift).

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
2. `docs/NATIVE-SURFACES.md` is generated with at least the seeded canonical pairs (bundled
   `code-review` vs `review:code-review`, `simplify` vs `code-tidying`, `security-review` vs
   `review:security-review`, `run` vs `testing:run-e2e`, and peers found during detection), every
   row carrying a verdict from the 5-value enum, evidence, environment observation record, and a
   per-row recheck trigger + verified date.
3. The registry self-check script exits 0/1/3, fails on trigger-less or trigger-fired-stale rows,
   and is wired into CI (or a loop lane) in the same change set.
4. The native-reference phrasing convention doc exists with a registered owner.
5. The apply step, given approved verdicts, emits description phrases + Boundary sections for
   affected components and a parity check passes registry↔lines; nothing is applied on bare
   invocation.
6. Execution contract for the baking sweep (bulk application): one plugin at a time — apply,
   verify (parity check + `skill-quality:check` + plugin version bump + CHANGELOG note), PR, close;
   a unit is closed only when its PR merges green.

### Captured assumptions

- `inventory.py`'s JSON output schema (builtin_commands, bundled_skills, integrity block) is the
  stable detection substrate; a schema change surfaces as a `degraded`/`broken` integrity verdict,
  not a silent misread.
- claude-ops takes a minor version bump for the new skill (0.x breaking-by-minor precedent).
- The seeded canonical-pairs list is maintained in the skill's reference data, not in the registry
  itself (the registry is generated output).

### Out-of-scope

- MCP tools as sources (`mcp-tools:audit` owns that domain); our hooks as targets; our commands as
  targets (component class is empty — `commands/` is Prohibited).
- Cloud-lane capture protocol (in-session roster probe) — deferred post-V1; until then cloud rows
  are observation-only.
- Telemetry-driven verdict evidence (skill-usage.jsonl routing data) — post-V1 enhancement.
- Automatic verdicts or automatic baking of any kind.

### Deferred questions

- Q12 (arbiter: /planning:plan): registry self-check placement — ci.yml gate vs loop-lane step vs
  both; pick with plan-time knowledge of CI cost and lane cadence.
- Q13 (arbiter: /planning:plan): exact registry column layout and generation format (single table
  vs per-source-lane sections), and where the seeded canonical-pairs data file lives inside the
  skill.
- Q14 (arbiter: USER-RESERVED): whether/when to run the fleet-wide baking sweep after the skill
  lands — the sweep touches many plugins' descriptions (routing-affecting) and is a separate
  human go/no-go beyond this build.

## Plan

*(empty — /planning:plan fills this)*
