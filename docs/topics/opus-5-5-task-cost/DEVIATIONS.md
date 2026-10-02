# Deviations: opus-5-5-task-cost

Append-only. Types: plan-confirmed, discovery, deviation, human-decision.

- **deviation (Phase 1):** plan said the main session writes the record; found it needs all 49 ledger rows in context; chose an `implementer` worker (opus, orchestrator commit authority) with the issues and the commit kept main-side; revisit: none. Evidence: commit 1 of this branch.
- **deviation (Phase 1):** the record's Q18 row claimed planning read the gap rows and ritual patterns; the phase-verifier found no such read; chose to mark the row OPEN; revisit: user decision (fold into Phase 6, or a sub-issue of #5763). Blocking for the record's Q18 row only.
- **deviation (Phase 1):** Brief TLDR and one acceptance criterion still described the Q42 "point" outcome; amended to "keep" to match the approved Q42 answer. Evidence: `PLAN.md` TLDR and Acceptance criteria.
- **discovery:** Sequencing says Gate S1 holds Phase 5 step 8; the phase text and Execution shape say step 9. Treated step 9 (`docs/plugin-philosophy.md`) as gated.
- **discovery:** `clean.test.sh` lives under `scripts/`, not `otel/`. Phase 4 ran it there.
- **discovery:** #5719 (209209449) removed `docs/specs/` and the topic-docs convention; plans now live in the PR body and linked issue. Chose: keep this slice on the branch while work runs, prune it in Phase 7 after moving the plan into #5763 and the PR body; Phase 2's `docs/specs/prompt-audit-skills-2026-09.md` row (Q48) is moot after the Gate S1 merge. Unverified until Phase 7.
- **deviation (Phase 5):** plan said the provider check reads three env vars; the worker added `CLAUDE_CODE_USE_ANTHROPIC_AWS` and `CLAUDE_CODE_USE_MANTLE`, which model-config#model-aliases and env-vars name; a false match only routes to the stronger implementer. Kept.
- **discovery (Phase 5):** `prompts/loops/loop-lane-profile-claude-code-plugins.md:192-199` says implementer dispatches pass no model, which predates scoped-implementer. Outside the Phase 5 fence; do it with Phase 5 step 9.
- **discovery:** version bumps were set against origin/main 126d0b058, ahead of the branch base; the Gate S1 merge will conflict in the implementation, planning, work-items and claude-ops manifests and CHANGELOGs. Resolve by keeping this branch's version and ordering its entry first.
