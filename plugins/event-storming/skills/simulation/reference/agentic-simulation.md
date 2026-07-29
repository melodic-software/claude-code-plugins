# Agentic EventStorming Simulation

EventStorming is inherently a multi-person activity. When working solo or with an AI assistant, we can simulate the workshop dynamics by spinning up agents with assigned personas and domain-specific perspectives. This guide covers how to identify participants, assign roles, and run a simulated session.

---

## Why Simulate?

Real EventStorming workshops require 5-20+ people in a room. Solo practitioners face a fundamental problem: **you can't have the cross-silo conversations that make EventStorming valuable if you're the only person present.**

Agentic simulation addresses this by:

- **Assigning diverse perspectives** to multiple agents, each with distinct domain knowledge, biases, and blind spots
- **Generating genuine disagreements** — agents with different roles will naturally conflict on priorities, naming, and boundaries
- **Surfacing assumptions** you didn't know you had — a simulated "operations manager" will ask different questions than a "developer"
- **Maintaining Brandolini's core insight** — "the conversations are the real value, not the artifact"

**Limitations to acknowledge:**

- No substitute for real domain experts with years of tacit knowledge
- Simulated personas can't improvise like humans — they work from the context you provide
- Body language, energy management, and spatial dynamics are lost entirely
- Best used for initial exploration, learning the method, or preparing for a real workshop

---

## LLM Behavioral Corrections — Making Agents Act Like Workshop Participants

LLMs have natural behavioral defaults that actively **oppose** what Brandolini's method requires. Every default below must be counteracted through explicit prompt instructions. This section is the single most important piece of the simulation — without it, agents produce polished corporate process documentation, not an EventStorming workshop.

### The 10 LLM-vs-Book Tensions

**Every agent prompt MUST include corrective instructions for the tensions relevant to that phase.** The facilitator is responsible for detecting when agents slip back into LLM defaults and re-prompting with stronger corrections.

#### 1. Completeness Bias → Partial, Siloed Views

**LLM default:** Produce comprehensive, thorough coverage. Fill every gap. Be helpful.
**Book requires:** Each persona sees ONLY their slice. Gaps are someone else's job. "Silos maximize ignorance about the whole" (Ch. 2) — that's the POINT, because colliding partial views creates discovery.

**Corrective prompt:** "You know 30% of this domain deeply and 70% is fog. Write ONLY events you personally encounter in your daily work. If you catch yourself writing events outside your expertise, STOP — that's someone else's job. Leave gaps. Your incomplete view is the simulation's most valuable input."

#### 2. Convergence → Genuine Divergence

**LLM default:** All agents share a base model and naturally produce similar vocabulary, similar event granularity, and similar flow structures. The output sounds like one person wearing different hats.
**Book requires:** Divergence IS the signal. Different wordings for the same moment = bounded context clue. "Nouns are the portion of enterprise knowledge most prone to ambiguity" (Ch. 3). `Schedule Ready` vs `Schedule Completed` vs `Schedule Published` — three personas, one moment, three names.

**Corrective prompt:** "Use YOUR role's vocabulary, not generic business language. A Developer says `Ticket Purchased`; a Finance person says `Revenue Recognized`; an Operations person says `Seat Allocated`. You MUST name events using the words YOUR role uses daily, even if another persona already named the same moment differently. ESPECIALLY if they named it differently — that divergence is the most valuable signal in the workshop."

#### 3. Politeness / Agreeableness → Genuine Pushback

**LLM default:** Validate others' contributions. Build on what's there. Avoid conflict. Be constructive.
**Book requires:** "Everybody in the room can (and *must*) interrupt you to challenge the ongoing storytelling" (Ch. 4). Workshop value comes from heated disagreement, sarcastic complaints, and eye-rolling. Hot spots emerge from conflict, not consensus.

**Corrective prompt:** "When you read another persona's events, your FIRST instinct should be to find what's WRONG. Not 'yes, and...' but 'no, that's not how it works from where I sit.' If you agree with everything on the board, you're not doing your job. Challenge at least 2-3 events per round. When you disagree, say WHY from your experience — 'In my 8 years in Operations, that NEVER works that way because [specific reason].'"

#### 4. Clean Logical Flows → Messy Organic Clusters

**LLM default:** Produce well-ordered, logically sequenced output. Each event flows naturally to the next. The result reads like a textbook process.
**Book requires:** Chaotic Exploration produces "locally ordered clusters in a disordered whole" — big, messy, dozens of stickies, duplicated, not in correct order. "I don't trust the official version" — starting from the clean process hides contradictions. The mess IS the point.

**Corrective prompt:** "Do NOT produce a clean left-to-right process flow. Dump events in the ORDER THEY COME TO MIND, not in chronological order. Some will be from the beginning, some from the middle, some from the end. Cluster related events together but don't worry about gaps between clusters. If your output reads like a process document, you've done it wrong. It should read like a brain dump on sticky notes."

#### 5. Verbosity → Sticky Note Brevity

**LLM default:** Write complete sentences. Explain. Elaborate. Provide context.
**Book requires:** Events are written with a thick marker on a 76x76mm sticky note: 2-5 words. Past-tense verb phrases. `Order Placed`, `Payment Failed`, `Certificate Signed`. If it doesn't fit on a physical sticky in thick marker, it's too long.

**Corrective prompt:** "Each event is 2-5 WORDS. Past tense. Verb phrase. NOT a sentence. NOT a description. Think: fat marker on a tiny sticky note. `Ticket Sold` not `A ticket was sold to the attendee after payment processing completed`. If you write more than 5 words, split it into multiple events or simplify."

#### 6. Expert/Teacher Mode → Participant Mode

**LLM default:** Explain concepts. Teach the reader. Provide comprehensive answers. "Here's how this works..."
**Book requires:** Workshop participants don't explain — they place stickies and react. An expert who knows why `Verification Step` exists doesn't explain it; they just write it. The explanation only surfaces when a naive participant questions it or gets it wrong.

**Corrective prompt:** "You are a PARTICIPANT at a wall, not a teacher at a whiteboard. Place events. React to others' events. DON'T explain or justify unless directly challenged. When you see something wrong, don't write an essay — place a hot spot with 3-5 words and a '!!!' marker."

#### 7. Consensus-Seeking → Disagreement-Preserving

**LLM default:** Find common ground. Synthesize opposing views. Resolve conflicts into a single coherent model.
**Book requires:** "Discussing to reach an agreement on every single sticky note, before writing it would kill workshop throughput and hide exactly the contradictions we want to explore" (Ch. 4). Different wordings for the same event are NOT a problem to solve — they're a signal to preserve. Merging duplicates destroys bounded context information.

**Corrective prompt:** "If you and another persona wrote different names for the same business moment, that is NOT a conflict to resolve. Both names STAY. Place them next to each other. The divergence IS the discovery. Do NOT merge, do NOT pick the 'better' name, do NOT synthesize."

#### 8. Structured Thinking → Organic Unfolding

**LLM default:** Plan the output. Think about the full scope before writing. Produce organized, categorized results.
**Book requires:** "The structure must emerge from the team's hard work" — not from upfront planning. Chaotic Exploration is organic: people write what comes to mind, influenced by what they see on the wall. The facilitator provides structure AFTER chaos, not before.

**Corrective prompt:** "Do NOT plan your events before writing them. Start writing the FIRST event that comes to mind for your role, then the next, then the next. Let each event trigger the next association. If you find yourself organizing events into categories before placing them, STOP — that's Enforce Timeline behavior and it doesn't happen yet."

#### 9. Helpful Gap-Filling → Genuine Blind Spots

**LLM default:** Notice gaps in the flow and fill them. Anticipate what's missing. Be thorough.
**Book requires:** DEEP/GREY/PRETEND zones. In your GREY zone, you have stale knowledge — write events based on outdated assumptions, not current reality. In your PRETEND zone, you bluff. "Pretending to know is the standard behavior in many organizations" (Ch. 2). Your blind spots should produce WRONG events, not missing events.

**Corrective prompt for GREY zone behavior:** "In areas outside your expertise, you have STALE knowledge — things you were told years ago that may no longer be true. Write events in these areas using your outdated understanding. DO NOT research or think carefully about whether you're right. Your wrongness will force experts to correct you, which is exactly how tacit knowledge surfaces."

**Corrective prompt for PRETEND zone behavior:** "In areas far from your expertise, you BLUFF. Write plausible-sounding events that feel right but are actually wrong. You don't know they're wrong — you genuinely believe them. This is normal organizational behavior: 'pretending to know is the standard behavior.'"

#### 10. Balanced Output → Asymmetric Contribution

**LLM default:** Each agent produces roughly equal output. Equal turns, equal detail, equal coverage.
**Book requires:** "Some might work mostly alone, dropping the bulk of their expertise in a single strip of orange sticky notes, ignoring the surrounding world" (Ch. 4). A Domain Expert dumps 15 events while a New Hire adds 5 confused guesses. Asymmetry is realistic and valuable.

**Corrective prompt:** "Your output volume should match YOUR role's knowledge. If you're the Domain Expert, dump 12-15 events. If you're the New Hire, write 4-6 hesitant guesses. If you're Finance, write 8 events that developers always forget. Do NOT try to match other personas' output volume."

### Applying Corrections Per Phase

Not all corrections apply equally to every phase. Here's the priority map:

| Phase | Critical Corrections | Why |
|-------|---------------------|-----|
| **Chaotic Exploration** | #1 (partial views), #4 (messy), #5 (brevity), #8 (organic), #10 (asymmetric) | This is silent parallel brain-dump — mess and incompleteness are the goal |
| **Enforce Timeline** | #7 (preserve divergence), #3 (pushback) | Sorting reveals conflicts; don't resolve them, surface them |
| **People & Systems** | #1 (partial views), #3 (sarcastic complaints) | Each persona knows different actors/systems; trigger boundary events |
| **Walk-through** | #3 (challenge narrator), #6 (participant mode), #9 (genuine blind spots) | Narrator tells the story; audience attacks it; stumbles = discovery |
| **Reverse Narrative** | #4 (expose hidden flow), #9 (blind spots create gaps) | Backward thinking exposes 30-40% of optimistic thinking |
| **Process Modeling** | #2 (divergent vocabulary), #3 (pushback on policies), #5 (brevity) | Color grammar strict; policies are "where people lie" |
| **Design-Level** | #1 (partial), #3 (challenge aggregates), #7 (don't merge prematurely) | "What if?" scenarios require genuine challenge, not agreement |

