# Design-Level EventStorming

Design-Level EventStorming bridges the gap between process understanding and software implementation. It focuses on implementing software features that solve a specific problem, working within a single bounded context.

**Source note:** Core concepts from Alberto Brandolini's book (5-20% complete chapters). Sections marked with `[SUPPLEMENTED]` were enriched from authoritative external sources: Brandolini's blog/talks, EventStorming Journal (Philippe Bourgau), MrPicky.dev (Mariusz Gil), and DDD community practitioners.

---

## How Design-Level Differs from Big Picture and Process Modeling

| Aspect | Big Picture | Process Modeling | Design-Level |
|--------|------------|-----------------|--------------|
| **Goal** | Discovery & shared understanding | Solution convergence | Software design |
| **Scope** | Entire business line | Single end-to-end process | Single bounded context |
| **Participants** | 15-20+ (all stakeholders) | 5-10 (cross-functional) | 3-7 (mostly developers) |
| **Precision** | Low (fuzzy, intentional) | Medium (increasing) | High (implementation-ready) |
| **Key output** | Hot spots, bounded contexts | Completed process with color grammar | Aggregates, commands, events, ready-to-code model |
| **Duration** | 2-4 hours | 2-4 hours | 1-3 hours |
| **When it's over** | When learning plateaus | When all 4 win conditions met | When you have a robust candidate solution |

### Scope is Different

Big Picture embraced the whole; Design-Level **focuses** on implementing software for a specific problem. The starting assumption is that we already have a shared understanding from Big Picture.

### People are Different

Big Picture had many business stakeholders; Design-Level is primarily **developers and software architects**, possibly with domain experts available for clarification.

### Outcome is Different

Big Picture's most valuable outcome was **knowledge/learning**. Design-Level isn't over until we have something that looks like a **robust candidate solution**.

---

## Working with the Big Picture Artifact

The Big Picture artifact provides:

- A good-enough **dictionary of domain events**
- A highlighted **hot spot** indicating the problem to solve
- The current level of understanding of **external contexts**

**Two approaches:**

1. **Start from scratch** — cleanest option, provides fresh modeling space
2. **Work on the existing model** — works well in small groups or multi-day workshops where Big Picture memory is still vivid

---

## Design-Level Workshop Phases `[SUPPLEMENTED]`

*Sources: EventStorming Journal (Philippe Bourgau), MrPicky.dev (Mariusz Gil), DDD community consensus from conference talks and practitioner blogs. Cross-referenced with Brandolini's book content.*

### Prerequisites

- Completed Big Picture or Process Modeling for the target bounded context
- Participants: 3-7, mostly developers, with domain expert access
- Duration: 1-3 hours
- Materials: same as Process Modeling + pale yellow stickies for aggregates

### The Transition Funnel

Don't go directly from Big Picture to Design-Level — Process Modeling is the natural intermediate step.

| Format | Participants | Selection |
|--------|-------------|-----------|
| Big Picture | 15-20+ all stakeholders | Everyone |
| Process Modeling | 5-10 from Big Picture | Those relevant to selected process |
| Design-Level | 3-7 from Process Modeling | Mostly developers + domain expert |

**Selection criteria for which bounded context to Design-Level:**

- Highest business priority (arrow voting winner)
- Most complex area (most hotspots)
- Area with highest uncertainty
- **NOT** the simplest area — that wastes the method

**Timing:** Same day or next day is ideal (knowledge is fresh). More than a week gap requires replaying the model from photos.

### Step-by-Step Session Flow

*Core flow from Brandolini's book (Ch. 17, 20). Steps marked `[BOURGAU]` are enrichments from Philippe Bourgau's verified agenda (EventStorming Journal). Steps marked `[SUPPLEMENTED]` are from community consensus, not directly from Brandolini.*

**Step 1: Display "The Picture That Explains Everything"** (5 min)
Draw or display the canonical reference: `Read Model → Actor → Command → Aggregate → Domain Event → Policy → Command...`. Keep it visible throughout. This IS the workshop's grammar.

