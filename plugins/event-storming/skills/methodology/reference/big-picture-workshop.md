# Big Picture EventStorming Workshop

Big Picture EventStorming is a single large-scale workshop that involves all the key people expected to cooperate to solve critical business problems. It produces a behavioral model of an entire line of business, highlighting collaborations, boundaries, responsibilities, and different perspectives.

**Outcomes:**

- A shared understanding of the business flow across silos
- Discovery and validation of the most compelling problem to solve
- Visibility of significant risks, hot spots, and opportunities
- Emerging bounded context boundaries

---

## Key Ingredients

1. **The right people** — a blend of curiosity and expertise, bound by the common goal of improving the system. Diversity in background is crucial: business experts, lean experts, service designers, software developers
2. **A suitable location** — a room large enough to provide an unlimited modeling surface
3. **At least one facilitator** — in charge of providing guidance and making sure everything runs smoothly
4. **Time** — everything happens in a few hours. Participants' time is precious

---

## Room Setup

The room must be hacked in your favor before participants arrive:

- **Long straight wall** with paper roll — 8 meters minimum, more is better
- **Enough walking space** in front of the modeling surface — people need to move freely
- **Seats not easily available** — stack chairs in a corner. Seats are terrible at the beginning; needed after a couple of hours
- **Paper roll** on the long wall
- **Flip chart** for the visible legend
- **Plenty of sticky notes and markers** for everyone — "a ridiculous amount of black markers"
- **Healthy food and beverages** — nobody should be starving
- **Timer** — some phases need time-boxing

Push the meeting table to the side. Remove chairs from the center. The typical corporate meeting room with a big table and chairs around it is **poisonous** — nothing smart comes from that setting.

---

## Workshop Phases

### Phase 1: Kick-off

- Short informal introduction round — quick, not a boring round robin
- **Explicitly set the goal**: "We are going to explore the business process as a whole by placing all the relevant events along a timeline. We'll highlight ideas, risks, and opportunities along the way."
- Warn participants: it's going to be chaotic, mostly stand-up, it's going to feel awkward — and this is all expected
- Keep explanation short — get into action ASAP. "Don't talk, show."
- Don't pitch the method. EventStorming is a tool, not the goal
- Optional: warm-up exercise modeling a well-known story (e.g., Cinderella) so participants get familiar without worrying about their domain
- **Take care of people's feelings.** It's not machinery; it's people

### Phase 2: Chaotic Exploration

The simplest notation: **orange sticky notes** = Domain Events, placed along a timeline.

**Three rules for a Domain Event:**

1. It's an **orange** sticky note
2. Phrased in **past tense** (e.g., `Item Added to Cart`, `Ticket Purchased`)
3. It's **relevant** for the domain experts

**Getting into flow:**

- The first minutes are awkward — some people won't know what to do
- An **icebreaker** (the person who places the first sticky) is your best ally. Praise them!
- If no icebreaker, the facilitator may place one example, then immediately step back: "Now it's up to you, not me"
- Once ice is broken, the workshop ignites into massively parallel contribution

**Facilitator guidance during chaos:**

- Break **committee circles** — people trying to agree on perfect wording before writing kill throughput and hide contradictions
- Don't stress about past tense compliance — engagement > compliance at this stage
- Phase names like `Registration` or `Enrolment` hide complexity — turn those stickies 45° to signal "not an event"
- Duplicates are fine — they surface different perspectives, will be merged later

**Expected outcome:** Locally ordered clusters in a disordered whole. Big and messy. Dozens or hundreds of stickies. The timeline constraint is broken in places. That's expected.

**Cool down:** When participants stop adding and take a contemplative position, walking a few steps back — praise the result, take a break.

### Phase 3: Enforce the Timeline

Goal: make the flow consistent from beginning to end.

This is when discussion gets heated — local sequences ("this is how it works in my silo") must merge with other views. Inconsistencies become visible. Key conversations happen naturally.

**Sorting Strategies** (choose based on context, combine as needed):

**Pivotal Events**

- Find 4-5 most significant events in the flow (e.g., `Order Placed`, `Order Shipped`, `Payment Received`)
- Mark with colored label tape as boundaries between phases
- Allows quicker sorting of remaining events into sections

**Swimlanes**

- Horizontal lanes assigned to actors/departments — improves readability
- Problem: uses lots of vertical space, needs synchronization
- Best applied after temporal structure is established, not as first strategy

**Temporal Milestones**

- Blue stickies on top: `1 year before`, `6 months before`, `1 month before`...
- Good for concurrent processes or when "what comes first" is unclear

