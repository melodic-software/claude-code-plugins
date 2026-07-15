# EventStorming Glossary and Tools

## Glossary

**"Fuzzy by design"** — Precision gets in the way. A large portion of EventStorming is about making significant conversations possible, and if you have to know what an Aggregate is in order to speak, that isn't going to work.

### Core Terms

| Term | Definition |
|------|-----------|
| **Domain Event** | An orange sticky note with a verb at past tense, referring to something that happened in the domain. In DDD, a software pattern; in EventStorming, a conversation enabler. Originally defined by Martin Fowler (2005), popularized by Greg Young with Event Sourcing and CQRS. |
| **Command** | A blue sticky note representing a user intention, action, or decision. Written in present/imperative tense. Does not imply completion — events contain the outcome. |
| **Aggregate** | A pale yellow sticky note. Unit of consistency within the domain model — a group of objects that change together but always expose consistency as a whole. From DDD by Eric Evans. |
| **Policy** | A lilac sticky note sitting between an event and a command. Reactive logic: "Whenever [event] then [command]." The flexible glue between building blocks. |
| **Read Model** | A large yellow/green sticky note. Information a person needs to make a decision (issue a command). |
| **Actor / Person** | A small yellow sticky note representing a human role. Intentionally fuzzy — can be User, Role, Persona, or specific named person. |
| **External System** | A large pink sticky note. "Whatever we can put the blame on." Software, organizations, departments, regulatory bodies, or even "Bad Luck." |
| **Hot Spot** | A magenta/purple sticky note with exclamation marks. Problems, questions, conflicts, risks, or unresolved issues. |
| **Opportunity** | A green sticky note representing value, improvement ideas, or positive outcomes. |
| **Pivotal Event** | A particularly significant event marking transition between business phases. Marked with colored tape. Usually 4-5 per flow. |
| **Bounded Context** | A DDD concept — a specific model tailored around a specific purpose. Different contexts have different models even for concepts with the same name. |
| **Event Model** | The physical outcome of an EventStorming session — the paper roll, a picture of it, or its digital translation. |
| **Ubiquitous Language** | The precise meaning of a term in a specific context. Captured on special sticky notes below the flow. |

### Specialized Terms

| Term | Definition |
|------|-----------|
| **CQRS** | Command-Query Responsibility Segregation — architectural style enforcing separation between commands (actions) and queries (data access). |
| **Event Sourcing** | Storing the history of state changes as a sequence of events, rather than just the current state. |
| **Event-Driven Architecture** | Architecture where system components communicate through events. |
| **Hypocrite Modeling** | Modeling a system with strict validation rules that can't be fulfilled in the real world — everyone finds a way to cheat. |
| **Impact Mapping** | A strategic planning technique (by Gojko Adzic) that connects goals to deliverables through actors and impacts. |
| **Model Storming** | The radical approach to modeling big stuff when you have no idea what you're doing — "the meta-process that lets you collaboratively model virtually everything without having an idea of how it will look like at the end." Extreme incremental notation. |
| **Theory of Constraints** | Focuses on finding the main system constraint (bottleneck). Improving around the bottleneck yields major improvements; improving elsewhere leads to negligible results or worse. Brandolini: "once you spot the bottleneck, every little improvement counts." From Goldratt's "The Goal." |
| **Blink Modelling** | A format where you model a domain with an expert you've never met in under 2 hours. Demonstrates "Rush to the Goal" pattern. Coined at DDD Europe 2020. |

### EventStorming Format Names

| Format | Purpose | Scope | Participants |
|--------|---------|-------|-------------|
| **Big Picture** | Discovery, shared understanding | Entire business line | 15-20+ all stakeholders |
| **Process Modeling** | Collaborative solution design | Single process | 5-10 cross-functional |
| **Design-Level** | Software design | Single bounded context | 3-7 developers |
| **Value-Driven** | Value stream mapping via events | Varies | Business + tech |
| **UX-Driven** | User/customer journey focus | User-facing flows | UX + business + tech |
| **Retrospective** | Process improvement discovery | Existing operations | Team members |
| **Induction/Learning** | Onboarding new hires | Whole organization | New + senior staff |

