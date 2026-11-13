# Pre-implementation order

This file is the one home for route choice before implementation: which planning pass runs
next. Other skills and docs point here rather than restating it. The sources behind
`docs/finding-your-unknowns.md` in the marketplace repository compose their pre-implementation
demos into one ordered flow, and this ladder adds the design, PRD, and decompose passes. The
marketplace ships a skill per pass; the composition itself is judgment, not a gate. New work whose
diff will not be quick to review and cheap to retry starts at the interview; the passes before
it run only when their unknown is present. Run the passes whose unknowns you actually have, in
this order when you run several:

1. **Blindspot pass**, `/discovery:blindspot`: surface unknown unknowns in the task's
   blast radius.
2. **Brainstorm / prototype**, `/planning:brainstorm` for direction candidates;
   `/prototype:explore-directions` or `/prototype:pressure-test` when the unknown is
   visual or interactive.
3. **Interview**, `/planning:interview`: convert known unknowns into decisions on the
   record. It calls a **PRD**, `/planning:prd`, only when a question shows the change is
   user-facing, business-driven, and needs alignment on the problem, the users, and the success
   metrics. When an interview outgrows one session because the effort is too big to hold at
   once and still too foggy to phrase as decisions, escalate to **wayfind**,
   `/planning:wayfind`, which charts a decision map from the interview's ledger and hands
   back once the fog clears. Wayfind is never the first pass.
4. **Reference port**, `/discipline:point-dont-copy` when the work leans on an external
   reference whose semantics must survive the port.
5. **Design**, `/planning:design` then `/planning:design-handoff`: settle module layout,
   contracts, and variation verdicts when the work adds types, contracts, modules, or a
   topology or data-model change; the handoff writes them into PLAN.md's `## Design`, which is
   how they reach the implementer. Work with no design question records a one-line early exit.
6. **Plan**, `/planning:plan`: lock the approach with the unknowns now known.
7. **Decompose** (conditional), `/work-items:decompose`: only when the plan holds more than one
   independently shippable ticket; each ticket quotes its part of the design.

Notes: the sequencing is chat-portable. Every pass works as plain conversation, and the
artifact form is optional. The passes a person answers (interview through plan) run in one
session, and `/session-flow:workflow` suggests a handoff between them only when context-usage
reports zone `heavy`; execution of a finished plan moves to a fresh session with the artifacts
carried forward.

As everywhere in this skill, a pass whose skill the consuming setup does not install runs inline
or is named to the user; never invent a skill name.