**Chapters Sorting**

- Extract 15-25 key chapters of the business story (on large yellow stickies)
- Sort chapters on a separate surface (window)
- Apply chapter structure back to the main flow
- "Why didn't we start with chapters?" — Because we couldn't be sure before chaotic exploration

**Hot Spots appear here:** The facilitator captures discussions and inconsistencies on purple stickies. Hot Spots provide "a safer target for finger-pointing" — go hard on the problem (on the wall), soft on the people.

### Phase 4: People and Systems

Add two new building blocks:

- **People** (small yellow stickies) — use "people" not "actors/users/roles" for inclusive fuzziness
- **External Systems** (large pink stickies) — fuzzy definition: **"An External System is whatever we can put the blame on"**

External Systems can be: software, other departments, external organizations, regulatory bodies, "Bad Luck", "Europe", "GDPR". If it might fit, put it on the wall. If it just adds noise, you wasted one sticky note.

Developer behavior tells a lot: sometimes legacy software is "external" (disengagement), sometimes it's "us" (ownership).

### Phase 5: Explicit Walk-through

Someone walks through the event sequence while telling the story that connects them — **literally walking** in front of the modeling surface.

- Walking forward while telling the story triggers "modeler's superpowers" — your body feels weird if the flow is inconsistent
- **Speaking out loud** forces your brain to think twice — bumpy storytelling means it's working
- Change narrator at pivotal events in relay-race fashion — experts lead in their territory
- Facilitator ensures spoken story aligns with the model, adds missing events on the fly
- Some discussions should happen; some should be parked as Hot Spots. Read body language

### Phase 6: Reverse Narrative

Challenge the model by thinking in **reverse temporal order** (or strict causal order):

1. Pick an event from the end of the flow
2. Ask: "What needs to happen for this event to occur?" — the event must be a direct consequence of previous events with no magic gaps
3. If something is missing, add it
4. Repeat for every event

Reverse Narrative typically discovers **~30-40%** additional flow that was buried under optimistic forward thinking.

Good candidates: terminal events, pivotal events.

### Bonus Phase: Add the Money

Developers neglect the money flow — money is in the intersection of "obvious" and "boring." But understanding money mechanics is vital for survival, especially for startups.

If the exploration looks naive about financial flows, call a short focused round on money.

### Phase 7: Problems and Opportunities

With the whole system visible, offer a **10-15 minute time-box** for everyone to add:

- **Problems** (purple/hot pink stickies) — issues, risks, pain points
- **Opportunities** (green stickies) — ideas, value, improvements

This provides a safe way to make opinions visible without raising explicit conflict. Works especially well in corporate scenarios.

### Phase 8: Pick Your Problem

**Arrow Voting:**

1. Each participant gets two votes — small blue stickies with an arrow
2. Arrows point toward a problem or opportunity. Criterion: "most important problem to solve"
3. Voting happens simultaneously — no catwalk
4. Facilitator prevents power play (ask the alpha to wait before casting)

**When NOT to vote:**

- Wrong people mix in the room (partisan perspective, not system-wide)
- Wrong scope (real constraint might be hidden elsewhere)
- Non-disclosure constraints (pre-sales scenarios)
- Too early (startup in inception — assumptions to challenge, not impediments to fix)

### Phase 9: Wrapping Up

Take final pictures, manage closing conversations, clean up (or postpone if you can).

---

## Structure Summary (Quick Reference)

1. **Invitations** — the right people: those who know and those who care
2. **Room Setup** — enough space, food, light, fresh air
3. **Kick-off** — alignment on goals, possible warm-up
4. **Chaotic Exploration** — frantically add domain events, massively parallel
5. **Enforce the Timeline** — merge local views, structure emerges, hot spots appear
6. **People and Systems** — make roles and external systems visible, more hot spots
7. **Explicit Walk-through** — narrators tell the story, challenge the flow
8. **Reverse Narrative** — think backward, discover missing 30-40%
9. **Problems and Opportunities** — everyone states their opinion
10. **Pick the Right Problem** — arrow voting, consensus or surprise
11. **Wrapping Up** — pictures, conversations, clean-up

---

## The Problem Space (Why Big Picture Works)

Big Picture EventStorming attacks deeply entrenched organizational dysfunctions:

### Silos

- Silos minimize the learning newcomers need to start contributing — that's their evolutionary advantage
- But in the long term, **silos maximize ignorance about the whole**
- They're easy to establish, very hard to remove — this asymmetry makes them thrive
- "Specialization is both a byproduct of silos and an enabler for more future silos"
- EventStorming can't break silos, but it makes key stakeholders understand relative points of view better

