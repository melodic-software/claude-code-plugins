# Process Modeling EventStorming

Process Modeling is a different beast from Big Picture. Big Picture is about discovery; Process Modeling is about **collaborative modeling** to converge on a shared solution. It is a **cooperative game** where participants work together against the problem, not against each other.

## Context and Assumptions

- Designing a new **business process** (or redesigning a broken one)
- The problem is **relevant** — typically the bottleneck highlighted during Big Picture arrow voting
- **Limited scope** — focusing on a single end-to-end process
- **Smaller number of people** with different backgrounds collaborating toward a solution
- **Not designing software yet** — that's Design-Level EventStorming

## The Cooperative Game

### Game Goals — Four Win Conditions

The game ends when:

1. All process paths are **completed**, leading to a stable state where no immediate action is required
2. The **color grammar** is preserved, with no holes or gaps
3. Every possible **Hotspot** is addressed
4. All stakeholders involved are **reasonably happy**

### Completion States

- **System Happy** — no further action is necessary (all events have reached stable state)
- **User Happy** — involved users are aware of the process completion (they see the outcome somewhere)

Processes start from a trigger (Command or external Event) and finish with a combination of Events and Read Models.

### Dropping Your Guns at the Saloon Entrance

Successful collaboration requires giving up specialized jargon. Technical jargon, notations, and tools create invisible barriers. EventStorming positions itself in the middle: dropping some technicalities from software, embracing simplified UX concerns, allowing business language around event-based storytelling.

---

## The Color Grammar

"The Picture That Explains Everything" (process modeling version) is the reference. Keep it visible on a flip chart throughout the session.

```
[Read Model] → [Actor] → [Command] → [System/Aggregate] → [Domain Event] → [Policy] → [Command] ...
```

**Two strict rules (the color grammar):**

1. **"There must be a Pink System between a Blue Command and an Orange Event."** Commands don't produce events directly — they're processed by a system (or aggregate at Design-Level). Making the system explicit forces the team to identify who/what is responsible.

2. **"There must be a Lilac Policy between an Orange Event and a Blue Command."** There is always a business decision between an event and the reaction. The mandatory lilac forces the team to think — "there is no such thing as an implicit cascading reaction."

These rules are non-negotiable. Every gap in the grammar is a conversation the team hasn't had yet.

---

## Building Blocks in Detail

### Events (Orange)

In process modeling, events must be **state transitions** and phrasing is **strictly mandatory** (past tense).

Be ready to rewrite events many times — different rounds increase semantic precision and require more events.

**Four sources of events:**

1. **User Interaction** — user + system = event(s). One interaction can produce multiple events (alternative outcomes: happy path on top, alternatives below)
2. **External System** — sensors, integrations, external organizations
3. **Time** — clock icon for hours/minutes, calendar for days/months. Recurring events get a recurring symbol
4. **Cascading Reaction** — "whenever X then Y" — always mediated by a Policy (there is no such thing as an implicit cascading reaction)

**Events that are NOT happening:**

- Unfulfilled expectations are modeled via time-triggered events
- "End of day happened before Greeting Received" models a forgotten birthday
- Making the time-frame explicit leads to interesting insights

**Different wordings for the same event are not a bad thing** — resist premature agreement. Different wordings mirror different concerns and are often an indicator of multiple Bounded Contexts.

### Commands / Actions / Intentions (Blue)

Blue stickies represent actions. Can be called Commands, Actions, Decisions, or Intentions — the semantic differences are real but less important than the visible traits: **blue, present tense**.

- Commands don't imply completion — Events contain the outcome(s)
- Commands can fail or be rejected

### People (Small Yellow)

Fuzzy definitions: Users, Actors, Roles, Personas, or specific named persons. Start generic, differentiate when shortcomings become evident.

Different types of people may:

- Do the same thing for different reasons
- Need alternative or extra steps in the flow
- Need different information to complete the task

**Internal users deserve as much attention as customers** — stopping at role categorization misses reality.

### Systems (Pink)

During process modeling, systems need to be more specific than "whatever we can blame." Make every specific system explicit — different systems have different strengths and pain points. Generic systems hide complexity.

**Conversational Systems** (phone, email, chat) are harder to model event-driven:

- Don't try to script the conversation
- Focus on the **termination condition** or **final outcome**
- Use a "conversational" glyph to signal the flow stays in the system until a terminal event
- Embrace the dichotomy: fuzzy upstream, mechanical downstream

### Policies (Lilac)

A policy sits **between an orange event and a blue command**. Captures reactive logic:

> **"Whenever [event(s)] then [command(s)]"**

**"Whenever" is the keyword.**

#### Name and Implementation

Policies have dual nature:

- **Name** — don't waste time finding a good name initially; leave blank or write tentative
- **Implementation** — infer from surrounding events and commands, say it loud

Once implementation is agreed, the name becomes obvious. Asking experts "How do you call this policy?" won't help — some people do things without naming them.

#### Software or People

A policy without a person attached = automatic/system-managed.
A policy with a person on it = human-managed decision.

Policies represent different stages of maturity:

- Early startup: owner answers phone calls
- Growth: dedicated person handles incoming calls
- Scale: auto-responders handle traffic

