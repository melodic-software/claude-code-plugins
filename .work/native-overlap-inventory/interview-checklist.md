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

- Q1 | open | round 1 | What artifact shape does "bake in" take (registry doc, per-skill soft references, both, runtime router)? |
- Q2 | open | round 1 | Where does the capability live (claude-ops extension, plugin-quality, new plugin)? |
- Q3 | open | round 1 | Who decides an overlap verdict — auto-applied or human-gated per overlap? |
- Q4 | open | round 1 | Preference policy per overlap — always prefer native, or per-case verdict set? |
- Q5 | open | round 1 | Which native sources and which marketplace targets are in scope for V1? |
- Q6 | open | round 1 | Refresh trigger — when does the overlap map get re-derived? |

## Decision tree (`me` mode)

- [ ] Baking mechanism (Q1)
- [ ] Packaging/home (Q2)
- [ ] Verdict authority (Q3)
- [ ] Preference policy shape (Q4) (blocked by: Q1)
- [ ] V1 scope: sources × targets (Q5)
- [ ] Refresh/drift trigger (Q6)
- [ ] Environment-conditional availability handling (cloud vs local surfaces) — round 2+
- [ ] Validation depth ("empirically true") — round 2+
- [ ] Handoff sequencing (explore/research/brainstorm order) — round 2+
