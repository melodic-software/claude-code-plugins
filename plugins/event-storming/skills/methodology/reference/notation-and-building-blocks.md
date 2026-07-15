# EventStorming Notation and Building Blocks

This reference covers the complete EventStorming notation — colors, sticky note types, and how they relate to each other. The notation is born from the available colors for physical sticky notes and has been adopted by digital modeling platforms.

## Core Principle: Incremental Notation

The notation is introduced incrementally during workshops, not all at once. Start with just Domain Events (orange) and add building blocks as the conversation demands them. "The fact that we're having this conversation is way more important than the precision of the used notation."

The notation is also extensible: if your domain needs a concept not covered by the standard palette (e.g., "communities" in a training business), pick an unassigned color and add it to your legend.

---

## The Building Blocks

### Domain Event (Orange sticky note)

The fundamental building block of EventStorming. A Domain Event represents **something that happened** in the business domain, written as a **verb in past tense**.

- Examples: `Order Placed`, `Payment Received`, `Ticket Sold`, `Training Description Published`
- Domain Events are placed along a **timeline** from left to right
- They are precise: they capture a specific moment in the business process
- They have no implicit scope limitation — they can span organizational boundaries
- They are triggers for consequences — other things happen because of them
- They lead toward bottlenecks — where events cluster, complexity lives
- Domain Events as state transitions: they mark the transition from one state to another

**Common mistakes:**

- Writing a phase or process name instead of a specific event (turn the sticky 45° to signal "not an event")
- Searching for the "perfect wording" too early — keep moving, refine later
- Duplicates are fine initially — they surface different perspectives and will be merged later

**Where do Domain Events come from?** (The four sources)

1. A **Command** triggered by a **User** (human decision)
2. An **External System** (something outside our boundary)
3. **Time passing** (e.g., `PaymentTermsExpired`) — no action involved
4. A **consequence** of another event, via a **Policy** ("whenever X happens, then Y")

### Command / Action / Intention (Blue sticky note)

A Command represents a **user intention, action, or decision** that triggers one or more Domain Events. Written in imperative form.

- Examples: `Place Order`, `Send Invitation`, `Reserve Seat`, `Cancel Reservation`
- Commands are the result of some user **decision**
- Some commands look like rephrasing of the corresponding Domain Event — that's fine, not every brick has to be complex
- Developers naturally look for **semantic symmetry**: if there's `ReserveSeat`, they look for `CancelReservation`
- Thinking in terms of user decisions forces thinking about what data the user needs to make that decision (→ Read Models)

### Actor / Person (Small yellow sticky note)

A human role that issues Commands.

- Represents a specific user category or role
- Can evolve from generic "user" into specific **personas** during workshop exploration
- Adding the little yellow sticky shifts focus toward **user interaction**

### Read Model (Large yellow/green sticky note)

The information a person needs to **make a decision** (issue a Command).

- Read Models emerge as tools to support the decision-making process happening in the user's brain
- Can be textual descriptions or little UI sketches when visual elements are relevant
- Examples: price display, available inventory, account status
- They support both rational and emotional decision-making

### Policy (Lilac/purple sticky note)

Reactive logic — **"whenever X happens, do Y"**. Policies connect Domain Events to Commands.

- Mostly start with the word **"whenever"**: "whenever the exposure passes the threshold, notify the risk manager"
- Captured early without making assumptions about implementation
- In a startup, a manual policy today may become automated software tomorrow
- Regardless of whether the policy is manual or automatic, the notation is the same

### External System (Large pink/red sticky note)

A system outside the current domain boundary — external organizations, services, or online applications.

- Represented with larger stickies to visually distinguish from the core flow
- Examples: payment gateways, regulatory systems, third-party APIs
- They can be sources of Domain Events (things happen in the external system that affect us)

### Hot Spot (Magenta/purple sticky note with exclamation marks)

A **problem, question, conflict, risk, or unresolved issue** flagged during the workshop.

- Decorated with big **exclamation marks** (!!!)
- Placed close to the corresponding step in the emerging workflow
- Can represent: problems, risks, areas needing further exploration, choice points where information is lacking, key requirements
- Examples: `Training Class Description Sucks!`, `Unclear Discount Policy`, `Advertising Policies!!!`
- Hot spots are prioritized to focus effort: "Which issue is going to have the biggest impact when solved?"

### Aggregate (Pale yellow sticky note)

A **consistency boundary** in Domain-Driven Design. Aggregates group related Commands and Events around a local responsibility.

- Introduced at Design-Level, not Big Picture
- Named in a **responsibility-driven fashion**
- When you start grouping commands and events around aggregates, the timeline breaks — that's fine. Timeline was for big-picture reasoning; responsibility is the driver for system design
- Aggregates look like little **state machines**
- Naming should be **postponed** — discover the behavior first, name it later

### Opportunity / Value (Green sticky note)

Represents **value, revenue, or positive outcomes** in the business flow.

- Used in value-driven exploration
- Helps identify where the business generates or captures value

### Ubiquitous Language Definition (Special sticky note)

When precision emerges from a domain expert's words, key term definitions are captured on a special sticky note placed below the normal flow.

- Not a "Wikipedia-ready" definition — just the precise meaning of that term in that specific conversation
- Captures the **Bounded Context**-specific vocabulary
- At wrap-up, resolved terms are graduation candidates for the consumer repo's committed project glossary (mechanics in `glossary-and-tools.md`)

---

## The Picture That Explains Everything

A key reference diagram drawn on a flip chart during workshops. It shows the relationship between all building blocks in a single flow:

```
[Read Model] → [Actor] → [Command] → [Aggregate] → [Domain Event] → [Policy] → [Command] ...
                                                          ↓
                                                   [External System]
```

The flow reads:

1. An **Actor** looks at a **Read Model** (information needed for a decision)
2. The Actor issues a **Command** (their decision/intention)
3. The Command is processed by an **Aggregate** (consistency boundary)
4. The Aggregate produces a **Domain Event** (something that happened)
5. A **Policy** reacts to the event ("whenever X, do Y") and triggers another Command
6. Or an **External System** reacts to / produces events

This is drawn on a flip chart and kept visible throughout the workshop as a reference legend.

---

## Color Palette Summary

| Color | Element | Shape | When Introduced |
|-------|---------|-------|-----------------|
| Orange | Domain Event | Standard sticky | Always first |
| Blue | Command | Square sticky | Process/Design-Level |
| Lilac/Purple | Policy | Standard sticky | Process/Design-Level |
| Small Yellow | Actor/Person | Small sticky | Process/Design-Level |
| Large Yellow/Green | Read Model | Large sticky | Process/Design-Level |
| Pink/Red | External System | Large rectangular | Big Picture onward |
| Magenta | Hot Spot | Standard + !!! marks | Big Picture onward |
| Green | Opportunity/Value | Standard sticky | Value exploration |
| Pale Yellow | Aggregate | Standard sticky | Design-Level only |

---

## Key Principles of the Notation

1. **Incremental introduction** — don't dump all building blocks at once. Start with events, add others as the conversation needs them
2. **Low-fidelity is intentional** — sticky notes are imprecise on purpose. They invite challenge and refinement
3. **Conversation over notation** — the stickies trigger conversations; the conversations are the real value
4. **Progressive precision** — start fuzzy, get more precise as understanding grows
5. **The right to be wrong** — wrong stickies are better than no stickies. Correction is learning
6. **Extensible** — if your domain needs a new concept, pick an unused color and add it
7. **"There is no right one"** — looking for perfect wording slows you down. Keep moving, refine later