### Decisions Pile Up

- Decisions stay longer than necessary
- Strong human bias toward **adding** instead of **removing** — "people are afraid of breaking invisible things"
- Admitting we're wrong is costly — cognitive dissonance, confirmation bias
- "An incredible amount of money is wasted on the unconfessable goal of allowing people not to lose face"

### The Cost of Agreeing

- Collaborative decisions require consensus, which is expensive in terms of time, energy, coordination
- **"Can't do system thinking without visualization"** (David Sibbett)
- Without a shared visible model, we can't guarantee different parties are talking about the same thing
- Sticky notes and markers allow **parallel contribution** that's still accessible to everyone — superior to serial conversation

### How EventStorming Helps

- A big behavioral model provides a perfect background for strategic decision-making
- Building the model together reveals different thinking processes
- Cross-silo workshops make strategic conversations easier
- "Large cross-silo workshops do make strategic conversations easier and help see global problems and define priorities"

---

## Discovering Bounded Contexts

"Getting the boundaries right" is the single design decision with the most significant impact over the entire life of a software project. EventStorming provides clues for bounded context discovery as a byproduct of the workshop.

**Core principle: "Merge the people, split the software."**

### Heuristics for Discovering Boundaries

**1. Look at the business phases**

- Different phases usually mean different problems, which usually leads to different models
- Pivotal Events mark transitions between phases and are usually part of a "published language" shared between contexts
- "Follow the money!" — businesses grow around well-defined business transactions
- The tools and mental models needed to *design* something are not the same tools needed to *run* it

**2. Look at the swimlanes**

- Swimlanes that highlight independent processes on different timelines suggest independent models
- Not every swimlane is a Bounded Context — sometimes it's just an `if` statement

**3. Look at the people on the paper roll**

- Different personas may require different flows — same apparent process, different mechanics
- Flows may diverge upstream (different entry points) but converge downstream (same schedule/output)

**4. Look at the humans in the room**

- Where people physically stand during the workshop is a powerful clue — experts hover around areas they know best
- Different people = different needs = different models
- This spatial information will never be documented but will often be remembered

**5. Look at the body language**

- Shaking heads, rolling eyes = conflicting perspectives not yet addressed
- DDD's answer: "we need a model to solve YOUR problem AND a model to solve YOUR BOSS' problem"

**6. Listen to the actual language**

- **Nouns fool you** — people agree on static data structure ("A Talk has a title") but the models are different
- The same noun (`Talk`) can appear in selection, scheduling, staffing, recording, publishing contexts
- **Verbs provide consistency** around one specific purpose
- Different wordings for the same event (e.g., `Schedule Ready` vs `Schedule Completed` vs `Schedule Published`) hint at multiple overlapping contexts — resist resolving duplicates!
- When two models interact, there are usually **three** models: the internals of each BC plus the communication model between them

### Divergence as a Clue

During Chaotic Exploration, duplicated or "apparently duplicated" events are valuable signals. Different wording may refer to different perspectives on the same event, hinting at relevance in more than one Bounded Context.

Resist the temptation to merge — make disagreements visible instead.

---

## Value Exploration (Optional Step)

An optional but powerful addition to the standard Big Picture. Applied after People and Systems and Explicit Walk-through, before Problems and Opportunities.

### Multiple Value Currencies

Money is the most obvious value, but far too simplistic:

- **Awareness**, **time**, **anxiety**, **stress**, **pride**, **reputation**, **safety**, **status**, **belonging**
- Once you signal that "we can talk about something else than just money," people start to talk

Use **green stickies** for value created, **red stickies** for value destroyed, placed along the flow.

### Contrasting Perspectives

- A given step may generate value for some parties while being a loss for others
- Customer-supplier dynamics: investigate whether your side inflicts unnecessary pain
- Internal conflicts: arrival of a prospect = opportunity for sales, nuisance for tech team

### Diverging Perspectives

- The same user category may have different motivations (learning vs networking vs belonging)
- Different needs = different strategies, possibly tough choices between competing needs

### Explore Purpose

- "I don't see the purpose of our job" — sometimes exploring value reveals lost organizational purpose
- Mission statements placed on the modeling surface may be embarrassingly contradicted by the actual flow
- Failing to find a reason why users should perform a given action can quietly kill a startup idea before wasting millions

---

## Big Picture Variations

### Software Project Discovery

- May need to embed workshop in pre-sales negotiation
- Sometimes best to "not even mention EventStorming" — just bring stickies and paper roll
- Trade-offs: you may not get the ideal people mix