**Step 2: Bring in Domain Events** (5-10 min)
Carry over events from Process Modeling (or Big Picture). Place along timeline left-to-right. Add any missing events discovered since the last session.

**Step 3: Add Commands** (10-15 min)
For each event, add the command that triggers it. Often mechanical — reverse the verb tense: `Game Started` → `Start Game`. Commands that don't have obvious events, or events without clear commands, are discovery signals.

**Step 4: Add Actors, Policies, and External Systems** (15-20 min)

- **Actors** (yellow): who issues each command?
- **Policies** (lilac): which event-to-command transitions are reactive? ("Whenever X, then Y")
- **External Systems** (pink): which commands are handled by something outside this bounded context? `[BOURGAU]` "In the scope of a bounded context, other contexts become external systems too!" — place a pink sticky between command and event when another BC handles it. This makes integration boundaries visible BEFORE aggregate discovery

**Step 5: Add Read Models and UX Mock-ups** `[BOURGAU]` (20-30 min)
Place blank green stickies (Read Models) and optional white stickies (UX sketches) between events and actors — what information does the actor need to make a decision?

This is one of the **two critical discussion moments** (Bourgau): "Design-Level Event Storming is the perfect workshop to discuss the UX of domain events." Domain experts and UX people can work in PARALLEL here — UX sketches interfaces while domain experts discuss data needs. Fill in each Read Model with the specific information required. Fill UX stickies with wireframe sketches when visual elements matter.

**Step 6: Place Blank Business Rules** (5 min)
For every command-event pair NOT already linked by an External System (pink), place an **empty** pale yellow sticky between them. This is purely mechanical scaffolding — no thinking required yet.

Brandolini's "Postpone Naming" principle starts here: "One of the most interesting tricks is to try to postpone aggregate naming. This is hard, because at this moment everybody is thinking they have a good name for it, and the habit of naming things is really too strong." `[BOURGAU]` "Please don't call them aggregates! It's going to work better if you call them Business Rules."

**Step 7: Fill Business Rules — Discover Invariants** (20-30 min)
This is the **second critical discussion moment**. For each blank yellow sticky, ask participants to fill in:

- **Preconditions**: "What must be true before this command can execute?" `[BOURGAU]`
- **Postconditions**: "What is true after?" `[BOURGAU]`
- **Invariants**: "What rules must remain true all along?" (Brandolini: "properties that should always be true")

Brandolini's aggregate discovery approach — look for behavior, not data:

1. Look for **responsibilities** first — what is this yellow sticky responsible for?
2. Look for the **information needed** to fulfill this responsibility
3. "How would I call a class with this information and purpose?" (that's Step 9 — not yet)

"Some business rules are dead-simple, but others generate much discussion. This knowledge sharing between domain experts and developers is invaluable." `[BOURGAU]`

**Step 8: Group Business Rules → Aggregates** (15-20 min)
When two business rules deal with similar data or enforce related invariants, **move them on top of one another**. This BREAKS chronological order — the board transforms from a horizontal timeline into vertical stacks. That's expected — "the timeline breaks when you start grouping commands and events around aggregates. Timeline was for big-picture reasoning; responsibility is the driver for system design." (Brandolini)

Commands that must enforce the same invariant share an aggregate. Look for units of **consistent behavior** — aggregates as little state machines that accept or reject commands based on current state.

**Step 9: Name the Aggregates** (5-10 min)
NOW name them. "How would I call a class with this information and purpose?" Add a label sticky on top of each group. Naming is the LAST thing — "the habit of naming things is really too strong" and premature naming creates false confidence. (Brandolini)

**Step 10: Identify Bounded Context Contracts** (10 min)

- Which events need to be **published** to other contexts?
- Which commands come from **outside**?
- These are your integration events. `[BOURGAU]` If you placed External System (pink) stickies in Step 4, the contracts are already visible — formalize them here.

**Step 11: Wrap Up** (5 min)
Photo the wall. **Start coding ASAP** — "the roll is not the deliverable, it's just a way to get to the right implementation faster." (Brandolini) Also sweep the shared vocabulary the session pinned down: offer each resolved term for graduation into the consumer repo's committed project glossary (term + 1–2 sentence definition + `Avoid:` anti-synonyms; mechanics in `glossary-and-tools.md`) so the context's language outlives the wall photo.

### Post-Workshop Strategies `[BOURGAU]`

*Source: Philippe Bourgau — "7 Tactics That Will Make Your DDD Design-Level Event Storming Pay Off"*

1. **Highlight the Core** — draw subdomain boundaries around aggregate groups before leaving the room. Aggregates naturally group into subdomains
2. **Curate Views** — capture focused documents (domain definitions, key decisions, open questions). Board photos go stale quickly; curated views stay useful
3. **Run Example Mapping** — pick business rules and detail them into precise user stories with concrete examples using BDD's Example Mapping format (Matt Wynne). This is where edge cases and "What if?" scenarios get drilled into — not during the workshop itself
4. **Build a Walking Skeleton** — the best feedback comes from trying to implement. Build a minimalistic end-to-end slice ASAP — the same "thinnest thing that proves the design" discipline at both plan and execution altitude

**Critical anti-pattern: "EventStorming is NOT Big Design Up Front."** `[BOURGAU]` Never spend more than two full days on EventStorming total. The cycle: draft just enough to get started → build something → learn from it → repeat. If you're still modeling after two days, you're over-designing.

### DDD Vocabulary Translation `[SUPPLEMENTED]`

*Source: Philippe Bourgau — replace intimidating DDD terminology with workshop-friendly alternatives.*

| DDD Term | Workshop Language |
|----------|-------------------|
| Bounded Context | "Functional Area" |
| Ubiquitous Language | "Shared Vocabulary" |
| Aggregate | "Consistency boundary" or "the yellow sticky" |
| Upstream/Downstream | "Who has the upper hand in the relationship?" |
| Invariant | "Rule that must always be true" |
| Domain Event | "Something that happened" or "Fact" |

---

## Discovering Aggregates

Aggregates are **units of transactional consistency** — groups of objects whose state can change but should always expose consistency as a whole. They enforce **invariants** (properties that must always be true).

### Don't Start from Data

Looking at data to be "contained" in the aggregate is the wrong approach. Data-driven thinking leads to misleading agreements — everyone pretends to agree on a container, but the models are actually different.

**Critical distinction:** "Data to be displayed to a user in order to make a decision" will be a **Read Model**. Aggregates are something else — you must resist "this vicious temptation of superimposing what we need to see on the screen on the internal structure of our model. They're not the same thing." A shopping cart's `ItemDescription` is needed for display (Read Model), not for enforcing the invariant that the subtotal equals the sum of quantities times unit prices (Aggregate).

### Aggregates as State Machines

Look for **units of consistent behavior**. Aggregates look like little state machines — they receive commands and produce events based on their current state.

### Postpone Naming

One of the most valuable tricks: **postpone aggregate naming**.

1. Look for **responsibilities** first — what is this yellow sticky responsible for?
2. Look for the **information needed** to fulfill this responsibility
3. Once sorted out, ask: "How would I call a class with this information and purpose?"

People's habit of naming things is too strong — naming prematurely creates false confidence. Discover the behavior first, name it later.

---

## Design-Level Modeling Tips

### Make the Alternatives Visible

You won't agree on a solution before modeling it. When trapped in a "Religion War," model both alternatives side by side and compare.

### Choose Later

Defer commitment. Model multiple options, then choose the best one with full information.

### Rewrite, Then Rewrite Again

**Be prepared to rewrite stickies like there's no tomorrow.**

Two reasons this matters:

1. It's not software yet — you're only trashing sticky notes. Sunken cost fallacy shouldn't apply to paper.
2. In production, Domain Events have very high cost of update due to their many potential listeners. Anticipating naming precision while the model is still paper is smart.

### Hide Unnecessary Complexity

After solving a tricky problem, the internal model may be more complex than the original understanding. But the **visible** model shouldn't reflect all underlying complexity. Keep it simple on the outside for users.

### Symmetry Might Not Be Your Friend

Developers naturally look for semantic symmetry (`ReserveSeat` → `CancelReservation`). This is useful for exploration but the actual model may not be symmetric — different paths may have very different behaviors.

---

## From Paper Roll to Working Code

### Event-Driven CRC Cards

A technique for modeling interactions collaboratively after Design-Level EventStorming:

- **Humans** take the role of Users, Aggregates, Processes, and Projections (decision makers in the system)
- **Cards** represent Commands, Domain Events, and UIs (carrying information)
- Each human can produce output only based on available information
- "Tell don't ask" — humans can tell, not ask
- This sketches the communication patterns needed for event-based solutions

In agentic simulation, CRC Cards can be modeled by assigning each aggregate to a separate agent, then passing command/event cards between them to verify the interaction patterns work.

### The Roll is Not the Deliverable

"A post-it based model does not compile, nor it delivers a green bar. The roll is not the deliverable, it's just a way to get to the right implementation faster."

**Start coding as soon as you have a reasonably good idea about the underlying model.** There's nothing better than a good prototype to discover flaws in reasoning.

### Coding ASAP

The whole cycle started with discovering the most urgent matter. If the solution is software, there are very few reasons to slow down.

---

## From EventStorming to User Stories

### User Stories as Placeholders

EventStorming building blocks naturally map to user story elements:

- **Events** → acceptance criteria (did this happen? black-or-white verification)
- **Read Models** → acceptance criteria (is this information visible? verifiable)
- **User Interface** → trickier — usability and beauty aren't black-or-white

### EventStorming vs User Story Mapping

Both leverage key experts to trigger meaningful conversations. Key differences:

- **Scope**: User Story Mapping focuses on developing a new product; EventStorming has broader scope
- **Starting point**: User Story Mapping starts from User Actions (tasks); EventStorming from Domain Events (broader)
- **MVP focus**: User Story Mapping explicitly targets Minimum Viable Product slicing

The two approaches can be combined — "a lot of the conversations will be the same."

---

## Domain Events in Depth (Why They're Special)

### Events Are Easy

No previous experience required. "Something relevant that happens in our business, written on an orange sticky note with the verb at past tense." Even participants who've never modeled before can join immediately.

If "Domain Event" sounds too technical for your audience, use **"Fact"** or **"Thing that happened"** instead.

### Events Are Precise

The verb at past tense forces precision about **state transitions** — the exact moment something changes. Example: `Temperature Raised` (imprecise, weather smalltalk) vs `Temperature Registered` + `Temperature Increment Measured` (precise, system design).

Don't make it precise too early — initial imprecise writing is fine if it triggers further reasoning.

### Events Remove Blind Spots

Unlike starting from Commands or User Actions (which focus on user interaction only), Domain Events capture the **whole system** — including external systems, time-triggered events, and cascading consequences.

### Events as Triggers for Consequences

Domain Events are leading us towards the bottleneck — where events cluster and trigger many consequences, that's where complexity lives.

---

## Relationship to Your Architecture

Design-Level EventStorming maps directly to DDD tactical patterns. Each sticky-note color
materializes a concrete code element; the concrete type/interface names depend on your stack —
a common CQRS + DDD shape looks like:

| EventStorming Element | Tactical Pattern (typical implementation) |
|----------------------|---------------------|
| Aggregate (pale yellow) | Aggregate Root class (consistency boundary) |
| Command (blue) | Command message + command handler (`ICommand<T>` or equivalent) |
| Domain Event (orange) | Domain event type raised by the aggregate |
| Query/Read Model (green/yellow) | Query message + read-model projection (`IQuery<T>` or equivalent) |
| Policy (lilac) | Domain event handler or process manager / saga |
| External System (pink) | Infrastructure adapter behind an abstraction |

When applying EventStorming to a codebase, read that project's own architecture and language
conventions (its `CLAUDE.md` / `.claude/rules` or equivalent) and substitute its concrete base
types and namespaces for the generic patterns above.
