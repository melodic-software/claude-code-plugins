---
name: clarify
description: "Faithfully clarify a dense, decision-heavy message you were just handed so you can act on it — chunk it into one-decision-at-a-time, define the session's own jargon, and surface exactly what you must decide, with every recommendation's operative terms quoted verbatim and no loss of precision or reading level. For big or decision-dense content, renders an HTML decision table (item | recommendation | alternative | what-you're-deciding, rows numbered so terminal answers map back). Use when: 'make this clear', 'clarify this', 'help me digest this', 'break this down', 'I can't parse this', 'what am I actually deciding here', 'this is a wall of text'. Empty argument targets the previous assistant response; an explicit target overrides. This changes STRUCTURE, not altitude — it makes the same content clear without simplifying it; a lossy plain-language / ELI5 drop that trades precision for simplicity is education:explain (if installed) instead. Sibling to adhd:shape, a standing session-wide output posture; this is a one-shot reshape of one artifact."
argument-hint: "[artifact to clarify] (empty = the previous assistant response)"
user-invocable: true
disable-model-invocation: false
metadata:
  cheatsheet-stage: anytime
  cheatsheet-summary: Reshape a dense, decision-heavy message into clear one-decision-at-a-time chunks, losing nothing
---

# Clarify a dense artifact into something you can act on

You were just handed a wall of text — an interview round with seven
cross-referenced questions, a design memo thick with session jargon. This skill
takes **that exact artifact** and makes it clear enough to act on: one decision
at a time, jargon defined, and the actual choices pulled to the surface.

