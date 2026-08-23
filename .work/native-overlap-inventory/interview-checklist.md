# /planning:interview Checklist — native-overlap-inventory

Topic: capability that inventories built-in/bundled Claude Code surfaces, detects overlap with this
marketplace's own skills/agents, and (optionally) bakes "prefer native" routing into our components.
Branch: `claude/cli-skill-inventory-v7hi82`. Mode: `me` (relentless), engineering domain.

## Steps

- [x] Step 1: Survey before you ask — read claude-ops:inventory SKILL.md, AGENTS.md, docs/topics/shadowed-skill-renames PLAN.md (cross-plugin reference rules), plugin listing
- [x] Step 1.5: Auto-detect — SKIPPED (user forced `me` mode)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Stop condition — register gate + user confirmation
- [ ] Step 4: Persist the contract — PLAN.md Brief at docs/topics/native-overlap-inventory/
- [ ] Step 5: Hand off — /discovery:explore, /discovery:research, /planning:brainstorm as user requested

## Session-shorthand glossary

- **native surface** — anything Claude Code itself provides: built-in CLI commands, bundled skills, environment-provided skills (e.g. cloud-session skills), built-in agents/tools
- **overlap** — a marketplace component whose purpose materially intersects a native surface (e.g. review:code-review vs built-in code-review skill)
- **bake in** — persist the overlap verdicts into the marketplace components themselves (soft references, routing notes) rather than only reporting them

## Open-question register

- Q1 | answered | round 1 | What artifact shape does "bake in" take? | Two layers: generated SSOT registry doc (e.g. docs/NATIVE-SURFACES.md) with verdict + evidence + verified date per overlap, PLUS one guarded soft-reference line per overlapping SKILL.md (accepted recommendation)
- Q2 | answered | round 1 | Where does the capability live? | Sibling skill in claude-ops (e.g. claude-ops:audit-native-overlap); audit = read-only, baking behind explicit apply step (accepted recommendation)
- Q3 | answered | round 1 | Who decides an overlap verdict? | Auto-detect candidates with evidence + RECOMMENDED verdict; human gates every verdict before any SKILL.md is touched (accepted recommendation)
- Q4 | answered | round 1 | Preference policy per overlap? | Per-overlap verdict enum: prefer-native / prefer-ours (with reason) / complementary / superseded — no blanket rule (accepted recommendation)
- Q5 | answered | round 1 | V1 scope — sources × targets? | Sources: built-in CLI commands + bundled skills + session/environment skills, each tagged by environment (local CLI / cloud / both). Targets: this repo's skills and agents. Deferred: our commands/hooks as targets, MCP tools as sources (accepted recommendation)
- Q6 | answered | round 1 | Refresh trigger? | On CLI releases via /claude-ops:changelog ingestion + on-demand runs; registry rows carry verified dates (accepted recommendation)

Note: round-1 closing probe (other-repo portability; any known prefer-native/superseded case today)
was not explicitly answered — carried as validation input for /planning:audit-answers and, if still
open after, a Brief deferred question.

## Decision tree (`me` mode)

- [x] Baking mechanism (Q1) — registry SSOT + per-skill soft references
- [x] Packaging/home (Q2) — claude-ops sibling skill
- [x] Verdict authority (Q3) — auto-candidates, human-gated verdicts
- [x] Preference policy shape (Q4) — 4-value verdict enum
- [x] V1 scope: sources × targets (Q5) — native surfaces (env-tagged) × our skills+agents
- [x] Refresh/drift trigger (Q6) — changelog-triggered + on-demand
- [ ] Environment-conditional availability handling (cloud vs local surfaces) — folded into Q5 env tags; wording of guarded references to be validated by audit-answers
- [ ] Validation depth ("empirically true") — inherited from claude-ops:inventory integrity machinery; audit-answers to challenge sufficiency
- [ ] Handoff sequencing (explore/research/brainstorm order) — next: audit-answers → explore/research → brainstorm → plan

## Resolved (round 1, 2026-08-23)

User: "Lets go with all your recommended" — Q1–Q6 resolved to the recommended answers, then
requested /planning:audit-answers to validate the auto-accepted set.