**Policies are the first thing that needs to change when business context changes.** They are the flexible glue between other building blocks.

#### Policies as Lie Detectors

**"Policies is where people lie."** Discovering the real implementation of an existing policy is an investigation game. There are codified rules, interpretation, and reality — they rarely match.

**Speak Out Loud technique:** Read the policy aloud — "Whenever we receive an email from a customer asking to hold a room, we just do it." Your brain (and your colleagues) will immediately object, revealing the real complexity.

Iterate: add read models (information needed), add conditions, add alternative paths, read aloud again. Each round gets closer to reality.

### Read Models (Large Yellow/Green)

Information a person needs to make a decision. Represents the data/view that supports the user in issuing a command.

### Hotspots (Magenta)

Problems, questions, risks, unresolved issues. In process modeling, hotspots track:

- Unresolved policy disagreements
- Missing information
- Alternative paths not yet explored
- Technical risks

### Value (Green/Red)

Green for value created, red for value destroyed. Multiple currencies beyond money: time, reputation, stress, pride, safety, awareness.

---

## Fuzziness vs. Precision

Fuzzy Definitions are intentional:

1. **Inclusive conversation** — precise notations create barriers for non-specialists
2. **Speed** — make everything visible quickly; precision can come later

"Precision is not a bad thing: precision will be necessary; we'll be introducing it gradually."

---

## Game Strategies

### Opening Strategies (pick one or combine)

**1. Start from the beginning** — matches natural storytelling, easy for first-timers. Downside: maximizes branching. Use Rush to the Goal to stay on track.

**2. Start from the end** — collect desired outcomes, sort by priority, work backward (Reverse Narrative). Very lean — shortest path to satisfaction. Downside: mentally demanding, assumes known outcomes.

**3. Make a little mess** — small brainstorming of orange Events, spaced enough to connect with other colors. Quick skeleton, but "going to discover quickly that your skeleton is wrong." Can get out of control.

No clear winner — strategies can be combined. "Be ready to react to the signals from your team." Keep the modeling surface around 6 meters. Leave empty space before the trigger for unexpected preconditions.

### The Three-Pass Technique

The core progression for refining process models, each pass increasing precision:

**Pass 1: Rush to the Goal**

Build a baseline happy path as quickly as possible using the color grammar. Follow the grammar strictly (lilac between orange and blue) but don't discuss, don't try to reach agreement on perfect wording. Speak Out Loud while building. Once the end state is reached, flood the model with Hotspots capturing everything you don't like about it: "the problem is too hard to find the perfect solution at first attempt, so I don't even try. I just need a solution, not a good one. Then I'll improve it till it makes everybody happy."

**Pass 2: Speak Out Loud**

Read each policy aloud in full sentence form. Two things happen:

1. "I can't even finish the sentence, because I will sound stupid saying so, and my brain will start trying to correct me in real-time."
2. "Somebody will correct me because this is not the way they're working."

Capture feedback with hotspots, add Read Models (information needed for decisions), add conditions and alternative paths. Read aloud again. Each iteration gets closer to reality.

**Example (B&B room hold):**

- Round 1: "Whenever we receive an email from a customer asking to hold a room, we just do it." — Sounds stupid, triggers objections.
- Round 2: Add customer info and availability checks. "Whenever we receive a room hold request, if the customer provided their full name and phone number, and there's room availability, we just do it."
- Round 3: Apply Magic Keywords → discover only trusted regulars can hold; default is polite no. Policy splits into two.

**Pass 3: Magic Keywords ("Always" / "Immediately")**

Repeat each policy sentence prepending **"Always"** and/or **"Immediately"**: "We always, immediately do X whenever Y." Then enjoy the show — your brain or your team will immediately surface exceptions and corner cases that were hidden. This breaks approximately 50%+ of policies that seemed solid after Pass 2.

### Mid-Game Strategies

- Explore alternative paths (what if the command fails?)
- Apply the color grammar strictly — every gap is a conversation to have
- **Recognize the rabbit hole** — symptoms: people detach from the surface, topic not visible on model, sentences start with "Yes, but if..." solving multiple scenarios simultaneously. Use hotspots to defer branches; limit work-in-progress to one issue
- **Keep everything visible** — "We don't talk about invisible things." Main facilitator responsibility
- **Split & Merge** — when personalities clash, split teams to attack from different angles. If both followed the color grammar, easy to spot similar/divergent parts. "It's never fair to choose between 'the visible model we built together' and 'the invisible one this person is talking about'"
- Rewrite events for precision as understanding deepens

### Are We Done?

- All four win conditions met
- Every path reaches System Happy + User Happy
- No unaddressed hotspots
- Color grammar preserved throughout

---

## Relationship to Other Formats

| Aspect | Big Picture | Process Modeling | Design-Level |
|--------|-------------|-----------------|--------------|
| Goal | Discovery | Solution convergence | Software design |
| Scope | Entire business | Single process | Single bounded context |
| People | 15-20+ | 5-10 | 3-7 developers |
| Precision | Low (fuzzy) | Medium (increasing) | High (implementation) |
| Notation | Mostly events | Full color grammar | + Aggregates |
| Duration | 2-4 hours | 2-4 hours | 1-3 hours |
