# Composition with other skills

Every skill `/planning:interview` hands to, detours through, or receives from. A skill marked
"(if enabled)" lives in another plugin: invoke it via the Skill tool when that plugin is enabled,
otherwise do the step inline or name it to the user.

| When | Skill | How it composes |
|---|---|---|
| Pre-task fuzzy intent or lock-the-brief | **`/planning:interview`** (this) | Produces PLAN.md Brief |
| Idea stage: a half-formed idea, no settled problem or direction | `/planning:brainstorm` | Upstream entry; explores approaches and writes a `## Handoff` block to `<memory_dir>/<topic-slug>/brainstorm.md` that seeds the Brief (SKILL.md "Intake the starting point") |
| A product or feature idea to stress-test before building it ("should I build this") | `/planning:interview product` (this skill's `product` action) | Recommend, never auto-switch; [`product.md`](product.md) runs one question per turn from the twenty principles and ends in a verdict, not a Brief |
| Product intent fuzzy (whose problem, what success) | `/planning:prd` | Upstream of `/planning:interview`; PRD answers *what for whom and why*; its Problem and Assumptions seed the Brief ([`loop.md`](loop.md) "Constraint ledger") |
| Territory unfamiliar to the user | `/discovery:blindspot` (if enabled) | Before round 1; surfaces the user's unknowns so they can assess options |
| A question rests on why something was built this way | `/discovery:trace-intent` (if enabled) | Recovers the original rationale from evidence outside the code before a recommendation leans on it |
| The topic has been attempted before | `/session-flow:recall` (if enabled) | At the survey: what past sessions tried, kept and reverted, so rounds do not re-litigate it |
| Need codebase grounding | `/discovery:explore` (if enabled) | Reads PLAN.md Brief as scope |
| Need external evidence | `/discovery:research` (if enabled) | Reads PLAN.md Brief as scope; its deep tier covers a multi-source sweep |
| A question needs something built to react to | `/prototype:explore-directions` (look and feel) or `/prototype:pressure-test` (logic, state, data shape) (if enabled) | Mid-interview detour: confirm scope and checkpoint, build the throwaway, react to it, return and answer in one line |
| A domain term resolves, or is used two ways | `/domain-driven-design:curate-language` (if enabled) | Inline vocabulary update between questions (SKILL.md Stance, item 4) |
| Domain events, processes or context boundaries are unclear | `/event-storming:methodology` or `/event-storming:simulation` (if enabled) | Detour to model the domain; resolved terms and boundaries come back as answers |
| Who the users are, or how a flow should work, is unsettled | `/user-experience:shape` or `/user-experience:evaluate` (if enabled) | `shape` grounds users and flows before acceptance criteria; `evaluate` checks an existing flow or prototype |
| Acceptance criteria for an LLM-based feature | `/evals:design` (if enabled) | Turns the criteria into measurable success criteria and eval cases |
| An option adds a non-trivial mechanism | `/overengineering:justify` (if enabled) | Planned mode on the proposal; its drop and needed verdicts feed the recommendation (SKILL.md "Before presenting an option that adds a mechanism") |
| The current approach is assumed rather than chosen | `/planning:devils-advocate incumbent` | Attacks the status quo before the Brief locks it in |
| A branch defers to another person's decision | `/planning:questionnaire` | Turns the question into a document that person fills in (SKILL.md Step 5) |
| The effort is too big and still foggy | `/planning:wayfind` | Charts it as a decision map from this ledger (SKILL.md Stance), after the scope cut below when the effort is over its budget |
| Design types, contracts, module boundaries | `/planning:design` | Reads PLAN.md Brief; its handoff writes PLAN.md `## Design` |
| Plan the implementation | `/planning:plan` | Reads PLAN.md Brief + `## Design` + explore + research findings |
| Stress-test the plan | `/planning:devils-advocate` | Adversarial pass on `/planning:plan` output |
| Validate the interview's answers via agents | `/planning:audit-answers` | Fresh validators challenge each answer in the filled ledger (hand-answered or auto-accepted); only the doubtful ones return as human questions. The Step 3 recap and `--procedure` check show the Q&A and that the procedure ran; this re-validates the answers, and neither duplicates the other |
| Record a decision that earns an ADR | `/architecture:record-decision` (if enabled) | Owns ADR convention discovery, the no-convention offer-and-defer, and the write; without it the interview writes to the declared convention or defers |
| Pause and resume later | `/session-flow:workflow` (if enabled) | Routes the continuation; the ledger and Brief carry the state (SKILL.md Step 5) |

## Scope cut before wayfind

When the effort is plainly too big for its budget (more capabilities than its people and time can
deliver), run a scope-cut round before recommending `/planning:wayfind`, in round 1 when the
request already shows it. For each capability, ask or apply the Must test (if this is not
delivered, is the effort cancelled or worked around?): cancelled makes it a Must, worked around
puts it in a lower bucket. Ask it as one question whose recommendation lists each capability's
MoSCoW bucket (Must, Should, Could, or Won't this time) under `Commits you to:` (SKILL.md Stance),
so the user can overturn any one. Keep Must to about 60% of the effort or less, and route the rest
to later work, or to `/planning:wayfind` once the fog trigger in [`routing.md`](routing.md) holds.
Eval evidence: case `interview-scope-cut-moscow`.

## Mid-interview composition

In `me` mode, research, exploration, and prototyping are not only downstream. Invoke them *during* the interview when a recommendation needs external/codebase grounding or when a question needs something built to react to; when branches outgrow the session, recommend routing the continuation with `/session-flow:workflow` (SKILL.md Step 5). Return to the open branch after. **The ungrillable question:** when a look, feel, or behavior question cannot be answered by asking. The user has to see the thing to know what they think. Stop grilling and route it to a throwaway prototype: `/prototype:explore-directions` (look and feel) or `/prototype:pressure-test` (logic, state, data shape), invoked via the Skill tool if enabled. Those skills gate their own model-initiated entry, so confirm the spike's scope with the user and checkpoint this interview before handing off. The detour leaves an active workflow. Checkpointing is persistence the interview already owes: the question registered `open` at ask-time, plus the ledger and Brief written per lock-in, which is what lets the open branch survive the detour. Then return to the open branch and resolve its question with a one-line answer. The prototype is the instrument that produces the answer, not a deliverable; it is thrown away.

`/planning:interview` is sister to `/planning:plan`: one resolves *what*, the other resolves *how*. They share the topic slug, share the directory, feed each other.
