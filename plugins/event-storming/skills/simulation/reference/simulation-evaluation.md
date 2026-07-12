# Simulation Evaluation and Quality Framework

This document defines the repeatable evaluation process for EventStorming simulation runs. Use it after every simulation to assess quality, compare against source material, and identify improvements for the next version.

---

## Source Material Reference

**Primary source:** Alberto Brandolini, "Introducing EventStorming" (Leanpub, ongoing)

Comparing a run against the book is a **plugin-authoring / optional** step, not a runtime
prerequisite — a consumer running a simulation does not need the book, and every step that reads it
is skipped when it isn't present. If you own a copy and want to run the source-comparison pass,
point the tooling at wherever your copy lives (any path you choose):

- EPUB / PDF: your local copy of the book (there is no assumed location — supply the path when you
  run the COMPARE step)
- Extracted EPUB working dir: `$TMPDIR/eventstorming_epub/OEBPS/` (chap00-chap44.xhtml) — `$TMPDIR`
  defaults to `/tmp` on Unix, `$TEMP` on Windows

**IMPORTANT:** EPUB file names (`chap{N}.xhtml`) do NOT match book chapter numbers. The EPUB includes unnumbered section dividers. Always use the `<title>` tag inside each file for the actual chapter number. Key mapping:

| EPUB File | Book Ch. | Content | Book % | Skill Coverage | Notes |
|-----------|----------|---------|--------|---------------|-------|
| chap00 | Preface | Scope, formats, audience | 100% | 95% | All formats listed; Blink Modelling in glossary |
| chap01 | Ch. 1 | What does ES look like? (4 stories) | 98% | 90% | Core patterns from all stories captured |
| chap03 | Ch. 2 | Problem space — silos, pretending to know | 95% | 85% | Captured in persona DEEP/GREY/PRETEND zones |
| chap04 | Ch. 3 | Software fallacies — nouns vs verbs | 90% | 70% | "Nouns fool you" captured; PO/backlog theory not (low impact) |
| chap05 | **Ch. 4** | **Running Big Picture** (core chapter) | **98%** | **98%** | Fully captured — all phases, facilitator behavior, metrics |
| chap06 | Ch. 5 | Playing with value — currencies, purpose | 95% | 95% | All 5 sub-rounds captured |
| chap07 | Ch. 6 | Discovering Bounded Contexts — 6 heuristics | 90% | 95% | All heuristics + "merge people split software" |
| chap08 | Ch. 7 | Making it happen — facilitator behavior | 80% | 85% | No arrows, legend, definitions, manage conflicts |
| chap09 | Ch. 8 | Preparing the workshop — room, invitations | 30% | 90%* | *of what exists. Room setup, focus, invitations captured |
| chap10 | Ch. 9 | Workshop Aftermath — visual checks | 20% | 95%* | *of what exists. All 4 visual checks + artifact management |
| chap11 | Ch. 10 | BP Variations — discovery, induction | 50% | 80%* | Induction mode + project discovery captured |
| chap12 | Ch. 11 | Big Picture Remote Mode | 80% | 90% | Anticipate structure, colors, iterate on copy, make interests explicit |
| chap14 | Ch. 12 | What Software Dev Really Is | 40% | 30% | Philosophical — "learning is bottleneck" captured implicitly |
| chap16 | **Ch. 13** | **PM cooperative game — win conditions** | **100%** | **98%** | 4 win conditions, System/User Happy, color grammar |
| chap17 | Ch. 14 | PM Building Blocks — Speak Out Loud | 90% | 95% | 3-pass technique, Magic Keywords, 4 event sources, policies |
| chap18 | Ch. 15 | PM game strategies — Rush to Goal | 50% | 85%* | Opening strategies, rabbit hole, split & merge captured |
| chap21 | Ch. 17 | Running Design-Level ES | 10% | **400%+** | `[SUPPLEMENTED]` with Bourgau 11-step agenda |
| chap22 | Ch. 18 | DL Modeling Tips | 20% | 90%* | Alternatives, rewrite, symmetry, hide complexity |
| chap23 | Ch. 19 | Building Blocks — why events are special | 20% | 80%* | Events as state transitions, triggers for consequences |
| chap24 | Ch. 20 | Modeling Aggregates | 30% | **95%+** | `[SUPPLEMENTED]` with Bourgau + Vernon invariant/sizing |
| chap26 | Ch. 22 | Paper Roll to Code — CRC Cards | 15% | 90%* | CRC Cards + coding ASAP + --crc simulation mode |
| chap27 | Ch. 23 | ES to User Stories | 5% | 80%* | Events→acceptance criteria, ES vs Story Mapping |
| chap29 | Ch. 25 | Corporate Environment — fog model | 5% | 60%* | Fog-me-fog captured conceptually in persona zones |
| chap32 | Ch. 28 | Remote ES — "no such thing" | 10% | 90%* | Full remote guidance in remote-eventstorming.md |
| chap34 | Ch. 29 | Patterns catalog | 75% | 90% | 29 patterns enriched from eventstorming.com + practitioners |
| chap35 | Ch. 30 | Rush to the Goal (dedicated) | 50% | 90%* | Detailed + Raise the Bar companion pattern added |
| chap36 | Ch. 29b | Anti-Patterns catalog | 75% | 90% | 14 anti-patterns enriched with Brandolini blog sources |
| chap38 | Recipe | BP recipe — ingredients, setup | 100% | 90% | Shopping list, refreshments in glossary-tools |
| chap39 | Recipe | DL recipe — ingredients, differences | 100% | 90% | Captured in design-level.md prerequisites |
| chap41 | Glossary | Terms — fuzzy by design | 80% | 85% | Theory of Constraints, Blink Modelling, Model Storming added |
| chap42 | Tools | Paper rolls, markers, stickies | 90% | 90% | Physical + digital tools in glossary-and-tools.md |

