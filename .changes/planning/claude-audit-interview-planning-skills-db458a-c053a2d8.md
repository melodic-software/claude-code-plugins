---
bump: minor
---

### Added

- **Interview: the user's intent and vision.** The Brief's Goal carries `Intent (why, in the user's words)`, `Vision (where this heads)` and `When goals conflict, prefer` lines, quoted from the user or `none stated`.
- **Interview as the ideation hub.** A half-formed idea routes to `/planning:brainstorm` and product work to `/planning:prd`; the interview reads brainstorm's Handoff block, opens with the problem when the request has none, and may hold back its recommendation on a why or direction question. The composition table, now in `context/composition.md`, names every ideation and discovery skill.
- **PRD: Vision and Assumptions.** Each tier gains a Vision line and an Assumptions section; the interview seeds the Brief's Problem and Captured assumptions from them.
- **Plan: load-bearing assumptions.** The Brief's Captured assumptions become a `### Load-bearing assumptions` table (assumption, source, falsifying check, response if false); the Goal names the Problem it serves and quotes the Brief's Intent and Vision lines. `review` re-plans from a divergence, reading DEVIATIONS.md and re-presenting for approval.

### Changed

- **Brainstorm** confirms the problem and the user's why before grounding, asks for the user's own ideas first, allows non-code candidates and an optional landscape pass, records why picks resonate, and writes a Handoff block on its way to interview, PRD or design. Problem-framing gains an "Idea-stage requests" section where the user's named solution is one candidate; spec-stage requests are unchanged.
- The Brief's variation line is now `Variation intent:`.
- Plan: the Alternatives table has a switch-condition column, Medium plans include alternatives, dependency rows carry version and source, deferred interview questions get Decisions rows, and the PLAN.md anatomy lists the plan's sections.

### Fixed

- Brainstorm no longer contradicts itself (one question against a full problem framing, a rule forbidding alternatives to a named solution, a spike clause against "builds no throwaway code").
