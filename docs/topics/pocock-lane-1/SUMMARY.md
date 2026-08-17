# Lane 1 summary: handoff (issue #2899)

First of six vetting lanes under the `pocock-course-lanes` contract
(`docs/topics/pocock-course-lanes/PLAN.md`). Closed 2026-08-17. Scope: the course handoff lesson
and upstream `skills/productivity/handoff/SKILL.md` (read at `068b6e0`) against our
`session-flow` save-point engine.

## Decisions (register Q10 through Q19; rows in `docs/upstream/aihero-course.md`)

- **Use-case boundary (Q10):** UNION. Our session-chain use (dumb-zone escape, session-ID chain,
  retrospective reconstruction) becomes a named first-class use case alongside his
  crossing-boundaries taxonomy (other agent, other repo, colleague, forked side task).
  Deliverable is routing signals for which form to use when, filed as #2956.
- **Purpose argument (Q11/Q16):** ADOPT as optional trailing free text,
  `[file|prompt] [topic] [purpose...]`. Emphasis-only tailoring; never drops sections; the
  resume-prompt shape (find-handoff detection contract) is untouched; Original-goal immutability
  wins over a contradicting purpose. Filed as #2955.
- **Placement and expiry (Q12/Q13):** keep `<memory_dir>/handoffs/` (memory tier), REJECT OS
  temp, accumulation by design, cleanup is user-controlled removal and never silent expiry.
  Confirms the #1477 finding-4 rejection rather than reversing it (retention is load-bearing for
  retro chain-walk and find-handoff recovery).
- **Worktree caveat (Q17):** a handoff written inside a worktree dies with
  `git worktree remove`; acceptable only when the worktree completes as a merged PR unit;
  otherwise write from the main checkout or rely on clean-stop's preserve-before-remove step.
  Wording lands via #2956.
- **Promote-on-value (Q18):** default no uplift; promote the content, never the file. Durable
  value moves into committed artifacts (topic contract, issue, PR body); no handoff file is ever
  committed. Via #2956.
- **Do-not-duplicate rule (Q14):** ADOPT explicitly in the skill body, mirroring upstream
  wording. Via #2956.
- **Model invocation (Q15):** REJECT his `disable-model-invocation: true`. Keep model-invocable
  under strict trigger discipline; proactive handoff prompting and instrument-triggered forks
  depend on it, and user-only skills lose skill-to-skill reach.
- **Minimalism and parity rows:** 15-line minimalism REJECTED (the engine is accumulated
  incident response; prompt-only mode is our minimal tier); suggested-skills section and
  redaction COVERED at parity or stronger.

## Work items filed (changes execute outside the lane)

- #2955: purpose argument across the save-point engine (behavior change).
- #2956: routing-signals table, do-not-duplicate rule, worktree caveat, promote-content rule
  (skill-body and reference wording).
- #2957: context-guard zone capture is statusline-teed and silent in cloud/headless sessions
  (surfaced while deciding Q15; verified live in this container).

## Parked to other lanes

- Lane 2 (#2900): the non-interactive continuation pattern the user described (worker emits the
  handoff at a fork point; an orchestrator, standing in for the human, kills the worker and
  seeds a fresh agent with the resume prompt). This is the continuation-router build's
  territory.
- Lane 3 (#2901): zone-signal availability in cloud (see #2957) affects the compaction-doctrine
  discussion.

## Process notes

- Grounding: fresh-context explore of the session-flow handoff engine
  (verified PASS, 14/14 sampled claims confirmed) plus the prior inline explore; #1477
  finding-4 rationale fetched verbatim before deciding the expiry axis.
- This lane also created the `docs/upstream/aihero-course.md` skeleton per audit amendment A2
  (row schema and divergence-at-re-fetch trigger form fixed at creation); lane 6 (#2904) owns
  the coverage index and consolidation.