**Overall: ~92% coverage of available book content.** Remaining gaps are philosophical/narrative (Ch. 2-3, 12) or unwritten by Brandolini (Ch. 23, 25 at 5%). Design-Level and Aggregates chapters significantly supplemented beyond book content with verified Bourgau/Vernon sources.

**Secondary sources (for cross-reference):**

- Philippe Bourgau's EventStorming Journal: https://www.eventstormingjournal.com/
- Mariusz Gil (MrPicky.dev) Design-Level guides
- Web search for current practitioner insights (Perplexity MCP if present, else `WebSearch`)

---

## Pre-Simulation Checklist

Run these checks BEFORE starting any simulation:

- [ ] **MCP preflight:** Test Miro MCP with `miro_list_boards`. If it fails, inform user and get approval for curl fallback
- [ ] **Source material accessible** *(optional — authoring / source-comparison only; skip if you don't own the book)*: If running the COMPARE-against-source pass and you own the Leanpub book, extract your copy into the temp working dir, e.g. `cd "${TMPDIR:-/tmp}" && mkdir -p eventstorming_epub && cd eventstorming_epub && unzip /path/to/your/introducing_eventstorming.epub`. If you don't own the book, skip this item — the simulation runs without it.
- [ ] **Previous boards documented:** Check the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) for prior version boards (comparison baseline)
- [ ] **Domain research done:** At least 3 web-research searches (Perplexity MCP if present, else `WebSearch`) for domain context before building persona prompts
- [ ] **Persona count validated:** 4-7 for simulation, with three-zone knowledge (DEEP/GREY/PRETEND) defined for each
- [ ] **Shared focal moments defined:** 5 moments all personas will name differently

---

## Phase-by-Phase Evaluation Rubric

### Big Picture: Chaotic Exploration

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| Events-only notation | Ch. 4, Ch. 7 | Only orange stickies during this phase | Board color audit: `count(non-orange) == 0` | Critical |
| Event brevity | Ch. 1 examples | 2-5 words per event, past tense | Word count analysis on all stickies | Critical |
| Event count | Ch. 9 visual check | 100-200 after all waves | `miro_list_board_items` count | High |
| Persona differentiation | Ch. 2-3 (siloed knowledge) | Remove [PersonaName] prefix — can you tell who wrote it? | Manual vocabulary analysis | High |
| Natural duplicates | Ch. 6 (divergence = BC signal) | 3+ events where different personas name same moment differently | Scan for overlapping events across y-rows | High |
| Phase names detected | Ch. 1, Ch. 7 | 0-3 stickies flagged as "not an event" | Scan for stickies without past-tense verbs | Medium |
| Convergence broken | Ch. 4 (committee circles) | No 3+ identical phrasings across personas after Wave 2 | Pairwise event name comparison | Medium |
| Legend updated | Ch. 8 (visible legend) | Legend shows Domain Event at minimum | Visual check | Critical |

**Scoring:** Each criterion is Pass/Partial/Fail. Critical items must Pass. Weighted score: Critical=3pts, High=2pts, Medium=1pt. Max=19. Healthy=15+.

