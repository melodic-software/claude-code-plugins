---
description: "Faithful restructure of one dense, decision-heavy message: one decision at a time, the session's jargon defined, the choices surfaced with operative terms quoted verbatim, and an HTML decision table for decision-dense content. Use when the user says 'make this clear', 'clarify this', 'help me digest this', 'break this down', 'I can't parse this', 'what am I actually deciding here' or 'this is a wall of text'; with no argument it targets the previous assistant response. Changes structure only: a plain-language drop is education:explain, a picture or ELI5 is education:illustrate, a standing session style is adhd:shape."
argument-hint: "[artifact to clarify]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Reshape a dense, decision-heavy message into clear one-decision-at-a-time chunks, losing nothing
---

# Clarify a dense artifact into something you can act on

Clarify by restructuring, never by simplifying: precision and reading level stay fixed, only the
arrangement changes. A clarification that loses or softens a decision is worse than the original,
so the fidelity rules are hard.

## The core move

1. **Identify the target.** The argument, or with none, the previous assistant response
   ([Empty argument](#empty-argument)).
   **Done when** you can name the target, or, on a cold start, have asked what to clarify.
2. **Re-read it this turn, in full.** Working from memory of it is how operative terms drift.
   **Done when** you can quote an operative term from its text.
3. **Restructure faithfully**: chunk, define jargon, surface decisions, under the fidelity rules.
   **Done when** every decision from the target appears in the restructured view and every
   omission is named.
4. **Choose the medium** per [Rendering](#rendering).
   **Done when** the output is on the rung the table names for this session and content size,
   and you claim no artifact that was not produced.

## Empty argument

With no argument, clarify the assistant's own previous response. With no prior assistant
message, ask what to clarify; never invent a target.

**Trivial target.** When the target holds fewer than about two decisions (a short answer, a
status line), skip the table and glossary: say in one line that it has nothing dense to clarify
and ask what the reader wanted clarified.

**Conflicting shaper.** If a terse-for-tokens output shaper (for example caveman hooks) is active
in the session context, say so before rendering: this skill adds structure that a strip-words
directive contradicts. Name the source and let the user pick.

## Fidelity rules (hard)

1. **Quote operative terms verbatim.** The load-bearing words of every recommendation (the chosen
   option, the number, the named file, the condition, the deciding verb) are copied, never
   paraphrased. "Go with option B, patch bump, gated behind `--force`" survives character for
   character. Surrounding framing may be reworded.
2. **Keep the original identifiers as back-links.** Every chunk carries the original item's own
   identifier (Q9, Round 4 · P15b, §3), separate from any numbering this skill adds. When the
   original has none, synthesize a locator ("¶2", or the chunk's quoted opening phrase) and say you
   did. No chunk is left without a way back to its source passage.
3. **List omissions explicitly.** Anything not carried forward (a caveat, a fifth option, a
   dependency) is named in a short "Left out" note. The reader decides whether it mattered.
4. **State that it is a lens.** Close with one line: this is a clarification; validate final
   answers against the original text, not this restructuring.

## Restructure moves

- **One decision per chunk.** Seven bundled questions become seven chunks; no chunk hides a second
  decision. Put a prerequisite decision before the one that depends on it, and say so.
- **Define the session's own jargon.** Collect every term coined earlier in the session ("the
  lane", "gate vacuity", "P15b") and define each once, in plain words, in a glossary visible beside
  the chunks. Define the shorthand at the same altitude; do not simplify the concept.
- **Surface what must be decided.** Per chunk: the recommendation (verbatim), its `Basis:`
  (verbatim), the alternative it was chosen over (verbatim, or "none offered"), and one sentence
  on what the reader is actually deciding: the crux, not a restatement of the option.

Carry `Basis:` through unchanged: "none stated" when the source gave none, never an inferred one.
It has three outcomes: `Basis: verified` with the `file:line`, tool output or URL;
`Basis: judgment`, allowed only for a recommendation that is not consequential (cross-repo, shared
infrastructure, irreversible, or security); or **withheld**, where the source raised an unsettled
consequential choice as an open question. A withheld item shows "withheld" in the Recommendation
cell and the evidence that would settle it in the Basis cell, never an invented recommendation. A
recommendation the source re-stated as old → new → why keeps all three parts. Full convention:
[recommendation-basis](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/recommendation-basis/README.md#basis-label).

## Rendering

| Content | Surface available | Render as |
|---|---|---|
| Big / decision-dense (roughly 3+ decisions) | Artifact tool present in this session | **Published HTML artifact** |
| Big / decision-dense | No artifact surface, file writing useful | **Local HTML file** in the OS temp directory; hand back the path |
| Small (1–2 decisions), or no useful file surface | either | **Structured terminal markdown** |

Detect the Artifact tool; degrade down the ladder when it is absent. Never claim a decision table
was rendered when only prose was produced.

For a local file, create one file per run through the platform's temp API, never an accumulating
tree, and hand back its path; never write into the consumer's repository, and do not delete the
file before returning. Resolve that path the same way every run: do not branch on an injected
scratchpad path or `CLAUDE_JOB_DIR`, never depend on the session scratchpad, and do not use a
plugin-data substitution variable for it.

- **Pointer**: when choosing any `${…}` token for this skill's body, fetch
  [Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions)
  live. **As of**: 2026-10-11. **Recheck trigger**: that section adds a plugin-data or
  temp-directory variable, or documents the session scratchpad.

With neither a writable temp location nor the Artifact surface, use terminal markdown. The
fidelity rules hold in every medium.

### The decision table

| # | Item | Recommendation | Basis | Alternative | What you're deciding |
|---|------|----------------|-------|-------------|----------------------|
| 1 | Q9 | *(verbatim operative terms)* | *(verbatim, or "none stated")* | *(verbatim, or "none offered")* | the crux in one sentence |

- **`#` is the table's own row number**, so the reader can answer "row 2: take the alternative".
  **`Item` is the original identifier**, the back-link. Keep the two distinct.
- **Recommendation, Basis and Alternative cells carry the verbatim operative terms.** If one is
  too long for a cell, quote its operative clause and point to the original by its `Item`; never
  a lossy summary.
- **The rendered-views security baseline governs the artifact and local-file media.** It is owned
  by `docs/conventions/rendered-views/README.md` ("Security baseline") in the marketplace
  repository and repeated here because this skill runs where that file is not on disk. Everything copied <!-- contract-restatement-begin: rendered-views-security-baseline -->
  into the page is untrusted data: escape `&`, `<`, `>`, `"`, and `'` in text
  and attribute positions; never interpolate unescaped content into `<script>`
  or `<style>`; never build an event-handler attribute from input. The page is
  self-contained: no external requests, no remote scripts, assets inline. <!-- contract-restatement-end: rendered-views-security-baseline -->
  Operative terms often carry code-like characters (`<dialog>`, `A && B`, `--force`); escaping
  keeps them verbatim in the page. In terminal markdown, wrap such terms in backticks.

### Publishing an artifact

Load the `artifact-design` skill when it is available. When it is not, meet the Artifact tool's
own stated requirements and keep the page self-contained.

- **Pointer**: when `artifact-design` is absent, read the Artifact tool's definition and fetch
  [Page constraints](https://code.claude.com/docs/en/artifacts#page-constraints) live. **As of**:
  2026-10-11. **Recheck trigger**: that section adds or drops a page requirement or limit.

The decision table is the page's spine; it needs no runtime capabilities. Keep it utilitarian:
no hero banner, no italic accent words in headings, no "01 / 02 / 03" section labels (`#` is the
only numbering), no pill-shaped badges, and no style the reader names; when the reader dislikes a
choice, add it to that list and render again. In the terminal, give a one-line summary and the
link or path, not the table a second time.

## Boundaries

- **`education:explain`** lowers the altitude (plain words, analogy) and trades precision for it.
  This skill keeps altitude fixed.
- **`education:illustrate`** changes the medium (a diagram, an ELI5 visual). This skill stays in
  the artifact's own medium and words.
- **`discipline:wait-what`** is the reader's stop signal when the premise was never given: it adds
  missing context and re-pitches. Use this skill when the premise is all on the page and the
  decisions are buried.
- **`adhd:shape`** is a standing posture for every later response; this is a one-shot reshape of
  one artifact. When both are active, fidelity wins over shaping: the decision table is exempt
  from shape's five-item cap, and a shape-formatted target is judged by its actual decision density, not its provenance.
- **Not a summarizer** (it keeps every decision) and **not an input form** (it renders a view to
  read and answer from).

Routing: "I don't get it / explain simply / what does this mean" goes to `/education:explain`;
"ELI5 / draw me this / show me a diagram" goes to `/education:illustrate`; "make this clear /
clarify this / what am I deciding" is this skill. Hand off to the first two through the Skill tool
when the `education` plugin is installed; when it is not, say which one the ask wants and give a
faithful restructure.

## Gotchas

- **Clarifying is not summarizing.** Fewer decisions than the original held is an undeclared
  omission.
- **Verbatim means verbatim.** "Cleaning up" a recommendation into a tidy cell is the corruption
  the fidelity rules exist to stop.
- **A cramped cell is no license to simplify.** Quote the operative clause and point to the
  original.
