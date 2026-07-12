# Remote EventStorming

`[SUPPLEMENTED]` — Content sourced from Alberto Brandolini's Avanscoperta blog post "EventStorming in COVID-19 times" (March 2020), DDD community best practices, and practitioner experience reports.

---

## Brandolini's Position

**"There is still no such thing as remote EventStorming."** — Alberto Brandolini

Brandolini acknowledges remote is necessary in many contexts but maintains that significant signal is lost. The remote format demands more explicit facilitation, clearer purpose-setting, and acceptance that "we can't expect to deliver in one day."

### What's Lost

- Physical co-location's natural **peer pressure and flow state**
- **Body language, facial expressions** — the facilitator's most powerful tool
- **Handwriting as implicit signatures** — identifying who wrote what
- **Emergent structure** through collaborative discovery (physical clustering)
- Seamless facilitation of group dynamics
- **Peripheral vision** — seeing what's happening at the other end of the wall
- **Physical energy management** — standing, walking, natural breaks
- **Hallway conversations** — serendipitous insights after the session
- The "mess" — stickies falling off, running out of space, markers dying — these create micro-interactions that build rapport

### What's Gained

- Easy **version control** through digital copy/paste
- **Parallel conversation channels** (chat, video, annotations)
- **Visual alternatives display** without physical constraints
- **Asynchronous homework** contributions before sessions
- Perfect **documentation** — the board IS the documentation (no need to photograph the wall)
- **Distributed teams** can participate
- **Templates and pre-built structures**
- **Truly infinite canvas** — unlimited modeling surface is literal, not illusory

---

## Format-Specific Remote Adaptations

### Big Picture EventStorming (Remote)

*From Brandolini's Avanscoperta blog + book Ch. 11:*

1. **Clarify purpose upfront** — distinguish between company retrospectives, startup envisioning, or business redesign. Each requires different remote approaches

2. **Anticipate structure (seed the skeleton)** — chaotic exploration fails digitally: "people braindump locally ordered clusters without global ordering, creating the worst possible starting point for sorting, and this happens every single time." Seed candidate pivotal events and/or frames before the activity starts. Accept this risks "caging the exploration"

3. **Colors as signature** — participants pick their own color as personal handwriting substitute. Temporary — later stages need colors for grammar

4. **Colors as progress indicator** — keep one color (orange) unassigned; use it to mark events validated during walkthrough, providing visible measure of progress

5. **Set explicit checkpoints** — scheduled reflection moments replace implicit body language indicators

6. **Expect longer timelines** — abandon single-day delivery. "Convergence may never happen" without immersion's urgency

7. **Allow disagreements visibility** — use tool comments and designated problem markers. Rolling eyes don't translate digitally

8. **Iterate on copy** — copy the entire modeling surface before each experiment. Set strict timeboxes (5-10 min). Ask thumbs up/down. Move failed experiments aside with a note about the reason

9. **Make interests explicit** — instead of inferring interest from body language, ask people to place their name/avatar near issues they care about with arrows. Replaces physical hovering

10. **"Validation without a conversation is an illusion"** — don't rely on async validation; synchronous discussion is mandatory for real convergence

### Process Modeling (Remote)

*From Brandolini's Avanscoperta blog:*

1. **Keep grammar visible** — ensure non-experts access fundamental rules without guilt

2. **Time-boxed mob modeling (5-7 minutes)** — rotate who drives modeling while others think before their turn. Prevents continuous interruptions from derailing thought

3. **Split and compare diverging ideas** — digital tools make creating parallel flow versions easier than physical

4. **Make disagreements visible** — since body language vanishes, disagreement must be explicit and structured

5. **Rush to baseline** — find minimum viable process respecting grammar quickly, then address variations and impediments individually

6. **Use grammar-compliant stencils** — prepare pre-built chunks to eliminate tool fumbling

### Software Design / Design-Level (Remote)

*From Brandolini's Avanscoperta blog:*

1. **Explicitly separate software-only discussions** — defer naming/aggregate debates to specialist sub-sessions when non-technical stakeholders tire