### Big Picture: Enforce Timeline

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| Sorting strategy chosen | Ch. 4-5 | Pivotal Events, Temporal Milestones, Chapters, or Swimlanes selected with rationale | Document the choice and why | High |
| Pivotal Events identified | Ch. 4 | 4-5 major phase transitions marked with dark_blue | Board check for dark_blue stickies | High |
| Divergent phrasings preserved | Ch. 6 | Near-duplicate events placed side-by-side, NOT merged | Visual check — duplicates visible | Critical |
| Hot spots facilitator-only | Ch. 4 | No personas prompted for problems yet | Check hot spot attribution | High |
| Events physically sorted | Ch. 4-5 | Events repositioned into timeline zones | Board check — events grouped by milestone | Medium |
| Legend updated | Ch. 8 | Legend adds: Hot Spot, Pivotal Event, Temporal Milestone | Visual check | Medium |

### Big Picture: People & Systems

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| People = fuzzy | Ch. 4 | Use "people" not "actors/roles" | Content check | Medium |
| External Systems = blameable | Ch. 4 | Definition: "whatever we can blame on" | Content variety check | Medium |
| New events triggered | Ch. 4 | People/Systems phase triggers additional events | Count events added in this round | High |
| Legend updated | Ch. 8 | Legend adds: Person/Actor, External System | Visual check | Medium |

### Big Picture: Walk-through + Reverse Narrative

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| Narrator relay race | Ch. 4 | Different narrators for different segments | Check agent invocations per segment | High |
| Natural language paragraphs | Ch. 4 (walking + speaking) | Connected narrative, not bullet lists | Read the narrative outputs | High |
| [STUMBLE] markers | Ch. 4 (body feels weird) | 3+ gaps identified where story doesn't flow | Count [STUMBLE] markers | High |
| New events from walk-through | Ch. 4 (30-40% additional) | 15-25 new events; target 30-40% of existing count | Count new events at y=1900 | High |
| Reverse narrative executed | Ch. 4 | 3+ terminal events traced backward | Check reverse narrative outputs | High |

### Big Picture: Value Exploration

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| Non-financial currencies | Ch. 5 | PRIDE, ANXIETY, TIME, STRESS, etc. — not just money | Check currency labels on stickies | High |
| Green = created, Pink = destroyed | Ch. 5 | Correct color usage | Board color check | Medium |
| Contrasting perspectives | Ch. 5 | Same event = value for one, loss for another | Check for contrast hot spots | High |

### Big Picture: Problems, Opportunities, Voting

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| 3 problems + 2 opportunities per persona | Ch. 4 | 18+ problems, 12+ opportunities | Count by color | Medium |
| Arrow voting | Ch. 4 | 2 votes per persona, light_blue stickies | Count votes | Medium |
| Winner identified | Ch. 4 | Clear winner marked, scopes Process Modeling | Check for winner marker | Critical |

### Big Picture: Meta-Outputs (not stickies — structural)

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| Ubiquitous Language captured | Ch. 1, Ch. 6 | 5-15 domain terms with precise definitions (gray stickies) | Board check for gray stickies | High |
| Bounded Context candidates labeled | Ch. 6, Ch. 9 | 3-5 BC boundaries identified from divergence signals (cyan labels) | Board check for cyan rectangles | High |
| Exploration map artifact | Post-workshop | Board traceability: BP→PM→DL path + unexplored BCs | Check for exploration map sticky | Medium |
| Complete legend | Ch. 8 | All building block types in legend | Count legend entries vs building block types used | Critical |

---

### Process Modeling Rubric

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| Color grammar strict | Ch. 13-14 | Policy (violet) between every Event→Command | Visual audit of flow | Critical |
| Three passes completed | Ch. 14-15 | Rush to Goal → Speak Out Loud → Magic Words | Check for corrected policies (violet at y=200) | Critical |
| "Always/Immediately" applied | Ch. 14 | Magic Words challenge breaks 50%+ of policies | Count corrected vs original policies | High |
| Alternative paths modeled | Ch. 15 | Failure events at y=250 for each command | Count failure events | High |
| Read models present | Ch. 14 | light_green stickies showing info needed for decisions | Board check | High |
| Win conditions met (4/4) | Ch. 13 | All paths complete, grammar preserved, hot spots addressed, stakeholders happy | Explicit win condition assessment | Critical |
| Legend complete | Ch. 14 | Full color grammar shown | Count legend entries | Medium |

### Design-Level Rubric

