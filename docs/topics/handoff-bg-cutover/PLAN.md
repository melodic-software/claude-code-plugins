# Handoff --bg cutover — background delegation as its own skill (#233)

## Brief

### TLDR

- New session-flow skill `continue-in-background`: background delegation
  extracted from `/handoff` — owns the dirty-tree gate, `claude --bg` launch,
  launch report, fallback-on-failure, and its own STOP rule.
- Shared engine doc `plugins/session-flow/reference/save-point.md`: save-point
  production, redaction pass, and rails resume prompt extracted from handoff;
  both skills become thin delivery wrappers citing it. No duplication, no
  runtime skill-to-skill invocation.
- Hard cut: `--bg` removed from `/handoff` outright — no alias, no warn
  window. `feat!` commit; session-flow minor bump (0.x breaking convention,
  precedent PR #179).
- Docs fix rides along: surface the launched session's fresh-session behavior
  (no CLI-config inheritance; model/effort resolve from launch flags and the
  launch directory's settings, not the current session).

### Goal

`/handoff --bg` buries a distinct user intent — "delegate the task to a
background session now" — behind a flag on a skill whose name and default flow
mean "save a snapshot, `/clear`, resume later by hand". Outcome: background
delegation gets an honestly named, discoverable entry point
(`/session-flow:continue-in-background`) while `/handoff` keeps only the
save-point/pause/resume-later job, with the shared machinery owned once.

### Constraints

- Direction A (own command), locked 2026-07-21 — do not relitigate. Clean
  cut: no deprecated alias, no legacy window, no duplicated engine content.
- Shared-engine shape over runtime composition: the engine doc is cited via
  `${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`; neither skill invokes the
  other at runtime. Precedents: session-flow `reference/topic-docs.md`,
  re-anchor `context/re-anchor-audit-correct.md`.
- Trigger-phrase partition: background phrases move from handoff's
  frontmatter description to the new skill's; zero overlap left.
- New skill is model-invocable (`disable-model-invocation: false`) with an
  explicit-intent launch gate (launch only when the user explicitly asked;
  never self-elected) and an eval covering the gate.
- Fresh-docs mandate (repo `CLAUDE.md`): official doc pages fetched and cited;
  markdownlint; check-jsonschema via pipx/direct, not npx; root README only
  via `node scripts/generate-catalog.mjs`.
- PR required; squash merge; Conventional Commits title (`feat(session-flow)!:`).

### Acceptance criteria

- `/session-flow:continue-in-background` exists: frontmatter partition done,
  explicit-intent gate stated in the body, delivery steps (dirty-tree gate,
  launch, report, fallback, STOP) owned there, launched-session behavior
  documented with official-doc citations.
- `/handoff` has no `--bg` surface anywhere (frontmatter, arguments, body,
  checklist, evals).
- `reference/save-point.md` owns save-point production + redaction + rails
  prompt; both skills cite it; no duplicated engine content in either.
- Handoff's two `--bg` evals migrate to the new skill's evals (rephrased);
  handoff keeps default-path coverage.
- session-flow `plugin.json` (ten skills, new description), `README.md`,
  `CHANGELOG.md` updated; version bumped 0.12.4 → 0.13.0.
- All repo gates green: check-skill (both skills), evals schema,
  changelog-parity, markdownlint, validate-plugin-contracts.

### Out-of-scope

- claude-ops lanes' `claude --bg` usage (CLI flag, unrelated).
- CHANGELOG history lines and `docs/topics/ai-adoption-ladder/*` (historical
  records — never rewritten).
- "Home base" stay-and-monitor mode (in-session Agent-tool subagent) —
  deferred on #233; trigger: demand for monitored background work.

## Plan

1. **Gate seam (skill-quality).** `check-skill.sh` check 3 hard-fails any
   dropped quoted trigger phrase, with no sanctioned path for a deliberate
   move — discovered during implementation; the gate predates any trigger
   partition. Root-cause fix, not a bypass: a dropped phrase that reappears
   verbatim in a sibling skill's listing text under the same skills root is
   reported as a move (WARN, passes) — listing coverage is preserved, which
   is the regression the check exists to catch. Phrases absent everywhere
   still FAIL. New test case in `check-skill.test.sh`; skill-quality
   CHANGELOG + version bump.
2. **Engine doc.** Extract save-point production (destination resolution,
   locate-position, path choice, file write, redaction, rails prompt) from
   handoff SKILL.md into `reference/save-point.md`, delivery-agnostic.
3. **Thin handoff.** Rewrite handoff SKILL.md as a delivery wrapper: citation
   of the engine + `/clear`-then-paste delivery + STOP gate. Remove every
   `--bg` surface; drop background triggers from the description.
4. **New skill.** `skills/continue-in-background/SKILL.md`: description owns
   the background trigger phrases; body = explicit-intent gate, engine
   citation, launch sequence (dirty-tree gate → launch → report → fallback →
   STOP), launched-session behavior docs. Evals: migrated no-intent-no-launch
   and dirty-tree-fallback cases + explicit-request happy path.
5. **Plugin surfaces.** plugin.json (description, 0.13.0), README (table +
   sections + network paragraph), CHANGELOG entry, root README regenerated
   via `node scripts/generate-catalog.mjs`.
6. **Verify.** check-skill on both skills, evals schema validation,
   changelog-parity, markdownlint, plugin-contract validation; fresh-context
   reviewer pass; PR → green → squash-merge → close out #233.