2. **Maintain visible term dictionary** — prevents teams from discussing 11 concepts while modeling with only 2

3. **Take breaks, then repeat** — find one solution first for safety, then experiment with alternatives using fresh minds

4. **Recognize models as exploratory tools** — not blueprints. Supplement with BDD tests and coding when stuck in "modeling whirlpool"

---

## Practical Remote Workshop Settings

### Group Size

- **Cap at 8-12** (vs 20+ in person). Beyond 12, split into parallel sessions
- Smaller groups compensate for the lost ability to read the room

### Duration

- **90 minutes max per session**, then break
- Multiple shorter sessions over days instead of one marathon
- Remote fatigue is real — participants deplete faster due to missing supporting factors

### Facilitation

- **Much more active** than in-person. Facilitator must verbally check in, call on people, manage turn-taking
- **Silent participants are invisible online** — in person, you can see someone thinking. Remotely, silence = disengagement until proven otherwise
- Monitor invisible dynamics more actively
- Call breaks when noticing signs of mental fatigue (doodling, tab-browsing)
- Make disagreement and progress visible through structured mechanisms

### Preparation

- Send **pre-read materials** before the session
- Consider a 15-min **"how to use the tool"** session before the workshop
- **Warm-up is even more critical remotely** — Cinderella exercise or "add 3 events from your morning routine" icebreaker

### Parallel Work

- Use Miro's "follow me" feature for group phases, then release for parallel sticky-note writing
- **Breakout rooms** for smaller group explorations (replaces organic clustering in person)

---

## Tool Landscape

### Primary Tools

- **Miro** — dominant choice. Large canvas, sticky note simulation, voting, templates. Brandolini created officially supported Miro templates for both Process Modeling and Software Design formats
- **Mural** — second choice, similar capabilities
- **FigJam** — growing adoption

### Tool Limitations (per Brandolini)

- Miro lacks **sticky rotation** — diminishes the visual pressure of Hot Spots (the 45-degree "not an event" signal)
- Comments feel **"too polite"** compared to physical Hot Spots' confrontational messaging
- **Draw.io** supports stencils better than Miro's templates for grammar-compliant chunks
- Tools should provide **grammar-compliant chunks** to avoid widening the "tool divide"

### Physical Setup for Remote

- **Use standing desks** — maintains EventStorming's physical engagement
- **Block distractions** — replicate immersion by muting notifications
- **Consider tablet input** — typing limits comfort; drawing may feel more natural
- **Dual monitors** if possible — one for the board, one for video

---

## Remote vs In-Person Decision Matrix

| Factor | In-Person | Remote |
|--------|-----------|--------|
| **Best for** | Big Picture (maximum learning) | Process Modeling, Design-Level |
| **Group size** | 15-25 | 8-12 max |
| **Duration** | 2-4 hours continuous | 90 min sessions over days |
| **Facilitation effort** | Moderate (body language helps) | High (everything must be explicit) |
| **Documentation** | Photos (lossy) | Digital board (lossless) |
| **Engagement risk** | Low (standing, moving) | High (screen fatigue) |
| **Async contribution** | Impossible | Natural (add stickies later) |
| **Warm-up importance** | High | Critical |

---

## Key Insight

Brandolini emphasizes that without in-person pressure and visibility, maintaining **discipline in naming, structure, and visible disagreement becomes non-negotiable**. The remote format demands more explicit facilitation, clearer purpose-setting, and acceptance that "we can't expect to deliver in one day."

The quality standard doesn't change — the facilitation intensity does.

---

## Sources

- Alberto Brandolini, "EventStorming in COVID-19 times" — Avanscoperta Blog (March 2020)
- Alberto Brandolini, Miro EventStorming Process Modelling Template (Miroverse)
- Alberto Brandolini, Miro EventStorming Software Design Template (Miroverse)
- Selleo, "How To Run A Remote Event Storming Session?"
- VMware Tanzu, "How to Conduct a Remote Event Storming Session"
- Synyx, "Remote Event Storming Takeaways"
