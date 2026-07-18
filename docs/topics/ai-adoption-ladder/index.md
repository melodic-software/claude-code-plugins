# ai-adoption-ladder — work-package index

Parent topic for the AI-adoption-ladder effort (Boris Cherny's "Steps of AI Adoption",
Jul 16 2026): climb any adopting org/repo/user from step 2 (human-supervised agents) toward
step 3 (governed autonomous agents) and eventually step 4 (closed loop), machine-, org-,
user-, and tool-agnostic.

Contract set: seven resolved design threads (T1–T7) from wayfind map claude-code-plugins#239
(closed). Design slice: `design/` (design-threads.md is the contract record; RESEARCH-*.md are
the evidence base; boris-step-and-your-role.txt is the captured source artifact). Session
working memory (checklists, drafts) stays in gitignored `.work/ai-adoption-ladder/`.

## Work packages

| WP | Topic slug | Contract source | Status |
|----|-----------|-----------------|--------|
| WP1 | `ai-ladder-wp1-packaging` | cross-cutting (T4 + #241 deferred packaging) | Brief locked |
| WP2 | `ai-ladder-wp2-telemetry` | T6 telemetry unification | Brief locked |
| WP3 | `ai-ladder-wp3-return-accounting` | T5 return accounting | Brief locked |
| WP4 | `ai-ladder-wp4-trigger-dispatch` | T1 trigger layer | Brief locked |
| WP5 | `ai-ladder-wp5-guardrails` | T2 sandbox bar + T3 guardrail matrix + #241 instance | Brief locked |
| WP6 | `ai-ladder-wp6-routines` | T7 standing routines | Brief locked |
| WP7 | `ai-ladder-wp7-runner` | T4 runner charter (build trigger-gated) | Brief locked |

Dependency order: WP1 blocks file layout everywhere; WP3 joins on WP2's work-item attribute;
WP6 needs WP4 adapters + WP5 matrix; WP7's Brief locks now, build waits on the T4 trigger.

Each package: `/planning:interview` locks the Brief in `docs/topics/<slug>/PLAN.md`, then
`/planning:architect` fills the Plan section.