| Criterion | Source Reference | Expected | How to Check | Weight |
|-----------|----------------|----------|--------------|--------|
| Blank Aggregates technique used | Ch. 17, Ch. 20 | Empty stickies first, rules written, THEN named | Check for gray business rule stickies | Critical |
| Aggregate consolidation | Ch. 20 | Aggregates <= Commands | Count aggregates vs commands | Critical |
| Invariants documented | Ch. 20 | Each aggregate has explicit rules | Check for invariant stickies | High |
| Alternative outcomes modeled | Ch. 17 | Rejection events for each command | Count failure events | High |
| "What if?" challenges | Ch. 17 | Concurrency, edge cases, scale scenarios | Check for red hot spots | High |
| Bounded context contracts | Ch. 17 | Published events (outbound) + consumed events (inbound) | Check for cyan contract stickies | High |
| Naming postponed | Ch. 20 | Aggregates named LAST, not first | Verify blank→named sequence in transcript | Medium |
| Legend complete | Ch. 17 | Includes Aggregate, Business Rule, BC Contract | Count legend entries | Medium |

### LLM Behavioral Fidelity (cross-cutting — applies to ALL phases)

| Criterion | LLM Tension # | Expected | How to Check | Weight |
|-----------|--------------|----------|--------------|--------|
| Partial views — no comprehensive coverage | #1 Completeness | Each persona covers only their domain; visible gaps between personas | Check if any single persona wrote events spanning the entire flow | Critical |
| Divergent vocabulary | #2 Convergence | 3+ moments where personas used different words for the same business event | Pairwise scan of event names near shared focal moments | Critical |
| Genuine pushback / challenges | #3 Politeness | 3+ hot spots from inter-persona disagreement (not just facilitator) | Count hot spots with "[PersonaName] disagrees" attribution | High |
| Messy organic output | #4 Clean flows | Chaotic Exploration produces unordered clusters, not a clean timeline | Visual check — events should NOT read as a process document | High |
| Sticky note brevity | #5 Verbosity | 90%+ of events are 2-5 words, past tense | Word count analysis; flag any >7 words | Critical |
| Participant mode (no explaining) | #6 Expert/Teacher | Agents place stickies and react, not write explanations | Check agent output for paragraphs of explanation vs sticky-format events | Medium |
| Disagreements preserved | #7 Consensus | Near-duplicate events placed side-by-side, NOT synthesized | Visual check — divergent phrasings still visible | High |
| Asymmetric output | #10 Balanced | Domain Expert produced 2x+ events compared to New Hire | Count events per persona | Medium |
| Grey-zone wrong events | #9 Gap-filling | At least 2-3 events that are plausible but wrong (from grey/pretend zones) | Manual check — do any events contradict expert knowledge? | High |

**Scoring:** Critical=3pts, High=2pts, Medium=1pt. Max=23. Healthy=18+. Any Critical failure = behavioral corrections need tightening for next run.

---

## Version Comparison Framework

After each simulation run, record these metrics for progression tracking:

```
Version: v{N}
Date: YYYY-MM-DD
Domain: [domain]

Big Picture:
  Events: [count]
  Total items: [count]
  Personas: [count]
  Natural duplicates found: [count]
  Bounded contexts identified: [count]
  Ubiquitous language terms: [count]
  Walk-through new events: [count] ([percentage]% of pre-walkthrough)

Process Modeling:
  Total stickies: [count]
  Policies corrected by Speak Out Loud: [count]/[total]
  Policies broken by Magic Words: [count]/[total]
  Win conditions met: [count]/4
  Alternative paths modeled: [count]

Design-Level:
  Total stickies: [count]
  Blank aggregates placed: [count]
  Final aggregates after consolidation: [count]
  Aggregate:Command ratio: [ratio]
  BC contracts (outbound/inbound): [out]/[in]

Process:
  MCP used: [yes/no/fallback]
  Source material consulted: [yes/no]
  Visual verification screenshots taken: [count]
  Legend complete at each phase: [yes/no]
  Ubiquitous language captured during workshop: [yes/no — vs added after]
  Bounded contexts labeled during workshop: [yes/no — vs added after]

Rubric Score:
  Big Picture: [score]/[max]
  Process Modeling: [score]/[max]
  Design-Level: [score]/[max]
  Overall: [total]/[grand_max]
```

**Previous versions (for comparison):**

- v3: 77 BP events (scripted), 5 DL aggregates — baseline, no agent simulation
- v4: 103 BP events (partial) — first agent attempt
- v5: 169 BP events, 68 PM stickies, 60 DL stickies, 8 aggregates — full agent-driven
- v6: 182 BP events, 88 PM stickies, 60 DL stickies, 4 aggregates — source-validated, 7 fixes applied

---