### How to Embed Corrections in Agent Prompts

Every agent prompt already includes persona identity, domain context, color/format rules, and round-specific behavior. Add a **Behavioral Rules** section AFTER the persona identity that includes the relevant corrections for the current phase. Example structure:

```markdown
## Behavioral Rules (DO NOT OVERRIDE)
- You know 30% of this domain. Write ONLY from your expertise. Leave gaps.
- Each event: 2-5 words, past tense, verb phrase. Not sentences.
- When you read others' events: find what's WRONG first. Challenge 2-3 events.
- Do NOT plan your output. Write events as they come to mind.
- Use YOUR role's vocabulary. Different words for the same moment = valuable signal.
- Your output volume matches your role: [Expert: 12-15 | Newbie: 4-6 | Specialist: 8-10]
```

The facilitator selects which corrections to include based on the phase (see priority map above). For Chaotic Exploration, emphasize #1, #4, #5, #8, #10. For Walk-through, emphasize #3, #6, #9.

### Detecting LLM Regression (Facilitator Responsibility)

After each round, the facilitator checks for regression into LLM defaults:

| Signal | LLM Default Leaking | Correction |
|--------|---------------------|------------|
| All events use identical vocabulary | **Convergence** (#2) | Re-prompt with divergent vocabulary emphasis; add shared focal moments with explicit instruction to name differently |
| No hot spots or challenges | **Politeness** (#3) | Spawn a skeptical persona specifically to challenge: "The [Expert] says X. From your experience, is that really how it works?" |
| Events read like process documentation | **Clean flows** (#4) | Invoke "I don't trust the official version": "This looks like the official process. What ACTUALLY happens?" |
| Every persona produced ~same number of events | **Balanced output** (#10) | Re-check persona prompts; ensure Domain Expert gets "dump 12-15" and New Hire gets "write 4-6 guesses" |
| No WRONG events in grey zones | **Helpful gap-filling** (#9) | Re-prompt grey-zone personas: "Write what you THINK happens, even if you're not sure. Your outdated assumptions are valuable." |
| Events are full sentences, 10+ words | **Verbosity** (#5) | Re-prompt: "Thick marker, tiny sticky note. 2-5 words. Split long events into multiples." |

---

## Step 1: Identify the Problem Space

Before assigning personas, define what you're exploring:

1. **What domain?** (e.g., e-commerce, conference organization, healthcare scheduling)
2. **What scope?** (Big Picture of the whole business? Single process? Software design?)
3. **What's the trigger?** (New product? Existing system redesign? Process improvement?)

Use whatever web-research tools the session has (Perplexity MCP or a scrape/search MCP if present, otherwise the built-in `WebSearch`/`WebFetch`) to gather domain context:

- Industry best practices and common business flows
- Regulatory constraints specific to the domain
- Common pain points and failure modes
- Existing competitors and their approaches

The richer the domain context, the more realistic the simulated perspectives.

---

## Step 2: Identify the WHO — Roles and Personas

Based on the problem space, identify which stakeholder perspectives are needed. Start with Brandolini's guidance: **"invite the right people — a blend of curiosity and expertise."**

### HARD RULE: Beneficiary Persona is Non-Negotiable

**The FIRST persona designed must be the end-user/beneficiary — the person the system exists to serve.** This persona cannot be proxied by an operational role (e.g., a support coordinator "speaking for" the individual). The beneficiary's vocabulary, frustrations, and blind spots are fundamentally different from any staff member's.

Examples: For IDD: Individual receiving services + Family/Guardian. For healthcare: Patient. For commerce: Customer. For education: Student.

Prior runs that omitted the beneficiary persona caught the gap only via facilitator step-back mid-run. The gap-fill was inconsistent with how other personas were executed. This is now a hard rule to prevent recurrence.

### Agent Execution Rule: One Persona Per Agent Invocation

**NEVER combine two personas in a single Agent invocation.** Each persona = one Agent call. When two personas share one agent, vocabulary converges and the output sounds like one voice wearing two hats. This defeats the core value of multi-persona simulation.

Combining personas (e.g., "SupportCoord reactor + ProgDir reactor" in one agent) consistently produces degraded output. Prompt quality audits show later-round combined prompts ~40% shorter than early-round individual prompts, scoring 6.2/10 vs 9/10 for individual prompts.

### Standard Persona Catalog

Pick 4-8 from these based on your domain (beneficiary persona is MANDATORY — always first):

| Persona | Perspective | Typical Concerns | Agent Tone |
|---------|-------------|-----------------|------------|
| **Domain Expert / Business Owner** | Knows the business deeply, has opinions about "how things work" | Revenue, customer value, competitive edge | Authoritative but may skip "obvious" details |
| **End User / Customer** | Experiences the system from outside | Usability, speed, trust, pain points | Practical, impatient with technical jargon |
| **Developer / Architect** | Thinks in systems, boundaries, data flow | Implementation feasibility, technical debt, scalability | Asks "what if?" and looks for semantic symmetry |
| **Operations / Support** | Maintains the system day-to-day | Reliability, monitoring, edge cases that "always happen" | Skeptical of happy-path thinking |
| **UX Designer** | Thinks in user journeys and emotional states | User experience, information hierarchy, cognitive load | Advocates for the user over the system |
| **Compliance / Legal** | Knows regulatory constraints | GDPR, PCI-DSS, audit trails, data retention | Conservative, asks about liability |
| **Finance / Accounting** | Tracks money flows | Revenue recognition, invoicing, payment terms, taxes | Focused on financial events others overlook |
| **Sales / Marketing** | Acquires and retains customers | Conversion, retention, competitive positioning | Optimistic, growth-oriented |
| **New Hire / Outsider** | Knows nothing, asks "stupid" questions | Understanding, learning, challenging assumptions | Curious, not afraid to say "I don't understand" |

### Domain-Specific Persona Discovery

For specialized domains, research additional personas:

```
Use WebSearch/Perplexity: "[domain] stakeholders roles organizational structure"
Use WebSearch/Perplexity: "[domain] common pain points between departments"
```

Examples:

- **Healthcare**: add Clinician, Patient, Insurance Reviewer, Lab Technician
- **Fintech**: add Risk Manager, Compliance Officer, Trading Desk, Settlement
- **Conference Org**: add Speaker, Sponsor, Venue Manager, Video Production
- **Music Platform**: add Artist/Songwriter, Producer, Venue Booker, Fan/Listener

---

## Step 3: Build Agent Prompts

Each simulated participant gets a system prompt that establishes their persona, knowledge, biases, and communication style.

### Prompt Template

```markdown
You are [ROLE NAME], participating in an EventStorming workshop to explore [DOMAIN/PROBLEM].

## Your Background
- [2-3 sentences about your professional background and experience]
- [What you know deeply about this domain]
- [What you DON'T know — your blind spots]

## Your Priorities (in order)
1. [Most important concern]
2. [Second concern]
3. [Third concern]

## Your Communication Style
- [How you express disagreement]
- [What triggers you to speak up]
- [What you tend to overlook or dismiss]

## Your Role in the Workshop
- Write Domain Events (orange) from YOUR perspective using past tense
- Flag Hot Spots (purple) for things that worry you
- Challenge other participants' events when they conflict with your experience
- Ask questions when something seems too simple or too complex

## Domain Context
[Paste domain-specific research here — industry terms, regulations, common flows]

## Rules
- Stay in character throughout the session
- Express genuine disagreement when your perspective conflicts with others
- Don't just agree — push back when something doesn't match your experience
- Use domain-specific vocabulary natural to your role
- Flag when you don't understand something (that's valuable signal)
```

### Persona Persistence Across Rounds

LLM agents are stateless — each Agent tool invocation starts fresh. Without persistence, a persona in Round 3 has no memory of what they wrote in Round 1, leading to inconsistent identity, vocabulary drift, and lost incremental knowledge.

**Solution: Temp profile files loaded into each agent prompt.**

**Directory structure** (created at session start, cleaned up at session end).
`{session_dir}` is **created** by a secure temp primitive rather than merely named, then captured once and used consistently throughout — `mktemp -d "${TMPDIR:-/tmp}/eventstorming-session-XXXXXX"` on POSIX/Git Bash, `New-Item -ItemType Directory -Path (Join-Path $env:TEMP ('eventstorming-session-' + [IO.Path]::GetRandomFileName()))` on Windows PowerShell (`$env:TEMP` is per-user, by default under `%LOCALAPPDATA%\Temp`). Never a hardcoded literal path, and never a name composed only from `{session_id}`: on a multi-user POSIX host `${TMPDIR:-/tmp}` falls back to the shared world-readable `/tmp`, where a predictable name both leaks the persona and session Markdown to every local user and lets one of them pre-create the path. The primitive closes both — the random component defeats pre-creation, and POSIX `mkdtemp` mandates mode 0700, which gates traversal into the directory regardless of the modes of the files inside it.

```
{session_dir}/
  personas/
    organizer.md         # Profile + accumulated state
    developer.md
    speaker.md
    sponsor.md
    operations.md
    newhire.md
  session-meta.md        # Domain, board IDs, current phase, persona list
```

**Profile template** (`personas/{role}.md`):

```markdown
# Persona: {Role Name}

## Identity
- **Role:** {role title}
- **Experience:** {2-3 sentences of professional background}
- **Personality traits:** {e.g., skeptical, curious, dismissive, cautious, enthusiastic}
- **Speech patterns:** {characteristic phrases, jargon preferences}
- **Emotional triggers:** {what makes them speak up, what they dismiss}

## Knowledge Zones
- **DEEP:** {areas of expertise — daily work}
- **GREY:** {stale/second-class knowledge — outdated assumptions}
- **PRETEND:** {areas where they bluff with plausible-sounding but wrong assertions}

## Vocabulary Registry
{Terms this persona uses — built up across rounds}
- "Ticket" → this persona says: "ticket purchased" (not "registration completed")
- "Schedule" → this persona says: "schedule grid" (not "agenda")

## Events Placed (accumulated across rounds)
### Round 1 (Chaotic Exploration)
- [Organizer] Venue Booked
- [Organizer] Budget Approved
- ...

### Round 3 (People & Systems)
- People added: Program Committee Chair, Venue Sales Rep, ...
- Systems added: Ticketing Platform, Email Marketing, ...
- New events: Program Committee Scored Talks, ...

### Round 4 (Walk-through)
- Narrated segment: Planning → CFP Published
- [STUMBLE] markers placed: ...
- Challenges made: ...

## Relationships with Other Personas
- Disagrees with {Speaker} about: {topic}
- Ignores {Operations} concerns about: {topic}
- Respects {Sponsor}'s input on: {topic}
```

**Loading profiles into agent prompts:**
When spawning an agent for Round N, include the persona's profile file content at the TOP of the prompt. The profile provides identity continuity and vocabulary consistency. After the agent completes, UPDATE the profile with what they produced in that round.

**Session ID generation:**
Use `{domain}-{date}-{random4}` format, e.g., `devconf-20260321-a7f2`, where `{random4}` is four random lowercase hex characters (`0-9a-f`) — no spaces, slashes, or other path-unsafe characters, since the ID is used in filesystem paths (including the `rm -rf` cleanup). This namespaces the temp directory for concurrent session safety.

**Cleanup protocol:**
At session end, ask user: "Delete persona temp files? (They can be archived for session replay.)"

- If yes: delete the session directory recursively with the host shell's remover — `rm -rf "{session_dir}/"` on POSIX/Git Bash, `Remove-Item -LiteralPath "{session_dir}" -Recurse -Force` on PowerShell; keep the path quoted, it may contain spaces (`{session_dir}` is the path the temp primitive returned at session start, not a path you recompute here)
- If no: archive to `${CLAUDE_PLUGIN_DATA}/sessions/{session_id}/` (the per-plugin data directory that survives updates). Session archives are per-run state, not skill source; never write them into the plugin's own installed directory (`${CLAUDE_PLUGIN_ROOT}`, read-only under cache isolation) or into the consumer's project tree

---

### Differentiating Agent Output — Simulating Siloed Knowledge (Brandolini Ch. 2, 3, 6)

Brandolini's core insight: "Silos minimize the learning newcomers need to start contributing. But the grey, unexplored areas will stay. Possibly for a very long time." (Ch. 2). The VALUE of EventStorming comes from colliding these designed ignorances — each persona has deep knowledge in their area and genuine ignorance outside it.

**Agent prompts must define THREE things per persona:**

1. **Deep expertise zone** — what this persona knows cold, from daily work. They write events here quickly, confidently, using precise internal vocabulary. They CORRECT wrong events in this zone
2. **Grey areas / blind spots** — what this persona was told "you don't need to know." They have stale, second-class knowledge here — outdated assumptions from years ago, not zero knowledge. Brandolini: "the former experts will slowly drift into second-class knowledge" (Ch. 2)
3. **Pretend-to-know zone** — areas where this persona bluffs with plausible-sounding but wrong assertions rather than admitting ignorance. Brandolini: "'Pretending to know' is the standard behavior in many organizations" (Ch. 2)

**Per persona type:**

- **Domain Expert / Business Owner**: DEEP in business process and customer interactions. GREY on technical implementation ("the system handles it"). PRETENDS about scalability and failure modes. Uses precise business jargon. Skips "obvious" steps. Dismisses edge cases: "that never happens." Has SACRED DECISIONS they'll defend emotionally (Ch. 2: cognitive dissonance around past choices)
- **Developer / Architect**: DEEP in technical systems, data flow, error handling. GREY on business rules and financial flows. PRETENDS about customer experience. Looks for semantic symmetry (`PlaceOrder` → `CancelOrder`). Brandolini: "developers invariably neglect the money part" (Ch. 4). Distances self from legacy: says "the system" not "our code" for components they've disengaged from (Ch. 4)
- **Operations / Support**: DEEP in failure modes, incidents, manual workarounds. GREY on the "why" behind business rules. PRETENDS about planned features ("I think they're fixing that"). Writes the events nobody else remembers: `Timeout Hit`, `Manual Override`, `Escalation Triggered`. Uses war-story vocabulary
- **End User / Customer**: DEEP in their own experience, pain points, emotional journey. GREY on everything behind the curtain. PRETENDS the system works simply ("I just click the button"). Writes events from OUTSIDE the system boundary using plain language
- **New Hire / Outsider**: DEEP in fresh pattern-recognition. GREY on everything specific. GUESSES rather than pretends — Brandolini: "guessing is a legitimate action" (Ch. 4). Wrong guesses force experts to articulate tacit knowledge they'd otherwise skip. Value is in being wrong in INTERESTING ways
- **Finance / Accounting**: DEEP in money flow, revenue recognition, payment terms. GREY on product features and user experience. PRETENDS about technical capabilities. Writes events developers systematically miss: `Invoice Generated`, `Revenue Recognized`, `Refund Window Expired`

**Critical principle — same noun, different meaning (Ch. 3, 6):**
Different personas use the SAME nouns to mean different things. "Order" to Sales means opportunity/pipeline. "Order" to Shipping means packages/routes. "Order" to Billing means invoice/payment. Agents must use domain-specific vocabulary naturally — the divergence in how they name the same business moment IS the bounded context signal. Brandolini: "Nouns are the portion of enterprise knowledge most prone to ambiguity... Looking at verbs provides much more consistency" (Ch. 3)

**Tacit knowledge surfaces through CORRECTION, not interrogation (Ch. 10):**
Don't have expert agents dump their knowledge unprompted. Have naive agents model first, let experts REACT to errors. An expert who would never mention "we always verify X before Y" will immediately correct a naive agent who places Y before X — that correction IS the articulation of tacit knowledge.

**Key test:** if you remove the `[PersonaName]` prefix and can't tell who wrote it, the personas aren't differentiated enough. Check: do they use different vocabulary for the same moment? Do experts skip "obvious" steps that others include? Does the New Hire guess wrong in ways that provoke correction?

### The "New Hire" Agent — Special Role

The New Hire persona is particularly valuable in simulation because it implements Brandolini's **"Guess First"** and **"Sound Stupid"** patterns naturally:

```markdown
You are a NEW HIRE who joined [COMPANY] two weeks ago. You have general
industry knowledge but zero knowledge of how THIS company does things.

Your job: ask the questions nobody else dares to ask.
- "Why do we do it this way?"
- "What happens if this step fails?"
- "I don't understand what [TERM] means in our context"
- "This seems really complicated — is there a simpler way?"

You are NOT stupid — you're fresh eyes. Your confusion is signal, not noise.
```

---

## Step 4: Run the Simulated Session

### Format Options

**Option A: Sequential Persona Rotation (Simplest)**

1. Start with one persona (Domain Expert) — lay down initial events
2. Switch to another persona (Developer) — challenge and add technical events
3. Switch again (Operations) — add failure modes and edge cases
4. Continue rotating until the flow stabilizes

**Option B: Multi-Agent Parallel (Most Realistic)**
Using Claude Code's Agent tool, spawn multiple agents simultaneously:

1. Each agent generates Domain Events from their perspective
2. Merge the events onto a shared timeline
3. Identify conflicts and duplicates (different wordings = possible bounded context clues)
4. Have agents debate the conflicts

**Option C: Facilitated Session (Recommended)**
You act as the facilitator, the skill provides methodology guidance, and you invoke individual persona agents as needed:

1. Start the Big Picture — ask the Domain Expert agent for initial events
2. When you hit a gap, invoke the relevant persona: "What would Operations say about this step?"
3. Use the Icebreaker pattern — place one event, then ask each persona to react
4. Follow the Big Picture phases (Chaotic Exploration → Enforce Timeline → People & Systems → Walk-through → Problems & Opportunities)

### Phase-by-Phase Simulation Guide

**Chaotic Exploration (simulated)**

- Ask each persona agent: "Write 10-15 Domain Events you'd place on the wall for [scope]"
- Collect all events, noting which persona generated each
- Duplicates and near-duplicates are VALUABLE — they signal bounded context boundaries

**Enforce the Timeline**

- Sort the collected events chronologically
- Ask each persona: "Does this sequence make sense from your perspective?"
- Hot spots emerge where personas disagree on ordering or causality

**People and Systems**

- Ask each persona: "Who are the key actors in YOUR part of the process?"
- Ask: "What external systems do you depend on or blame?"
- Fuzzy definitions intentional — let different personas name the same system differently

**Problems and Opportunities**

- Ask each persona: "What are the top 3 problems you see in this flow?"
- Ask: "What opportunities would you prioritize?"
- Arrow voting: each persona gets 2 votes

---

## Step 5: Capture Outputs

The simulation produces:

1. **Event timeline** — collected Domain Events with persona attribution
2. **Hot spots** — disagreements, questions, risks flagged by different personas
3. **Bounded context candidates** — areas where language diverges between personas
4. **Priority ranking** — arrow voting results across personas
5. **Ubiquitous language seeds** — terms with persona-specific definitions; terms the session resolves are offered at wrap-up for graduation into the consumer repo's committed project glossary rather than staying session-scoped

### Output Format

```markdown
## EventStorming Simulation Output

### Domain Events (chronological)
| # | Event | Source Persona | Conflicts |
|---|-------|---------------|-----------|
| 1 | User Account Created | Domain Expert | Ops: "what about email verification?" |
| 2 | ... | ... | ... |

### Hot Spots
| Hot Spot | Raised By | Related Events |
|----------|-----------|----------------|
| "No clear ownership of payment failures" | Operations | Payment Initiated, Payment Failed |

### Bounded Context Candidates
| Area | Diverging Terms | Personas Involved |
|------|----------------|-------------------|
| Order vs Reservation | Dev: "Order", Sales: "Booking" | Developer, Sales |

### Arrow Votes (Priority)
| Problem/Opportunity | Votes | Voters |
|-------------------|-------|--------|
| Payment failure handling | 4 | Ops, Dev, Finance, Domain Expert |
```

---

## Integration with Miro

When the Miro MCP server is configured (`mcp-servers/miro/node/`), simulated agents can place stickies directly on a Miro board. See `@./reference/miro-integration.md` for color mapping, spacing values, and board setup.

### Round-Based Orchestration — Following Brandolini's Incremental Phases

Agents can't subscribe to live board changes — MCP is request/response, not streaming. The realistic pattern is **round-based orchestration**, which maps to Brandolini's Big Picture phases exactly. **Critical: follow the incremental notation — don't dump all building blocks at once.**

**Agent Execution Pattern (MANDATORY — the facilitator NEVER generates events)**

Each persona is a SEPARATE Agent tool invocation. The facilitator orchestrates rounds but agents generate ALL content (events, reactions, disagreements). This is non-negotiable — centralized event generation by the facilitator produces events that all sound like the same voice with different labels, defeating the entire purpose of simulation.

**Per-agent prompt must include:**

1. **Persona profile** — if persona persistence is enabled, load the full profile file content from `{session_dir}/personas/{role}.md`. Otherwise, include inline: role, background (2-3 sentences), priorities (ordered), blind spots, communication style, what triggers them to speak up
2. **Board ID and MCP instructions** — agents read the board themselves via `miro_list_board_items`, place events via `miro_create_sticky_note` or `miro_bulk_create_sticky_notes`
3. **Domain context** — research relevant to their role (not the full dump — what THIS persona would know from their professional experience)
4. **Color and format rules** — which colors are allowed this round (e.g., orange only during Chaotic Exploration), event format: `[PersonaName] Event in Past Tense`
5. **Y-offset** — each persona occupies a distinct y-coordinate row during chaotic exploration
6. **Sticky note content rules (MANDATORY in every agent prompt):**
   - **Brevity:** 2-5 words per event. Past-tense verb phrases (`Order Placed`, `Payment Failed`). If it doesn't fit on a physical 76x76mm sticky note in thick marker, it's too long. **Key test:** count your words — if >5, split into multiple events or simplify
   - **No emojis:** Physical sticky notes are handwritten text only. Do NOT prefix stickies with emoji characters (🧑, 📖, 🔵, ⚡, 📊, 🏆, etc.). Plain text only. This applies to ALL board types (BP, PM, DL) and ALL agent prompts — include this instruction in every subagent prompt that creates stickies
   - **No literal newlines:** Do NOT use `\n` in sticky note content — Miro renders these as literal backslash-n, not line breaks. Use ` — ` (em dash with spaces) as separator instead
   - **No type prefixes:** Do NOT add prefixes like "COMMAND:", "EVENT:", "POLICY:" to sticky content. The COLOR is the type indicator, not a text prefix. Write the content only: `Submit Talk Proposal` not `🔵 COMMAND Submit Talk Proposal`
7. **Round-specific behavior:**
   - **Hermit agents**: "Do NOT read the board. Dump 8-12 events purely from YOUR expertise."
   - **Reactor agents**: "Read the board first via `miro_list_board_items`. Place events that REACT to what you see — reference other personas' events by name, add your perspective, flag where you disagree."
   - **"What is missing?" agents**: "Read the full board. Identify gaps — failure modes, edge cases, time-triggered events, financial flows, system interactions nobody mentioned. Place 3-5 events filling those gaps."

**Round orchestration (facilitator workflow):**

1. Spawn agent(s) for the current micro-round — use parallel Agent tool calls where simultaneous work is appropriate
2. Wait for all agents to complete
3. **Post-placement quality gate (facilitator validates EVERY round):**
   a. Read the board via `miro_list_board_items` (full pagination)
   b. **Brevity check:** scan all new stickies — flag any with >5 words for decomposition or simplification
   c. **Emoji check:** scan for emoji Unicode characters in sticky content — if found, update the sticky via `miro_update_sticky_note` to remove emojis
   d. **Type prefix check:** scan for stickies with prefixes like "COMMAND:", "EVENT:", "🔵" — update to remove prefix, the color IS the type
   e. **Phase name check:** scan for nouns/gerund phrases without past-tense verbs — flag as `[PHASE? Decompose this]`
   f. **Visual checkpoint:** on the live-board path with a browser MCP connected, take a screenshot at every phase transition (a strong quality gate for board runs); in structured-markdown mode or with no browser MCP, skip it and verify against the markdown artifact instead
   g. **Legend overflow check:** verify legend stickies are within frame bounds visually
4. Next round's agents read the board themselves via MCP — they don't need a facilitator summary
5. Repeat until cool down + 100-event gate
6. If persona persistence is enabled, update the persona profile files with what each agent produced in this round

**Board Setup (Facilitator)**

1. Create board with `miro_create_board`
2. Create Legend frame — but only show Domain Events initially (add to legend incrementally as phases progress)
3. **Do NOT create a timeline frame.** A frame sized to the flow must grow every round, and frames created or resized after their content render on top and hide it (frame z-order gotcha in `miro-integration.md`). Rely on coordinate-based organization; the static Legend frame is the only frame.
4. Set x=0 as the timeline start, flowing right

**Round 1: Chaotic Exploration (EVENTS ONLY — orange stickies)**

The ONLY notation at this point is orange Domain Events in past tense. No other colors — no actors, systems, commands, or hot spots.

**Simulating "quiet chaos" (Brandolini's actual description):**

Brandolini says the chaotic exploration phase is "usually silent: people will quietly place their brain-dump on the wall" (Ch. 4, 6). This is NOT a conversation — it's massively parallel independent work. Conversations and reactions come LATER during Enforce Timeline.

**Critical simulation principle: "I don't trust the official version."** Brandolini uses messy chaotic exploration specifically because starting from the "official" process hides real contradictions. If the simulation produces a clean, consistent flow on the first pass, the agent prompts aren't diverse enough. The mess IS the point.

**Simulation flow (mirroring the organic workshop dynamic):**

Brandolini describes ONE organic phase, not structured "waves." The dynamics (Ch. 4): awkward start → icebreaker → ignition → quiet chaos → cool-down. People self-organize into three simultaneous behaviors: **committees** (trying to agree on wording — facilitator breaks these), **hermits** (working alone, dumping expertise), and **lost/guessing** (no idea what to write — reassured that guessing is legitimate). "I am not expecting many conversations at this stage. After breaking the committee circles, people will eventually start working on their own: I call this phase quiet chaos." The result is "locally ordered clusters in a disordered whole."

The simulation approximates this with parallel agent rounds, but must NOT impose artificial structure (no "Wave 1/Wave 2/Wave 3" labels, no behavioral mode switches between rounds).

1. **Everyone at the wall — spawn ALL agents in parallel:**
   Spawn ALL persona agents simultaneously. Each agent independently dumps 10-15 Domain Events from their expertise. Each agent places events in their own y-row. Whichever agent COMPLETES first is the organic icebreaker — this is emergent, not prescribed ("An icebreaker, the person that places the first sticky note... is your best ally" — Ch. 4). The facilitator does NOT go first ("I tend to resist it, since it may put other's participants in passive mode" — Ch. 4).

   Each agent CHOOSES whether to read the board (`miro_list_board_items`) or not — some will be hermits ("work mostly alone, dropping the bulk of their expertise"), some will glance at what's there. Do NOT prescribe "hermit mode" or "peripheral awareness mode" — let the agent prompt say: "You're at the wall with everyone else. Place your events. You may glance at what's already on the board — or ignore it entirely and just dump your expertise."

   **Anti-Spoiler protection (critical for LLM agents):** LLM agents naturally want to be comprehensive and correct — they'll dump complete, consistent process flows instead of partial, perspective-limited views. This is the Spoiler anti-pattern (Ch. 29). Every agent prompt MUST include: "You are NOT trying to be comprehensive. Place 10-15 events from YOUR perspective only. Leave gaps — your incomplete view is the POINT. Events you don't know about are someone else's job. If you're writing events that feel outside your expertise, stop."

   Do NOT use a single orchestrator agent to generate events for all personas — that defeats persona differentiation. One Agent tool call per persona in a single message.

   **Seeding overlap (the "same moment, different eyes" principle):**
   In real workshops, overlap happens because everyone writes about the same visible business moments from their own perspective — Brandolini's `Schedule Ready` vs `Schedule Completed` vs `Schedule Published` example (Ch. 6). In simulation, agents writing about completely different domain areas produces complementary coverage but zero overlap. To force natural overlap, include 3-5 **shared focal moments** in every agent's prompt: "Your domain includes these key moments that everyone encounters: [list pivotal transitions, e.g., 'a customer first engages', 'money changes hands', 'the product/service is delivered', 'something goes wrong']. Write events for these moments FROM YOUR PERSPECTIVE using YOUR vocabulary, AND write events for the parts of the domain only you know about." Each persona will name the same moment differently — that divergence is the signal we want.

2. **Continued exploration (if areas are thin):**
   If total events are well below 100 after the initial dump, or if the facilitator sees under-explored areas, spawn agents again. Each agent reads the board and adds MORE events from their own expertise — but is NOT yet "reacting to" or "referencing" others' events. That's Enforce Timeline behavior. The conversation is still mostly silent.

   This is NOT a separate "wave" — it's continued exploration, the same way workshop participants keep adding stickies after the initial rush. "Some might work mostly alone, dropping the bulk of their expertise in a single strip of orange sticky notes, ignoring the surrounding world" (Ch. 4).

3. **Cool-down — recognize the natural stopping point:**
   "Eventually, the crowd will stop adding stickies to the wall and will take a more contemplative position, looking at the big picture more than to their own stickies, and walking a few steps back" (Ch. 4). In simulation, cool-down = when the last round of agents adds only 1-3 events each, or when agents start producing events that feel like stretches rather than natural expertise. The facilitator praises the result and takes a break.

4. **Event count diagnostic (NOT a hard gate):**
   Check event count. Per Brandolini's post-workshop visual check (Ch. 9), 100-200 is a healthy range for a 2-hour workshop. Below 100 suggests surface-level exploration — spawn agents again targeting under-explored areas. This is a diagnostic signal, not a blocking gate — Brandolini uses it as a retrospective assessment, not a pre-condition.

**Asymmetric information flow:**
Some agents will naturally produce more events than others — a Domain Expert might dump 15 events while a New Hire adds 5 curious questions disguised as events. This asymmetry is realistic. Brandolini observes: "Some might work mostly alone, dropping the bulk of their expertise in a single strip of orange sticky notes, ignoring the surrounding world." Don't force equal output across agents.

**Phase name detection (facilitator validation):**
After each micro-round, the facilitator scans for stickies that look like phase/process names rather than events — no past-tense verb, reads like a category ("Registration", "Payment Processing", "Onboarding"). In a real workshop, the facilitator turns these 45° to signal "not an event." In the simulation, flag them with `[PHASE? Decompose this]` and prompt the generating agent to break them into specific events. Heuristic: if the sticky has no past-tense verb, or reads as a noun/gerund phrase, it's likely a phase name hiding 5-10 events.

**Event count diagnostic (post-exploration check):**
After Chaotic Exploration, check the event count against Brandolini's retrospective visual check (Ch. 9): 100-200 is a healthy range for a Big Picture workshop. Below 100 suggests the exploration only scratched the surface — run additional waves targeting specific under-explored areas (failure modes, edge cases, time-triggered events, financial flows, system interactions). This is a quality signal, not a blocking gate.

**Event count decision tree (facilitator action at each checkpoint):**

- After initial dump: `count < 10 per persona?` → persona prompts are too narrow; widen domain context and re-run
- After initial dump: `3+ personas used identical phrasing for same moment?` → convergence detected; break committee circles in next round prompts
- After cool-down: `count < 100?` → run targeted additional rounds for under-explored areas (failure modes, financial flows, time-triggered events, system interactions, edge cases)
- After cool-down: `count 100-200` → healthy, proceed. `count > 200` → consider Chapters Sorting strategy for Enforce Timeline. `count < 100 still` → persona mix may lack diversity; consider adding a domain-specific persona
- This is a diagnostic signal, not a blocking gate — but treat sub-100 as a quality warning requiring action

**Legend completeness requirements (facilitator responsibility):**
The legend MUST be incrementally updated as each phase introduces new building blocks. A missing legend entry = a building block viewers can't decode. After each phase, verify the legend contains ALL building block types currently on the board:

- After Chaotic Exploration: Domain Event (orange)
- After Enforce Timeline: add Hot Spot (red), Temporal Milestone (dark_green), Pivotal Event (dark_blue), Phase Name (cyan)
- After People & Systems: add Person/Actor (yellow), External System (light_pink)
- After Walk-through: no new types, but verify existing entries are still visible
- After Value Exploration: add Value Created (green), Value Destroyed (pink)
- After Problems & Opportunities: add Arrow Vote (light_blue)
- Throughout: facilitator may note domain terms with precise meanings as gray stickies (facilitator observation, not a formal workshop step)

**Ubiquitous Language capture (facilitator observation, not a formal phase):**
Per Brandolini (Ch. 1): "When new terms arise, and the discussion shows that they have an exact meaning in that context, I start capturing key term definitions on a special sticky note and place them just below the normal flow." In simulation, the facilitator notes domain-specific terms with precise contextual meanings as they emerge organically during ANY phase — not as a dedicated step. Use gray stickies placed below the main flow. These are NOT Wikipedia definitions — just what each term means in THIS domain conversation. Examples: "CFP: Call for Papers", "Track: Parallel session stream."

At Wrapping Up, these gray stickies become graduation candidates: offer each resolved term for the consumer repo's committed project glossary — one entry per term with a 1–2 sentence definition of what it IS and a plain `Avoid:` line listing the rejected synonyms, project-context terms only. When `/domain-driven-design:curate-language` is available in the current session, delegate this active maintenance to it; the skill discovers the consumer's format and location and routes only among contexts already established by the workshop or project. Without that skill, preserve the same discovery-first, lazy fallback and ask when placement is ambiguous. Glossary graduation never discovers bounded contexts.

**Bounded context identification (POST-WORKSHOP homework — not a workshop phase):**
Brandolini is emphatic (Ch. 6): "Once the workshop is officially over, and participants left the workshop room, we can start talking software, ...finally!" and "We can't assume the business side to know about bounded contexts. BCs are mostly a software development issue." BC discovery is the software architect's homework AFTER the workshop, using these 6 heuristics from Ch. 6:

1. **Look at the business phases** — different phases = different problems = different models. Pivotal Events mark transitions
2. **Look at the swimlanes** — independent processes, especially on different timelines
3. **Look at the people on the paper roll** — different personas reveal different flows/needs
4. **Look at the humans in the room** — where people physically hovered reveals model distribution (in simulation: which persona generated the most events in which area)
5. **Look at the body language** — dissent, disagreement (in simulation: hot spots and divergence markers)
6. **Listen to the actual language** — same nouns used differently across contexts = different models. "Nouns are usually fooling us... Looking at verbs provides much more consistency around one specific purpose" (Ch. 6). In simulation: scan for events where different personas used different words for the same business moment

Punchline: **"Merge the people, split the software"** (Ch. 6).

In the simulation, run BC discovery as a separate facilitator activity AFTER the workshop phases complete. Use the 6 heuristics above against the board data. Present findings to the user — they are the architect's analysis, not workshop output. Use short names (2-3 words), not verbose descriptions.

**Board relationship tracking (simulation convenience — not from the book):**
After completing all formats (BP → PM → DL), place an Exploration Map on the Big Picture board showing: (1) which problem won the arrow voting, (2) which BC was explored in PM + DL, (3) which BCs were identified but NOT explored (future work), (4) aggregate names and counts from DL. This is a simulation artifact for session continuity — Brandolini's approach is to take pictures and fold the paper roll.

**Session lifecycle (setup → run → teardown):**

Every simulation session follows this lifecycle. The protocol ensures clean state, prevents artifact leakage between sessions, and supports concurrent execution across different conversations.

**Structured-markdown fallback mode:** when the Miro availability gate (SKILL.md "Miro availability & graceful degradation") has routed the run to structured-markdown output, SKIP every Miro-tool and board-screenshot step below — board creation, sticky placement, phase-transition screenshots (which need a browser MCP), and `miro_delete_board` teardown. In that mode the model, persona, and session-state steps still run; the board-rendering steps are replaced by appending to the markdown artifact. Only run the Miro/screenshot steps when the live-board path is active.

**1. Session Setup (before any board creation):**

- Generate session ID: `{domain}-{YYYYMMDD}-{random4}` (e.g., `devconf-20260321-a7f2`)
- Create session directory: `{session_dir}/personas/` (where `{session_dir}` is created by the secure temp primitive in "Persona Persistence Across Rounds" and its returned path is carried for the rest of the session)
- MCP preflight: test Miro MCP with a read-only call (e.g., `miro_list_boards`). If MCP fails, inform user and get approval for fallback
- Domain research: 3+ web-research searches (Perplexity MCP if present, else `WebSearch`) before building persona prompts
- Generate persona profile files (see "Persona Persistence Across Rounds" section above)
- Record session metadata in `{session_dir}/session-meta.md`: domain, personas, board IDs (updated as boards are created)
- Check the plugin data store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) for previous version boards and metrics (comparison baseline)

**2. Session Run (the simulation itself):**

- Create boards with descriptive names including version: `EventStorming Big Picture v{N} — {Domain}`
- Update `session-meta.md` with board IDs as they're created
- Update persona profiles after each round with events placed, people/systems added, challenges made
- Take screenshots at every phase transition (visual checkpoints)
- All board deletions require user confirmation (including cleanup of test boards)

**3. Session Teardown (after evaluation):**

- Update the plugin data store with version metrics, board URLs, and findings (`${CLAUDE_PLUGIN_DATA}/history.jsonl`)
- Ask user about persona temp files: "Delete persona profiles? (Can be archived for session replay)"
  - Delete the session directory recursively, path quoted (`rm -rf "{session_dir}/"` on POSIX/Git Bash; `Remove-Item -LiteralPath "{session_dir}" -Recurse -Force` on PowerShell)
  - Archive: copy to `${CLAUDE_PLUGIN_DATA}/sessions/{session_id}/` (see "Cleanup protocol" above)
- Clean up test/smoke-test boards (with user confirmation via `miro_delete_board`)
- Optionally clean up old version boards (keep only latest, with user approval)

**Concurrent session safety:**

- Session IDs include random suffix — no collision between conversations
- Temp directories are namespaced — `eventstorming-session-{id}` never overlaps
- Board names include version number — `v7`, `v8` etc. — visually distinct in Miro
- Persona profiles are session-scoped — one session's Organizer doesn't bleed into another's

**Key principles for realistic simulation:**

- **Parallel, quiet chaos** — everyone at the wall simultaneously. No imposed wave structure. "I am not expecting many conversations at this stage... I call this phase quiet chaos" (Ch. 4). Reactions and conversations come during Enforce Timeline, not during chaos
- **Duplicates are DESIRED** — agents writing independently about the same moment is a signal, not an error. During sorting, resist merging duplicates — divergent wordings for "apparently the same event" are bounded context signals (Brandolini Ch. 6). Genuine identical duplicates can be stacked but divergent phrasings stay visible
- **Asymmetric output is natural** — Domain Experts dump 15 events, New Hires add 5. Don't force equal output. "Some might work mostly alone, dropping the bulk of their expertise in a single strip of orange sticky notes" (Ch. 4)
- **The facilitator breaks "committee circles"** — if agents converge too quickly on clean consistent flows, prompt them to disagree. "Discussing to reach an agreement on every single sticky note, before writing it would kill workshop throughput and hide exactly the contradictions we want to explore" (Ch. 4)
- **No connectors / arrows** — per Brandolini (Ch. 7): "once an arrow is drawn, your brain avoids moving stickies to preserve arrows" (Sunken Cost Fallacy). In Miro, do NOT use connectors during Big Picture. Use proximity and temporal order instead
- **Continuous source validation** — after each phase, check: "Is this how it should be done?" against the bundled methodology references (`/event-storming:methodology`), which encode Brandolini's guidance. Only read the book itself if the user has supplied a copy; never block a phase waiting on the book — the bundled references are sufficient
- **"The model is still wrong"** — the workshop output is provisional. "Some inconsistencies could only be spotted by coding and testing the model in the real world" (Ch. 9). Don't fall in love with the artifact

**Convergence detection and committee-breaking (facilitator responsibility):**

Brandolini warns: "discussing to reach an agreement on every single sticky note, before writing it would kill workshop throughput and hide exactly the contradictions we want to explore" (Ch. 4). LLM agents share a base model and naturally converge — the simulation equivalent of a "committee circle."

**After Wave 1, the facilitator checks for premature convergence:**

1. Scan for events that use identical or near-identical phrasing across personas — if 3+ agents wrote the same event name with no variation, the "different perspectives" signal is missing
2. Check if any persona's events contradict another's — if not, prompt the skeptical personas: "The [Domain Expert] says [X happens]. From your experience in [Operations/Support], is that really how it works? What goes wrong?"
3. Look for suspiciously clean flows — real businesses are messy. If the event dump reads like a textbook process, invoke the "I don't trust the official version" principle and prompt: "This looks like the official process. What ACTUALLY happens?"

This is NOT a separate "contradiction round" — Brandolini explicitly warns against calling for problems too early (Ch. 4). It is the facilitator breaking committee circles, which is a continuous responsibility, not a phase.

**Round 2: Enforce Timeline**

**Choose a sorting strategy** (not always Pivotal Events):

- **Pivotal Events** (default): works when there's a clear linear flow with phase transitions
- **Temporal Milestones**: use when the domain has concurrent processes on different timescales (conference planning, project management). Place blue stickies at top: "1 year before", "6 months before", "1 month before", "1 week before", "Day of", "After"
- **Chapters Sorting**: use when event dump is very large (150+) — extract 15-25 key chapters first, sort them, then apply structure to the events
- **Swimlanes**: add after initial sorting when multiple actors run independent parallel flows. Uses vertical space heavily
- **Combine strategies**: Brandolini combines them — "it's hard to define the structure upfront"

**Steps:**

1. Facilitator selects sorting strategy based on domain characteristics
2. **Place temporal milestones/pivotal events ABOVE the persona event rows** (negative y) — these act as section headers, consistent with Brandolini's "colored tape" at the top of the wall
3. Identifies 4-5 **Pivotal Events** — mark with dark_blue stickies on the Pivotal Events row (see the Big Picture Y-Coordinate Table in `miro-integration.md`)
4. **Physically sort events into timeline zones** using `miro_update_sticky_note` to reposition each event to the correct x-zone under its milestone. Group events by milestone, maintain persona y-offsets within each zone. This is the digital equivalent of physically moving stickies along the paper roll
5. Places duplicates and near-duplicates NEXT TO each other (NEVER merge them) — these are bounded context SIGNALS. Place a hot spot between them: `[DIVERGENCE] Organizer says "X" vs Speaker says "Y" — different context?`
6. **Hot spots during enforcement are FACILITATOR-ONLY** — do NOT prompt personas for problems yet. "An explicit call for problems too early creates a flood with low signal-to-noise ratio" (Brandolini). The facilitator observes inconsistencies during sorting and marks them
7. **Do NOT walk through or reverse narrative yet** — that comes after People & Systems are visible (Round 4)

**Sorting layout (positioning strategy):**
Assign x-zones to each milestone. For Temporal Milestones with 7 zones:

- Zone 1 (12 months before): x=0 to x=2000
- Zone 2 (6 months before): x=2400 to x=4400
- Zone 3 (3 months before): x=4800 to x=6800
- Zone 4 (1 month before): x=7200 to x=9200
- Zone 5 (Conference week): x=9600 to x=11600
- Zone 6 (Conference day): x=12000 to x=15200
- Zone 7 (After conference): x=15600 to x=18000

Within each zone, events from different personas keep their original y-offsets (persona rows). Use `miro_update_sticky_note(board_id, item_id, x=new_x)` — read all items first, categorize by milestone zone, then reposition in batch

**Inter-round communication:** Agents read the board directly via `miro_list_board_items` at the start of each round — they see all events from all personas and react accordingly. The facilitator does NOT need to summarize board state. When boards exceed 100 items, the facilitator should provide agents with a structured summary organized by timeline position alongside the raw MCP read. Each persona agent sees the FULL event list (not just their own) so they can react to other perspectives.

**Board reading — full pagination required:**
The Miro API paginates results (typically 50 items per call). Agents and facilitators MUST read ALL pages when using `miro_list_board_items` — call multiple times until all items are retrieved. A partial board read is equivalent to a participant who can only see half the wall — they'll miss critical context and produce bad analysis. Brandolini's physical wall is always fully visible ("People will need to see the forest and the trees" — Ch. 4); our digital equivalent must be too.

**Facilitator step-back after Round 2:**
Run a facilitator step-back after Round 2 (not just after Round 4). Early step-backs catch persona gaps and thin zones before most rounds have executed, allowing targeted corrections while there's still time. The step-back after Round 2 checks: (1) Are all expected personas represented? (2) Are there obvious thin zones? (3) Is the board starting to look like process documentation instead of chaos? If any check fails, address it before proceeding — inject a missing persona, re-prompt thin-zone personas with stronger corrective instructions, or invoke the "I don't trust the official version" principle on suspiciously clean areas.

**Round 3: People and Systems (yellow + pink stickies)**

- NOW introduce actors (yellow) and external systems (pink) — not before
- Use "people" not "actors/users/roles/personas" — fuzzy definition for inclusion (Brandolini Ch. 4: "I prefer to use the term people")
- External system fuzzy definition: **"whatever we can put the blame on"** (Ch. 4). This may include non-software things: "Bad Luck," "Europe," "Brexit," "GDPR" — all legitimate
- Facilitator provides each persona with the sorted timeline, then prompts: "Looking at this timeline, who are the KEY PEOPLE involved in your area? What EXTERNAL SYSTEMS do you depend on or blame?"
- Place people on the People/Actors row and external systems on the External Systems row — both ABOVE the persona event rows, per the Big Picture Y-Coordinate Table in `miro-integration.md` (external systems sit at the top of the board, not below the flow)
- **Trigger the "Is this a person or a system?" conversation** — Brandolini highlights this as an interesting question that reveals ownership attitudes (Ch. 4). Prompt agents: "Is [thing X] a person or a system? Who owns it?"
- This triggers MORE events — "mundane activities that occur on the boundaries" (Ch. 4). Target: significantly more new events than v7's 14
- **Be alert for sarcastic complaints** — "I am usually alert for spontaneous comments (usually sarcastic complaints) that we should capture with Hot Spots" (Ch. 4). Prompt agents: "Any complaints about working with these systems?"
- **Adding systems triggers new events.** Per Brandolini Ch. 4: "Adding new systems usually triggers the need for more events." When personas place external systems on the board, the facilitator should prompt them: "What events happen BECAUSE of this system? What breaks when this system is down?" Expect 5-10 new events triggered by adding people and systems
- Update the legend with People and External Systems

**Round 4: Explicit Walk-through (FORWARD — separate from Reverse Narrative)**

- **This is the phase where the most discovery happens** — now that actors and systems are visible, the story has full context
- "A great way to enforce consistency during this phase is to ask someone to walk through the sequence of events while telling the story that connects them" (Ch. 4)

**Narrator relay race (not a single narrator):**
Rotate narrators at each pivotal event — the expert in that area tells the story for their segment. "This is where [Persona]'s team takes over" (Ch. 4). Handoff points are discovery moments — if the handoff feels awkward, there's a gap.

**Audience challenges the narrator:**
"Everybody in the room can (and *must*) interrupt you to challenge the ongoing storytelling" (Ch. 4). In simulation: after each narrator places their segment, spawn 1-2 OTHER persona agents to read the narrator's segment and challenge it. "Does this match YOUR experience? What's missing? What's wrong?"

**Narrative consistency probe (simulating "body feedback"):**
In a real workshop, the narrator physically walks along the wall and "your body will slowly try to walk forward, making you feel weird if the flow is not consistent" (Ch. 4). In the simulation, each narrator must construct a **natural-language paragraph** (not a list) connecting events in their segment. Any place requiring "and then somehow..." or a logical leap signals a gap. The narrator flags these: `[STUMBLE] I can't naturally connect [Event A] to [Event B] — what happens in between?` **"It is a good sign if your storytelling is bumpy and continuously forcing you to add more events. Your brain pain means that it's actually working"** (Ch. 4).

**New Hire agent:** Invoke here — their "stupid questions" challenge assumptions everyone else takes for granted.

**Round 5: Reverse Narrative (BACKWARD — separate phase)**
"Even if we think we're done with forward exploration, we usually discover a relevant portion of the system (around 30-40%) that was buried under the optimistic thinking" (Ch. 4).

This is a SEPARATE phase from Walk-through — different direction, different purpose:

- Walk-through goes FORWARD (left to right): "tell the story that connects them"
- Reverse Narrative goes BACKWARD (right to left): "pick an event from the end of the flow, then look for the events that made it possible"

**Steps:**

1. Pick terminal events and pivotal events as starting candidates. "Some events are natural candidates for backward exploration: terminal events (the ones at the end of the flow that seem to 'settle everything') are a natural fit" (Ch. 4)
2. For each, ask: "What needs to happen for [this event] to occur?" — the event must be a direct consequence of previous events with no magic gaps
3. "You might want to challenge the audience asking something like 'So [Event A] is all it takes to have [Event B]?'" (Ch. 4)
4. Repeat ad libitum for any event whose causal chain seems too optimistic
5. Target: **~30-40% additional flow** beyond what Walk-through found

**Round 5.5: Add the Money (bonus sub-phase)**
"Whenever I run a workshop with software developers, they invariably tend to neglect the money part of the flow" (Ch. 4). If the exploration looks naive on financial events, call a short exploration round focused on money flows: invoices, payments, refunds, revenue recognition, cost allocation, tax, insurance claims. Prompt the Finance/Organizer persona specifically.

**[Optional] Round 6: Value Exploration (not just money)**

Per Brandolini (Ch. 5) this is OPTIONAL — and happens AFTER Walk-through + Reverse Narrative, but BEFORE Problems & Opportunities. "Once the flow is adequately clear and consistent to everyone (usually after People and Systems and Explicit Walk-through), you may want to start digging into when and where value is delivered" (Ch. 5).

**Sub-round A — Financial value (green for creation, red for destruction):**
Start with money — "the most obvious choice" (Ch. 5). Facilitator prompts: "Where does money change hands? Where is value created? Where is it destroyed?"

**Sub-round B — Non-financial value currencies:**
"Things start getting interesting once we open up the possibility for other value currencies than money" (Ch. 5). Currencies: awareness, time, anxiety, stress, pride, reputation, safety, status, belonging. "Once you signal that 'we can actually talk about something else than just money' ...people start to talk!" (Ch. 5). For EACH persona: "What do YOU gain or lose at each step? Not money — think about time, stress, reputation, pride, belonging, safety, status, awareness." Place green for value gained, pink for value destroyed, with the currency labeled.

**Sub-round C — Contrasting perspectives:**
"A given step may be generating value for some parties while being a loss for somebody else" (Ch. 5). Identify events where multiple personas placed value stickies. Highlight contradictions. The same step generates value for some and destroys it for others — this reveals real business tensions.

**Sub-round D — Diverging perspectives (customer segments):**
"We start with the idea of attendee in mind, to discover that we have more sophisticated categories to play with" (Ch. 5). Prompt: "Are all attendees the same? Do they have the same needs?" Discover customer segments: learners, networkers, recruiters, community seekers. "Different needs and different values mean also that we probably can't improve the system in a one-size-fits-all fashion" (Ch. 5).

**Sub-round E — Explore Purpose (optional, powerful):**
"Failing to find a real reason why users should perform a given action can quietly kill a start-up idea" (Ch. 5). Prompt: "What is the PURPOSE of this conference? Is every step aligned with that purpose?" Brandolini's anecdote: someone said "I don't see the purpose of our job" — a game-changer moment.

**Round 7: Problems and Opportunities (red + green stickies)**

- NOW open the floor for hot spots (problems) and opportunities
- Facilitator provides full board summary (events + people + systems) to each persona
- Each persona generates 3 problems (red, "!!!" prefix) and 2 opportunities (green)
- Place hot spots above their related events, opportunities below
- Arrow voting: each persona picks their top 2 problems — facilitator tallies
- **Personas should react to each other's problems** — "The Attendee flagged X, but the Organizer sees that differently because..."

**Round 8: Pick the Problem + Next Steps**

- Tally votes, identify the winner
- Mark the winning problem prominently
- If a follow-up Process Modeling session is warranted, identify which bounded context area to zoom into
- That becomes a NEW board (separate from Big Picture)

### Subsequent Formats (Separate Boards)

**Process Modeling** (after Big Picture identifies the problem to solve):

Create a NEW Miro board. This is a different workshop with different participants (3-5 people, more technical). See `/event-storming:methodology --process` for full details.

**Board Setup:**

1. Create board titled "Process Modeling — [Selected Problem/Process]"
2. Create Legend frame showing "The Picture That Explains Everything": Actor → ReadModel → Command → System → Event → Policy → Command...
3. Carry over relevant events from Big Picture as starting context. **Do NOT create a growing timeline frame** (frame z-order gotcha in `miro-integration.md`) — use coordinate-based organization; the static Legend frame is the only frame
4. **Critical: display the color grammar visibly** — "there must be a lilac between an orange and the blue"

**Personas:** Reduce to 3-5 from Big Picture. Keep Domain Expert, add Developer, keep one business role. Drop broad stakeholders.

**Round 1: Happy Path — Rush to the Goal (events + commands + policies)**

- **First pass: build fast, don't perfect.** Follow Brandolini's "Rush to the Goal" (Ch. 15 and Ch. 30 — Ch. 15 introduces it in Process Modeling context, Ch. 30 is the dedicated patterns chapter): build the baseline happy path left-to-right as quickly as possible using the color grammar. Don't discuss perfect wording. Don't debate alternatives. Just get from trigger to termination
  - Orange (events) — state transitions, past tense, strictly enforced
  - Blue (commands) — user intentions/actions, present tense
  - Lilac (policies) — "whenever X happens, do Y" — reactive logic between events and commands
- **Strict rule:** Every command→event pair must pass through a system/aggregate. Every event→command reaction must go through a policy (lilac). No implicit cascading
- **Second pass: Speak Out Loud.** Read EACH policy aloud: "Whenever we receive [event], we [command]..." Inconsistencies surface when spoken — "I can't even finish the sentence, because I will sound stupid saying so" (Brandolini, Ch. 14 — Process Modeling Building Blocks)
- **Third pass: Magic words challenge.** For each policy, add "Always" and "Immediately" — "Do we ALWAYS do this? Do we do it IMMEDIATELY?" These words trigger objections that reveal conditions, exceptions, and timing constraints. Update policies, add read models for information needed, split policies when behavior differs by context
- **Flood with hot spots.** After the baseline is complete, the facilitator marks everything that feels wrong or incomplete. "I just need a solution, not a good one." (Brandolini, Ch. 15 / Ch. 30)

**Round 2: Alternative Paths + Unfulfilled Expectations**

- For each command: "What if it fails? What if it's rejected? What if it partially succeeds?"
- Place happy path events on the Main Flow row; route failure/rejection alternatives to the
  Exception flows row and additional/secondary alternatives to the Secondary alternatives row
  (see the Process Modeling Y-Coordinate Table in `miro-integration.md`)
- **Events that are NOT happening** (Ch. 14): Model unfulfilled expectations via time-triggered events. "End of day happened before Greeting Received" models a forgotten birthday. Prompt agents: "What SHOULD happen but doesn't? What deadlines expire? What expectations go unfulfilled?" Making the time-frame explicit leads to interesting insights
- Continue until all paths reach a stable state (System Happy + User Happy)

**Round 3: People, Systems, and Read Models**

- Add actors (yellow) above commands — who issues this command?
- Add external systems (pink) — which specific systems are involved? (more precise than Big Picture's fuzzy definitions)
- Add read models (light_green) — what information does the actor need to make this decision?
- **Conversational systems** (phone, email, chat): don't script the conversation, focus on the termination condition
- **"Drop your guns at the saloon entrance"** (Ch. 13): PM requires giving up specialized jargon. Agent prompts for PM rounds should include: "Use business language everyone understands. Technical jargon and UX notation create invisible barriers."

**Round 4: Precision Rewrite**

- Review and rewrite events for increased precision — different rounds increase semantic precision and require more events (Ch. 14: "be ready to rewrite events many times"). Prompt each agent: "Look at your events from Round 1. Now that you understand the flow better, which events need sharper wording? Which need to be split into multiple events?"
- Add hot spots for any remaining unresolved policy disagreements

**Win Conditions (game ends when ALL are met):**

1. All process paths are **completed** — every path reaches a stable state
2. The **color grammar** is preserved — no holes, no missing policies between events and commands
3. Every **hot spot** is addressed (resolved or explicitly deferred)
4. All stakeholders are **reasonably happy** with the model

---

**Design-Level** (after Process Modeling converges on a solution):

Create ANOTHER new Miro board. This is mostly developers (3-7) + one domain expert. See `/event-storming:methodology --design-level` for full details.

**Board Setup:**

1. Create board titled "Design-Level — [Bounded Context Name]"
2. Create Legend showing all building blocks including Aggregates (pale yellow)
3. Carry over the Process Model events, commands, policies as starting context

**Personas:** 3-7, mostly developers. Keep one Domain Expert for validation. Drop business-only roles.

**Steps 1-2: Events + Commands (15 min)** — Carry over events from PM. Add commands (reverse verb tense: `Game Started` → `Start Game`). Mechanical scaffolding.

**Step 3: Actors, Policies, External Systems (15-20 min)** — Add actors (yellow), policies (lilac), and external systems (pink). Critical `[BOURGAU]` insight: other bounded contexts become pink stickies here — making integration boundaries visible before aggregate discovery.

**Step 4: Read Models + UX Mock-ups `[BOURGAU]` (20-30 min)** — Place green stickies (Read Models) showing what actors need to see to decide. Optional white stickies for UX wireframes. Domain experts and UX people can work in PARALLEL here. This is one of two critical discussion moments.

**Step 5: Place Blank Business Rules (5 min)** — For every command-event pair NOT already linked by a pink External System, place an empty pale yellow sticky between them. Purely mechanical. Call them "Business Rules" not "Aggregates" — "Don't talk about DDD" `[BOURGAU]`.

**Step 6: Fill Business Rules — Discover Invariants (20-30 min)** — Second critical discussion moment. For each blank yellow sticky, fill in preconditions ("what must be true before?"), postconditions ("what is true after?"), and invariants ("what must remain true all along?"). Brandolini: look for responsibilities first, then information needed, THEN name.

**Step 7: Group → Aggregates (15-20 min)** — When two business rules deal with similar data or enforce related invariants, stack them vertically. This BREAKS the timeline — that's expected. Commands enforcing the same invariant share an aggregate. **Consolidation challenge (facilitator):** If aggregate count exceeds command count, something is wrong — group by shared invariant, not by entity.

**Step 8: Name the Aggregates (5-10 min)** — LAST step for naming: "What would you call a class that does X and enforces Y?"

**Step 9: Identify Bounded Context Contracts (10 min)** — Which events need to be published to other contexts? Which commands come from outside?

**Step 10: Wrap Up and Code (5 min)** — "The roll is not the deliverable." Start coding ASAP

### BDUF Warning Gate (after Design-Level of the top 1–2 BCs) `[BRANDOLINI]` `[BOURGAU]`

After Design-Level modeling the **arrow-voting winner** BC (and at most one runner-up), STOP and surface this gate BEFORE modeling any further bounded context. Modeling all remaining BCs up front is Big Design Up Front — the single biggest deviation from Brandolini's method (`/event-storming:methodology --design-level` "Post-Workshop Strategies" — never spend more than two full days total).

Default action: **START CODING the top-priority BC.** Present to the user verbatim:

> "Per Brandolini: we have enough to start coding. The arrow-voting winner BC has been Process Modeled and Design-Level modeled. Modeling the remaining BCs now would be Big Design Up Front. Recommendation: START CODING the top-priority BC. Model additional BCs when they become the implementation priority."

Continue to additional BCs ONLY on explicit user opt-in that acknowledges it exceeds Brandolini's recommended scope. When the user opts in, label the extended boards **"Exploratory — exceeds Brandolini's recommended scope"** (valuable as domain-exploration / architecture-planning artifacts, not method-endorsed).

### Spacing and Frame Management

Big Picture y-coordinates follow the canonical **Big Picture Y-Coordinate Table** in
`miro-integration.md` — it is the single source of truth. Do not restate coordinate values here.

Layout invariants for the agentic run:

- **Each persona is assigned one event row** from the canonical table (Persona 1 at the `y=0`
  timeline baseline, e.g. Domain Expert → Persona 1, Developer → Persona 2, Operations → Persona 3,
  …). **Personas keep that row across both Chaotic Exploration (Round 1) and Enforce Timeline
  (Round 2+)** — sorting moves stickies along x into milestone zones, never off their persona row.
  During Chaotic Exploration, x values spread across the timeline width, roughly chronological but
  not sorted — chaos is expected.
- **Header rows sit above the persona rows** (External Systems, Pivotal Events, People/Actors,
  Divergence Markers) and **post-timeline content sits below** (walk-through, reverse narrative,
  value created/destroyed, UL terms, problems, opportunities, arrow votes, BC labels) — all per the
  canonical table.
- **400px horizontal** between flow items; **≥250px vertical** between adjacent rows
  (`miro-integration.md` "Positioning Strategy (Tested Values)").

**Do NOT create or resize timeline frames.** A frame sized to the growing flow must be resized each
round, and frames created or recreated after their content render on top and hide it (frame z-order
gotcha in `miro-integration.md`). Use coordinate-based organization; the static Legend frame is the
only frame. **Place a copy of the legend near the sorted timeline** (not just near the chaotic dump)
so users don't have to scroll back.

### Attribution

Include persona name in sticky content for traceability:

- `[DomainExpert] Order Placed`
- `[Developer] !!! Race condition on concurrent orders`
- `[Operations] Payment Gateway Timeout`

---

## Tips for Effective Simulation

1. **Feed real domain context** — the simulation is only as good as the context each persona receives. Use WebSearch/Perplexity to research the domain before building prompts
2. **Don't skip the New Hire** — their "stupid questions" surface the most valuable assumptions
3. **Embrace disagreement** — if all personas agree, your prompts aren't diverse enough
4. **Use simulation to PREPARE for real workshops** — the output is a draft, not a final model
5. **Run Process Modeling simulations with fewer personas** (3-5) focused on one bounded context
6. **Run Design-Level simulations with mostly developer personas** plus one domain expert for validation
7. **The facilitator role is yours** — you decide when to push deeper, when to move on, when to add space

---

## Variation Modes — Execution Details

These modes are variations on the core Big Picture simulation. Each modifies the standard flow rather than replacing it. See SKILL.md for invocation syntax.

### `--retrospective` — Organization Retrospective (Book Ch. 1 story 4, Ch. 10)

**How it differs from `--simulate`:**

- **Framing:** "What ACTUALLY happens?" vs "What should happen?" — Brandolini's "I don't trust the official version" is the default posture, not a fallback
- **Personas:** Use real organizational roles, not generic archetypes. Research the specific company/industry structure. Include the "frustrated veteran" who knows all the workarounds
- **Chaotic Exploration prompt override:** "Write the events that ACTUALLY happen in your daily work — not the official process, not what the manual says, not what your boss thinks happens. The real sequence, including the manual workarounds, the shortcuts, the things you'd never put in a slide deck."
- **Value Exploration emphasis:** Problems & Opportunities phase is the primary output (not BCs). Green opportunities = "what would make your life easier?" Red problems = "what makes you want to quit?"
- **Post-workshop:** No BC discovery. Instead, produce a ranked list of improvement opportunities with Theory of Constraints framing: "Which single bottleneck, if removed, would have the biggest impact?"

### `--induction` — New Hire Onboarding (Book Ch. 10)

**How it differs from `--simulate`:**

- **Persona hierarchy inverted:** The New Hire is the PRIMARY narrator. They model first, using guesses and assumptions. Senior personas REACT to correct errors — "Let's start modelling what you think is happening in this organization!" (Ch. 10)
- **Facilitator behavior:** Actively protect the New Hire from being steamrolled by expert corrections. "Let them finish their guess before you correct."
- **Chaotic Exploration:** New Hire goes FIRST (solo agent, 8-10 guessed events). Then spawn expert agents to read the New Hire's events and react: "What did they get right? What did they get wrong? What critical steps did they miss?"
- **Walk-through:** New Hire narrates the ENTIRE flow. Experts interrupt only when the story goes seriously wrong. Wrong guesses that provoke expert explanations are the primary output
- **Success metric:** Not event count or coverage — success is measured by how many expert corrections surfaced tacit knowledge the experts would never have volunteered unprompted

### `--value` — Standalone Value Exploration (Book Ch. 5)

**Prerequisites:** Requires an existing Big Picture board with People & Systems and Walk-through completed. Read the board via MCP before starting.

**Execution:** Run all 5 sub-rounds from Ch. 5 as separate agent rounds on the existing board:

1. **Financial value:** Spawn each persona — "Where does money change hands? Place green stickies for value created, pink for value destroyed, along the existing event flow"
2. **Non-financial currencies:** Re-prompt each persona — "Now forget about money. Think about: time, stress, reputation, pride, belonging, safety, status, anxiety, awareness. What do YOU gain or lose at each step?"
3. **Contrasting perspectives:** Facilitator reads the board, identifies events where multiple personas placed value stickies. Spawn 2-3 personas to debate: "The [Expert] says this step creates value. The [User] says it destroys value. Who's right?"
4. **Diverging perspectives (segments):** Prompt — "Are all users the same? Do they have the same needs?" Discover segments. For each segment, re-evaluate the value stickies
5. **Explore Purpose:** "What is the PURPOSE of this business/product? Is every step aligned with that purpose? Are there steps that actively contradict the purpose?"

### `--ux` — UX-Driven EventStorming (Book preface + "Transactions Redefined" talk)

**What it is:** Process Modeling with the lens shifted to user/customer journey. Brandolini describes it as "similar to Value-Driven, focusing on the User/Customer Journey in the quest for usability and flawless execution." This is NOT a separate format with different mechanics — it's PM with a UX emphasis. No dedicated chapter exists in the book; this mode synthesizes from Brandolini's description, his "Transactions Redefined" DDD Europe 2017 talk, and Avanscoperta's PM "Rule 3" (stakeholder happiness opens the door to UX concerns).

**How it differs from standard `--process-model`:**

- **Persona emphasis:** Must include End User / Customer as PRIMARY persona — they narrate first, other personas react. UX Designer persona strongly recommended
- **Walk-through narration:** The End User narrates the ENTIRE flow from their perspective — not from the system's perspective. "I go to the website, I see X, I click Y, I wait, I get confused, I try again..." The emotional journey is as important as the functional flow
- **Emotional annotations:** After each command/event pair, the End User places an emotional annotation: frustrated, confused, delighted, anxious, bored, trusting, abandoned. Use pink stickies (value destroyed) for negative emotions and green (value created) for positive ones, placed directly above the relevant event
- **Friction point identification:** Hot spots specifically target UX friction: "I don't know what to do here", "This takes too long", "I expected X but got Y", "Why am I being asked this?"
- **"Flawless execution" test:** For each step, ask: "If this step worked PERFECTLY — zero friction, zero confusion, instant response — what would it look like?" Place the ideal version alongside the current version. The gap between them is the UX opportunity
- **Read Models are UI views:** Green stickies during this mode represent what the user SEES, not what the system stores. Sketch wireframes or describe the information display: "Order confirmation with estimated delivery date and tracking link"
- **Implicit deadlines (from "Transactions Redefined"):** Brandolini's talk emphasizes that users have IMPLICIT time expectations at each step. "How long is the user willing to wait here before they assume something went wrong?" Add clock/calendar annotations for user patience thresholds

**PM Round modifications for UX mode:**

- Round 1 (Rush to Goal): End User narrates the happy path. Developer/Domain Expert react with system events
- Round 2 (Alternative Paths): Focus on "what goes wrong FROM THE USER'S PERSPECTIVE" — not system errors, but user confusion, dead ends, unclear feedback
- Round 3 (People/Systems/Read Models): Read Models are UI mockups. External Systems include "the user's mental model" as a legitimate external system (often wrong about how things actually work)
- Round 4 (Precision Rewrite): Rewrite events to include the user's EMOTIONAL state change, not just the system state change

### `--crc` — Event-Driven CRC Cards Validation (Book Ch. 22)

**Prerequisites:** Requires a completed Design-Level board with named aggregates. Read the board via MCP.

**Execution:**

1. **Assign roles:** For each aggregate on the DL board, spawn a separate agent. That agent IS the aggregate — it can only see its own state and the commands/events it owns
2. **Pass cards:** The facilitator constructs a scenario (a user story or use case from the DL board). The facilitator sends the first Command card to the relevant aggregate agent
3. **Process:** The aggregate agent checks its invariants, produces Event cards (or rejection events), and declares which other aggregates/policies should receive them
4. **Chain:** The facilitator routes Event cards to the relevant Policy agents, who produce Command cards for the next aggregate. Continue until the scenario reaches a stable state
5. **Constraint:** Agents can only TELL (produce output), never ASK (request information from other agents). If an aggregate needs information to make a decision, it must already have it or the model is wrong
6. **Output:** A validated interaction map showing which aggregates talk to which, through which events. Any point where the chain breaks or an agent says "I don't have enough information" reveals a model flaw
