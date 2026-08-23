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

## Audit-answers validation (2026-08-23)

Three fresh-context validators, full answer set each, rationale withheld. Merged verdicts:

- D1 (Q1 baking shape) — CHALLENGED (B, C): SKILL.md body lines never reach the model's routing
  decision (descriptions are the always-in-context surface; official skills doc + repo's own
  description-routing idiom); registry rows lack per-row recheck triggers required by
  docs/conventions/upstream-drift; cross-boundary citation of docs/NATIVE-SURFACES.md from shipped
  plugins is a broken ref (check-skill.sh resolves only within plugin root); no parity mechanism.
- D2 (Q2 packaging) — CONFIRMED (A, B, C): claude-ops co-location structurally forced (inventory.py
  is the only extractor; cross-plugin file imports forbidden); audit verb contract matches; no
  existing skill owns overlap verdicts (scope boundaries checked). Obligation: skill must be
  repo-generic (claude-ops ships to consumers).
- D3 (Q3 verdict authority) — human gate CONFIRMED (all); detection half CHALLENGED (B): live run
  showed bundled-skill list is a floor (34/424 registrations resolved), evidence is one-line
  menuDescription only, no cloud extractor — auto-detection under-recalls.
- D4 (Q4 verdict enum) — CHALLENGED (C, narrow): no uncertainty state; every in-repo verdict
  vocabulary has one (Adopt/Defer/Decline, Wait, ok/degraded/broken). Add defer/undetermined.
- D5 (Q5 scope) — CHALLENGED (B): session/environment skills unenumerable from outside a session;
  static local/cloud/both tag untruthful (bundled skills runtime-gated: commit, pr, loop, claude-api
  gated:True). C: agents coherent as registry-rows-only targets, no agent-file edits.
- D6 (Q6 refresh) — CHALLENGED (A, B, C unanimous): changelog trigger blind to server-side cloud
  drift; aspirational (zero "address Claude Code v" commits — the pipeline never completed a run);
  repo's proven pattern is self-announcing drift (--self-check exit codes in CI/lane), not dates.

Blind spots recorded: cloud-lane capture protocol undefined; native-reference phrasing convention
needs an owner doc (seam-phrasing covers cross-plugin only); no enforcement owner for baked-line
truthfulness (needs mechanical parity/freshness check); disableBundledSkills + plan/host gating
means lines must be read-time presence gates; description listing budget (1,536-char cap, 1%
context budget with silent drops) constrains description-side references.

## Open-question register (round 2 — audit confirm round)

- Q7 | open | round 2 | Where does routing-effective "prefer native" text live (descriptions vs body vs both), and what fixes the registry row shape? |
- Q8 | open | round 2 | Add a fifth defer/undetermined verdict to the enum? |
- Q9 | open | round 2 | Demote cloud/session skills to observation-only (no verdicts, no baked lines) for V1; env tag as observation record; agents registry-rows-only? |
- Q10 | open | round 2 | Replace changelog-as-trigger with a shipped registry self-check (CI/lane wired) + per-row triggers; changelog kept as on-demand diff aid? |
- Q11 | open | round 2 | Accept floor-honest detection (inventory output + seeded canonical pairs + human-added candidates, integrity status carried) for V1? |