## Post-Simulation Retrospective Protocol

After EVERY simulation run, answer these questions:

### Source Fidelity (compare against the book)

1. For each phase, read the corresponding book chapter and compare. Is the simulation producing what Brandolini describes?
2. Are there building blocks from the book that we're not using? (Check notation-and-building-blocks.md)
3. Are there workshop dynamics we're not simulating? (Body language, spatial hovering, energy management)

### Simulation Realism

1. Would Brandolini recognize this as his method?
2. Are personas genuinely differentiated? (Remove prefixes — can you tell who wrote what?)
3. Did the facilitator break committee circles when needed?
4. Is the event count in the healthy 100-200 range?

### Operational Quality

1. Were agent prompts specific enough? Too long? Missing key context?
2. Did parallel vs sequential execution work well? Should anything change?
3. Did MCP tools work? If not, was the fallback handled transparently?
4. Were legends incrementally updated at each phase?
5. Were ubiquitous language terms captured DURING the workshop (not added after)?
6. Was bounded context discovery deferred to post-workshop analysis (labels added AFTER the workshop as the architect's homework, not prematurely during it — Brandolini Ch. 6)?

### LLM Behavioral Fidelity (the 10 tensions — see agentic-simulation.md)

1. Did agents produce **partial views** (30% coverage each) or comprehensive flows? (#1)
2. Did agents use **divergent vocabulary** for the same business moments? (#2)
3. Did agents **genuinely challenge** each other, or just build on what was there? (#3)
4. Was Chaotic Exploration output **messy** or did it read like a process document? (#4)
5. Were events **2-5 words** or full sentences? (#5)
6. Did any agent **explain** instead of placing stickies? (#6)
7. Were near-duplicate events **preserved** or merged/synthesized? (#7)
8. Was output **asymmetric** (Expert: 12-15, New Hire: 4-6) or balanced? (#10)
9. Did grey-zone agents produce **plausible-but-wrong** events? (#9)

### Improvement Identification

1. What specific changes would improve the next version?
2. Should any findings be codified into the skill docs? (Update agentic-simulation.md)
3. Should any findings be saved as feedback memories? (For cross-session learning)
4. Which LLM behavioral corrections need tightening based on this run's results?

---

## Visual Verification Checklist (MANDATORY at every phase transition)

Screenshots are not optional — they are a required quality gate. Take a browser screenshot via chrome-devtools MCP after EVERY phase transition and check these items:

| Check | What to Look For | Action if Failed |
|-------|-----------------|------------------|
| Legend completeness | All building block types currently on the board have a legend entry | Add missing legend entries |
| Legend frame overflow | All legend stickies are fully visible within the frame bounds | Resize frame using the sizing formula in miro-integration.md |
| Color correctness | Each building block uses its correct color (orange=events, blue=commands, etc.) | Update miscolored stickies via `miro_update_sticky_note` |
| Stickies outside expected zones | No stickies floating far from the main content area | Reposition outliers |
| Density and readability | Stickies are not overlapping excessively; content is readable at normal zoom | Adjust spacing |
| Milestone/pivotal positioning | Temporal milestones are ABOVE events (negative y), not below | Reposition milestones |
| Emoji presence | No emoji characters visible on any sticky | Update sticky content to remove emojis |
| Type prefix presence | No "COMMAND:", "EVENT:", "🔵" prefixes on stickies | Update sticky content to remove prefixes |

**Screenshot naming convention:** `{format}-v{version}-{phase}.png`
Examples: `bp-v7-chaotic-exploration.png`, `bp-v7-enforce-timeline.png`, `pm-v7-cfp-management.png`

**Screenshot storage:** Save to `{worktree}/screenshots/` or session temp directory.

---

## How to Run an Evaluation

1. **Complete the simulation** — all 3 formats (BP, PM, DL) or the subset being evaluated
2. **Read ALL boards** — full pagination. Export item lists with colors, positions, and content
3. **Score each rubric section** — Pass/Partial/Fail for each criterion
4. **Take screenshots** — visual verification at EVERY phase transition via chrome-devtools MCP (see checklist above)
5. **Compare against prior version** — use the version comparison framework
6. **Run the retrospective protocol** — answer all 26 questions
7. **Update the run-state store** — record findings in `${CLAUDE_PLUGIN_DATA}/history.jsonl`
8. **Update skill docs** *(plugin-authoring only)* — if developing the plugin from source and an improvement is durable, add it to `agentic-simulation.md`; a consumer reports the gap upstream instead
9. **Document improvements** — specific, actionable items for the next run
