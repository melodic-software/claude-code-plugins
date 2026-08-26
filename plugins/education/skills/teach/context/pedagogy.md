# Pedagogy: three layers and the ZPD

The teaching model every action in [`../SKILL.md`](../SKILL.md) assumes but none of them restates.
Knowledge, skills, and wisdom are the three layers; the zone of proximal development is the pacing
rule that decides how far above the learner's current level a lesson or an exercise sits.

## Contents

- [Fluency vs storage strength](#fluency-vs-storage-strength)
- [Knowledge (declarative. What is it?)](#knowledge-declarative-what-is-it)
- [Research grounding](#research-grounding)
- [Skills (procedural. How to do it?)](#skills-procedural-how-to-do-it)
- [Wisdom (judgment. When and why?)](#wisdom-judgment-when-and-why)
- [Lessons and Reference](#lessons-and-reference)
- [Zone of Proximal Development](#zone-of-proximal-development)

Every teaching session progresses through Knowledge → Skills → Wisdom. Don't skip layers; don't rush. Each layer has different teaching moves. The knowledge/skills balance varies by topic. Theory-heavy subjects (theoretical physics) lean knowledge; practice-heavy ones (yoga, a framework) lean skills. Calibrate lesson design to the topic.

## Fluency vs storage strength

Optimize for **storage strength**, long-term retention, not **fluency**, in-the-moment recall that gives "an illusory sense of mastery" (upstream teach-skill terms; the research literature, Bjork, names the pair storage strength vs *retrieval* strength). Storage strength is built by **desirable difficulty**: retrieval practice (recall from memory before re-showing), spacing (distributing practice over time), and interleaving (mixing related topics in practice. **skills practice only**, never knowledge presentation). The asymmetry that governs lesson design: **for acquiring knowledge, difficulty is the enemy**. It eats the working memory understanding needs, so explanations stay clear and scaffolded; **for skill acquisition, difficulty is the tool**. Effortful retrieval is what builds storage strength, so practice stays effortful. Quiz design inherits this: answer options carry equal length and formatting weight so presentation never leaks the answer (see [exercises.md](exercises.md)).

## Knowledge (declarative. What is it?)

- Provide clear explanations with examples and counterexamples
- Ground per "Research grounding" below. Never parametric recall at any tier. A claim that drives a lesson is verified against a source fetched or a file Read THIS turn, not recalled from training data; the ladder decides *which* fetch, never *whether*
- Use retrieval practice: ask the user to restate in their own words
- Add to `GLOSSARY.md` only when the user demonstrates understanding

## Research grounding

Grounding is graduated, pick the cheapest tier that grounds the claim:

- **Tier 0. Already-verified sources, no dispatch.** Repo files Read this turn (codebase mode) and `RESOURCES.md` citations already verified satisfy grounding for narrow or slow-domain claims. Escalate to tier 1 when a claim is contested, broad, or fast-domain (library APIs, framework syntax, tooling).
- **Tier 1. Per-lesson research (default for fresh external claims).** Invoke `/discovery:research` via the Skill tool when installed; fallback chain when absent: inline fetch of the authoritative source, `/context7:lookup` via the Skill tool (if installed) for library docs, `/firecrawl:firecrawl` via the Skill tool (if installed) when fetches are blocked. Terminating at built-in WebSearch/WebFetch. Cap: roughly one research dispatch per session unless the subject shifts, batch open questions into one dispatch.
- **Tier 2. Workspace seeding / broad subjects.** Invoke `/discovery:research-deep` via the Skill tool (if installed), or use dynamic workflows, to seed `RESOURCES.md` when a workspace opens on a broad subject.
- **Tier 3. Huge-subject corpus.** Invoke `/knowledge:map-corpus` via the Skill tool plus its digest skills (if installed) to build a corpus map; `RESOURCES.md` points at the produced slices.

Adjacent intake and sources, each invoked via the Skill tool and each only if installed: `/discovery:blindspot` when the learner doesn't know what they don't know (unknown-territory intake before the mission interview); `/dometrain:grounding` for course-grounded claims; `/x:read` when a resource lives in an X post or thread.

## Skills (procedural. How to do it?)

- Emphasize deliberate practice: small tasks focused on 1-2 skills at a time
- Couple explanation with application: explain → simple use → novel use → integrated use
- For `codebase` mode: exercises use actual repo patterns (write a handler, add a test, implement the repo's own domain primitive)
- Use error-driven learning: present buggy code, ask the user to diagnose
- Tight feedback loops, immediate feedback on each attempt

## Wisdom (judgment. When and why?)

- Ask about tradeoffs: "You chose X; what are the pros/cons vs Y?"
- Present multiple solutions, ask the user to choose and justify
- Connect to mission: "How does this apply to what you're building?"
- Prompt transfer: "Where else could this pattern apply?"
- Metacognitive reflection: "What tripped you up? What pattern did you learn?"
- For `codebase` mode: connect to the repo's ADRs, architecture decisions, design philosophy
- **Delegate to community.** Wisdom comes from real-world interaction outside the learning environment. Something an AI tutor structurally cannot provide. When a question requires wisdom, attempt to answer but also find relevant communities (subreddits, Discord servers, local meetups, courses, open-source projects) where the user can test skills in practice. Record community preferences in `RESOURCES.md`. Respect opt-outs. If the user declines community participation, don't re-suggest

## Lessons and Reference

The unit of teaching is a **lesson**. One tightly-scoped thing tied to the mission, completable quickly for a tangible win, in the user's zone of proximal development. Lessons are ephemeral in the **pedagogical** sense only. Rarely revisited and regenerable. Never in the topic-docs sense: a lesson is a member of its concept slice and stays in machine state. Alongside, distill the durable **reference**. The compressed cheat-sheet the user returns to. Authoring format, the platform-aware HTML-first default, the assets splice, reuse-first scaffolds, inline citations: [lessons.md](lessons.md).

Concept diagrams: `/visualization:visualize` when installed; otherwise native mermaid blocks (markdown fences, or `<pre class="mermaid">` where a host renders HTML) cover most structural diagrams. In-lesson charts follow the `dataviz` skill's constraints when that skill is present.

## Zone of Proximal Development

Teach just beyond current understanding, challenging but achievable. Scaffold and fade:

1. **Check current level**. Read learning records, ask what they already know
2. **Calibrate difficulty**. Not too easy (bored), not too hard (frustrated)
3. **Scaffold levels** (fade as competence grows):
   - Orientation, restate in simpler terms, break into sub-steps
   - Heuristic hints, guiding questions ("What data structure gives O(1) lookup?")
   - Pointing hints, highlight relevant concept or code section
   - Partial solution, show snippet with blanks
   - Full solution + explanation, last resort, always ask the user to explain back
4. **Track and adapt**. Update learning records when understanding demonstrated