### Organization Retrospective

- Use EventStorming to explore cross-department process improvement
- Focus on problems and opportunities in existing flows

### Induction for New Hires

Use EventStorming to quickly bring new team members up to speed:

- Don't just show the outcome of a previous session — **re-discover the whole thing**
- Give newcomers the **leading role** — model based on their guessing and assumptions
- Senior members explain and correct, evolving the model together
- Brandolini: "If you already ran a Big Picture workshop, then every participant already has a better understanding of the whole" — so being a proxy expert in a downsized workshop isn't much of a risk

This variation is valuable for agentic simulation: the "New Hire" persona implements the induction pattern naturally. Their wrong guesses force experts to articulate tacit knowledge they'd otherwise skip.

---

## Workshop Aftermath

### When to Stop

The dominant constraint is **key people availability** — expected timebox ~2 hours. Maximize value of output given time constraints: explore critical areas in depth while keeping the overall picture.

### Visual Check (Brandolini's Retrospective Checklist)

Per Ch. 9 — quick checks to verify depth of exploration:

1. **Do we have hot spots?** No conflicts and no problems doesn't mean honeymoon — it means somebody was missing, or lying
2. **How many Domain Events?** For a 2-hour workshop, 100-200 is reasonable. Less than 100 = only scratched the surface
3. **Did we capture External Systems?** They're usually sources of variability and trouble. If they're not displayed, the exploration wasn't wide enough
4. **Did we explicitly ask "what is missing?"** Without an explicit prompt, people skip vital details they think aren't relevant

### Managing the Artifact

The real outcome is **cooperative learning** — not the artifact. Don't fall in love with the model: it's still wrong. The workshop environment makes it easy to spot mistakes via the wisdom of the crowd, but some inconsistencies can only be spotted by coding and testing.

- **Keep it around for a few days** — visible reference for non-participants, visual anchoring for afterthoughts, triggers new conversations
- **Archive it** — take panorama photos for the whole flow, close-up shots for readability. Roll the paper preserving stickies. Store safely
- **Don't force detachment** — participants aren't ready to let go immediately. Give them time
- **Focus on the hot spot** — from Theory of Constraints: once you spot the bottleneck, don't lose momentum by doing something else instead

"The roll is not the deliverable, it's just a way to get to the right implementation faster." — Start coding as soon as you have a reasonably good idea about the underlying model.

### The model is not the goal

The model is:

1. An **excuse** to trigger the right conversation with the right people
2. A **tool** to improve the quality of the emerging conversation

### "This mess is us!"

A great session ends with people happily tired and a feeling of accomplishment — contemplating the walls filled with colored sticky notes with a "there is nothing left to add" feeling.

### When things go wrong

- A workshop that reveals organizational dysfunction (power plays, silent audiences) is still valuable — it shows you the real situation before you waste months building the wrong software
- "It took me less than two hours to have all the information needed in order to quit a project that was doomed"

---

## Facilitation Tips

### Postpone Precision

- Be **strict** on color scheme (hide wrong colors), **relaxed** on phrasing
- During ignition, participants shouldn't feel under examination
- Wrong phrasing will be an issue later but engagement > compliance at this stage

### No Arrows on the Paper Roll

- Arrows are drawn and can't be moved — once drawn, your brain avoids moving stickies to preserve arrows (Sunken Cost Fallacy)
- Use proximity and temporal order instead
- For distant causal links, duplicate the originator event and place a copy near the consequence

### No Laptops

- "No tables" policy means no space for laptops — this ensures full engagement
- An open laptop anchors a key person in disengaged mode
- EventStorming is more interesting than checking corporate email

### 100% Focus

- Remove tables from center — small tall tables only (for writing on stickies)
- No-tables = no laptops. "I am so sorry for that. ...No I am not."
- An open laptop anchors a key person in disengaged mode — "sitting back checked out"

### Unlimited Modeling Resources

- A depleted marker costs more than you think — 10 minutes of lost focus for 8 people = 1 hour 20 minutes of combined time wasted
- Always have excess markers and stickies. The cost is negligible compared to participant time

### Capture Definitions

- When everyone uses a mysterious term with precise domain meaning, ask for a definition
- Write it on a special sticky and place below the flow — building the Ubiquitous Language

### Timeline Is a Tool, Not the Goal

- Not every business fits a strict sequence — there are loops, branches, parallel paths
- Timeline enforces consistency between perspectives, but strict compliance isn't the goal
- EventStorming is support for "business relevant narratives"