The move is **clarify by restructuring, never by simplifying**. The content stays
at full precision and full reading level; only its *arrangement* changes. Lowering
the altitude — plain words, an analogy, ELI5 — is a different job (see
[Boundaries](#boundaries)). A clarification that loses or softens a decision is
worse than the wall of text, so the fidelity rules below are hard, not aspirational.

## The core move

1. **Identify the target.** With an argument, that is the thing. Empty
   argument → the **previous assistant response** (see [Empty
   argument](#empty-argument--anaphora-default)).
2. **Ground it, don't recall it.** Re-read the actual artifact this turn — the
   message just sent, in full. Working from your memory of it instead of its text
   is how operative terms drift.
3. **Restructure faithfully** — chunk, define jargon, surface decisions
   (below), under the fidelity rules.
4. **Choose the medium** — artifact, local file, or terminal — per
   [Rendering](#rendering-artifact-forward).

## Empty argument — anaphora default

With no argument, the target is the **assistant's own previous response** — the
thing the reader is reacting to. "Make this clear" needs no topic named:
re-read that prior message and clarify it. When there is **no prior assistant
message** — a cold start where the reader opens with "make this clear" and
nothing has been said — do not invent a target: ask what to clarify.

**Trivial-target escape hatch.** When the resolved target holds fewer than ~2
decisions — a short answer, a status line, anything with nothing to untangle —
do **not** run the full table/glossary apparatus on it. Say in one line that
the target has nothing dense to clarify, and ask what the reader actually
wanted clarified. A three-line response restructured into a one-row decision
table is ceremony, not clarity.

**Conflicting-shaper note.** If a terse-for-tokens output shaper (e.g. caveman
hooks) is active in the session context, say so before rendering: this skill's
faithful, structure-adding output directly contradicts a strip-words directive,
and the two cannot both govern the same response. Advisory only — name the
source and let the user pick.

## Fidelity rules (hard)

A clarification is a **lens on the original, not a replacement for it.** These
four rules are non-negotiable, because a restructure that corrupts a decision
defeats the purpose:

1. **Quote operative terms verbatim.** The load-bearing words of every
   recommendation — the chosen option, the number, the named file, the
   condition, the verb that decides — are **copied, never paraphrased**. Restate
   surrounding framing in your own words if it helps; never the terms the reader
   will act on. "Go with option B, patch bump, gated behind `--force`" survives
   into the clarified version character-for-character.
2. **Keep the original numbers as back-links.** Every chunk carries the
   original item's own identifier (Q9, Round 4 · P15b, §3) so the reader can jump
   back to the source. This is separate from any numbering this skill adds for
   itself (see [Rendering](#rendering-artifact-forward)) — never collapse the two.
   When the original carries **no identifiers** (a dense prose memo with no Q-numbers
   or section marks), synthesize a locator and say you did: a sequential marker
   ("¶2", "Para 3") or the chunk's quoted opening phrase — never leave a chunk
   with no way back to its source passage.
3. **List omissions explicitly.** Anything in the original you did not carry
   forward — a caveat, a fifth option, a dependency — is named in a short "Left
   out" note, not silently dropped. The reader decides whether an omission
   mattered; you do not get to decide it for them by hiding it.
4. **State that it is a lens.** Close with one line: this is a clarification —
   validate final answers against the original text, not against this
   restructuring.

## Restructure moves

### Chunk into one decision at a time

Split the artifact so each chunk holds exactly **one** thing the reader
resolves. A round of seven bundled questions becomes seven chunks. No chunk
hides a second "and also decide." Order chunks so a prerequisite decision comes
before the one that depends on it, and say so when it does.

### Define the session's own jargon

A dense artifact leans on shorthand coined earlier in the session — "the lane,"
"gate vacuity," "managed components," "P15b." Collect every such term and define
it once, in plain words, in a short glossary the reader can see while reading the
chunks (not one they must remember from earlier). Define the shorthand; do
**not** simplify the concept it names — the definition is a pointer to the term,
at the same altitude.

### Surface what must be decided

For each chunk, make the actual choice unmissable: the recommendation (verbatim),
the alternative it was chosen over (verbatim, if the original named one), and, in
one sentence, **what the reader is actually deciding** — the crux, not a
restatement of the option. If the original only recommends with no alternative,
say so rather than inventing one.

## Rendering: artifact-forward

Decision-dense content wants a table, not a paragraph — a table is the part a
plain reply cannot do well. Pick the medium by what the session can render and
how heavy the content is:

| Content | Surface available | Render as |
|---|---|---|
| Big / decision-dense (roughly 3+ decisions) | Artifact tool present in this session | **Published HTML artifact** |
| Big / decision-dense | No artifact surface (e.g. plain terminal), file writing useful | **Local HTML file** under plugin data / temp, hand back the path |
| Small (1–2 decisions), or no useful file surface | either | **Structured terminal markdown** |

The Artifact rendering surface is a claude.ai-hosted capability — present in some
sessions and absent in others. Detect it: if the Artifact tool is available, that
is the top rung; otherwise degrade down the ladder. Never claim a decision table
was rendered when only prose was produced.

Write any local HTML file to an **OS temp path** (the session's scratchpad
directory when the harness provides one, else the platform temp dir) and hand
back that path — a clarified view is transient generated state, so it never
lands in the consumer's repository tree. Do not rely on a plugin-data
substitution variable for this location: skill-body substitution is documented
only for a fixed set of variables, and an undocumented token can substitute
unpredictably (including to the wrong plugin's directory when the token
travels through another skill's arguments). If no writable temp location nor
the Artifact surface is available, drop to the terminal-markdown rung rather
than writing into the repo.

The fidelity rules hold in **every** medium — verbatim terms, original-number
back-links, omissions, lens line — table or prose.

### The decision table

Whichever medium, the decision table has numbered rows and these columns:

| # | Item | Recommendation | Alternative | What you're deciding |
|---|------|----------------|-------------|----------------------|
| 1 | Q9 | *(verbatim operative terms)* | *(verbatim, or "none offered")* | the crux in one sentence |
| 2 | Q10 | *(verbatim)* | *(verbatim)* | … |

- The **`#` column is the table's own row number** (this skill's) — its job is
  answer-mapping, so the reader can reply "row 2: take the alternative" and you
  know exactly which original item that resolves.
- The **`Item` column is the original identifier** (Q9, §3, Round 4 · P15b) — the
  back-link to the source. Two numbering systems, kept distinct.
- **Recommendation and Alternative cells carry the verbatim operative terms.** A
  cell is where paraphrase and truncation creep in; resist both. If a
  recommendation is too long for a cell, quote its operative clause verbatim and
  link the row to the fuller original by its `Item` number — never a lossy summary.
- **Escape copied text before it becomes HTML.** In the artifact and local-file
  media, treat every copied term as text content and HTML-escape it. Operative
  terms often contain code-like characters (`<dialog>`, `A && B`, `--force`); left
  raw, a `<tag>` gets eaten or the table breaks, so escaping is what keeps rule 1's
  verbatim promise *true in the rendered page*. It also closes an injection vector:
  the artifact you are clarifying may be untrusted, and unescaped markup copied
  from it would execute in the published page. In terminal markdown, wrap such
  terms in backticks so they render literally.

### Honoring the Artifact contract

When you publish an artifact, honor the Artifact tool contract. **Load the
`artifact-design` skill for the design fundamentals when it is available** — it
ships with the artifact surface, so it is normally present on the publish rung;
if it is not, meet the contract's essentials directly rather than skipping them:
a self-contained page (no external hosts), theme-aware, a title and one-line
description, a favicon. Either way, the decision table is the page's spine — keep
the treatment utilitarian, not a flashy hero — and this static table needs no
runtime capabilities. In the terminal, give a one-line summary and the artifact
link (or the local file path); don't reprint the whole table twice.

## Boundaries

**vs `education:explain` — structure, not altitude.** `explain` drops the
*altitude*: plain words, a concrete analogy, ELI5 — it trades precision for
accessibility, and it climbs back up only on request. This skill holds altitude
**fixed** and changes *arrangement*: same precision, same reading level, made
clear by reorganizing. The routing rule: "I don't get it / explain simply / what
does this mean" is a comprehension gap → `explain`; "make this clear / clarify
this / what am I deciding" is a structure problem → this skill. When a reader
genuinely needs the concept made simpler, hand off to `/education:explain` (if the
`education` plugin is installed); otherwise a faithful restructure is this skill's
job.

**vs `adhd:shape` — one-shot, not standing.** `shape` is a **standing** posture:
invoke it once and every response for the rest of the session is shaped. This is
a **one-shot** reshape of **one** artifact already on screen — it does not change
how future responses are written. Use `shape` to set the house style; use this to
rescue a specific wall of text. Two interaction rules when both are active:
the decision table is **exempt from shape's five-item list cap** (fidelity
forbids dropping decisions, and fidelity wins over shaping); and when the
target is shape-formatted output, judge by the target's **actual decision
density, never its provenance** — an already action-shaped, low-density
response has nothing left to restructure (take the trivial-target escape
hatch), but a dense multi-decision artifact still gets the full faithful
restructure even though shape produced it (shape's explain override emits
long, decision-heavy responses with no glossary, locators, or table).

## Gotchas

- **Clarifying is not summarizing.** A summary drops detail to save length; this
  keeps every decision and rearranges it. If the reader ends up with fewer
  decisions than the original held, that is a fidelity-rule-3 omission you failed
  to declare.
- **Verbatim means verbatim.** The temptation to "clean up" a recommendation into
  a tidy cell is exactly the corruption the fidelity rules exist to stop. Copy the
  operative terms.
- **Don't lower the altitude to fit the table.** A cramped cell is a reason to
  quote the operative clause and link out, never a license to simplify the
  content. Simplifying is `explain`'s job, not this one.

## What this skill does NOT do

- **Not a simplifier / ELI5.** Altitude stays fixed. Lowering it is
  `education:explain`.
- **Not a summarizer.** It keeps every decision; it does not compress the artifact
  to its gist.
- **Not a standing output posture.** It reshapes one artifact once; the
  session-wide shaper is `adhd:shape`.
- **Not an input-capture form.** It renders a clarified view to read and answer
  from; collecting answers *through* an artifact form is a deferred, separate
  capability.