### Graduating Workshop Terms into the Project Glossary

Ubiquitous Language stickies are session artifacts — the terms they resolve should not be. At workshop wrap-up, offer each resolved term for graduation into the consumer repo's committed project glossary:

- One entry per term: the term, a 1–2 sentence definition of what it IS, and a plain `Avoid:` line listing the rejected synonyms the workshop ruled out
- Project-context terms only — EventStorming mechanics vocabulary (the tables above) stays out
- If the repo keeps no committed glossary yet, offer to create one lazily: a single file at the repo root, or per-context files plus a root map once multiple bounded contexts each own their own language
- When the `planning` plugin is installed, `/planning:design` owns this format — defer to it for format details; without it, the shape above is the complete contract

---

## Physical Tools

### Modeling Surfaces

**Paper Roll** — The icon of EventStorming. Provides the "unlimited modeling surface" illusion.

- **Guerrilla workshop**: IKEA Måla paper roll (kids area) — cheap, fits in a backpack, yellowish, limited width (need double-decker)
- **Prepared workshop**: Professional plotter paper roll — 60cm (fits in airline trolley) or 90cm (car transport)
- Paper roll has never been mandatory — it exists because most workplaces don't have unlimited wall space

**Writable Walls** — The ideal solution. Apply special whiteboard paint on existing walls. Every wall becomes a modeling surface.

### Markers

**One Man One Marker rule** — Provide enough working markers for everyone.

- **On stickies**: BIC Marking Pocket 1445 or Sharpie Fine Point permanent marker — regular whiteboard markers are too big, regular pens aren't visible enough
- **On flip charts** (facilitator): Round tip for beginners, chisel tip for visual scribing pros
- **On whiteboards**: Standard whiteboard markers

**Always check markers before the workshop.** Throw away depleted ones. Bring an extra supply. A depleted marker costs way more than its price in lost workshop momentum.

### Sticky Notes

**The glue is the most important thing.** Don't save money on cheap stickies that fall off the wall during your big boss's workshop.

Recommended: **3M Super Sticky** — reliable adhesion on paper rolls and walls.

**Required colors:**

- Orange (standard size) — Domain Events (the most consumed)
- Blue (square) — Commands
- Lilac/Purple (standard or rectangular) — Policies
- Small Yellow — Actors/People
- Large Yellow or Green — Read Models
- Large Pink — External Systems
- Magenta/Hot Pink — Hot Spots
- Green — Opportunities / Value
- Pale Yellow — Aggregates (Design-Level only)

### Other Supplies

- **Removable labeling/covering tape** — For labeling areas (subdomains, bounded contexts) without writing directly on the paper (which is irreversible). White sticky tape that can be rewritten or moved.
- **Colored label tape** — For marking pivotal events as boundaries between phases
- **Flip chart** — For the visible legend
- **Timer** — For time-boxed phases
- **Camera/phone** — For recording results (take pictures!)

### Static Pads

Electrostatically charged pads that stick to smooth surfaces without adhesive. Useful on glass walls.

---

## Digital Tools

The book notes that digital modeling platforms have adopted the same color palettes as physical stickies. Digital tools are useful for:

- Remote EventStorming workshops
- Preserving and sharing workshop outcomes
- Collaborative editing after the workshop

Popular digital tools for EventStorming include Miro, Mural, and specialized EventStorming tools, though the book emphasizes that physical workshops produce higher engagement and better conversations.

---

## Quick Shopping List

For a typical Big Picture workshop (20 people):

- [ ] Paper roll (8+ meters, wider is better)
- [ ] 25+ black markers (Sharpie Fine Point or BIC 1445)
- [ ] 500+ orange sticky notes (3M Super Sticky)
- [ ] 100 each: blue, lilac, small yellow, large pink, green, magenta
- [ ] 50 pale yellow (for Design-Level)
- [ ] Colored label tape
- [ ] Removable labeling tape
- [ ] Flip chart + flip chart markers
- [ ] Healthy food and beverages
- [ ] Timer/visible clock
