# Finding your unknowns

Graduated reference for the "Finding Your Unknowns" methodology: an artifact-first way of
working where, before and during an implementation, the agent produces small purpose-built
artifacts (explainers, brainstorms, interviews, mockups, plans) whose job is to surface
what you don't yet know while it is still cheap to find out. This doc owns the house
conventions the methodology graduated into this marketplace — the reply-affordance
convention, the export-button rule, and the opt-in deviation-log convention — plus the
pattern catalog and the boundaries (when HTML, when not; what deliberately stays
un-codified). Sibling docs: `PLUGIN-PHILOSOPHY.md` (governance),
`GLOSSARY.md` (vocabulary), `MIGRATION-PLAYBOOK.md` (delivery).

**Sources and permission basis.** The material derives from public posts by their named
author (see [Sources](#sources-and-citation-shape)). This doc quotes short attributed
verbatim excerpts under fair-quotation practice; no license is claimed and bulk
reproduction is avoided. Quotes are reproduced exactly as published — punctuation
included — and are never edited to fit this repo's style rules.

## Contents

- [Why this exists](#why-this-exists)
- [The unknowns taxonomy](#the-unknowns-taxonomy)
- [The five-pass pre-implementation workflow](#the-five-pass-pre-implementation-workflow)
- [Prompt-pattern catalog](#prompt-pattern-catalog)
- [Reply-affordance convention](#reply-affordance-convention)
- [Export-button rule](#export-button-rule)
- [Deviation-log convention (opt-in)](#deviation-log-convention-opt-in)
- [When HTML, and when not](#when-html-and-when-not)
- [The buy-in pattern](#the-buy-in-pattern)
- [Cautions from the source author](#cautions-from-the-source-author)
- [Heuristics awaiting evidence](#heuristics-awaiting-evidence)
- [Sources and citation shape](#sources-and-citation-shape)

## Why this exists

The methodology's economic argument, in the author's words: "Every explainer, brainstorm,
interview, prototype, and reference is a cheap way to find out what you didn't know before
it gets expensive to fix." (Field guide, [Sources](#sources-and-citation-shape) S1.) Each
pass below trades a few minutes of artifact review for a class of rework.

Caution on the framing: the author's stronger thesis — that output quality is now
bottlenecked by the human's ability to clarify the model's unknowns — is a single
practitioner's vendor-published claim and is treated here as direction, not doctrine.

## The unknowns taxonomy

Four quadrants, asked as "what are your unknowns?" before prompting:

- **Known knowns** — what the prompt already states.
- **Known unknowns** — questions you know to ask but haven't answered yet.
- **Unknown knowns** — things you assume without realizing you're assuming them; the
  agent can't see them until you disclose them.
- **Unknown unknowns** — the pothole you didn't know the road could have; only an
  artifact that shows you the terrain surfaces these.

The draft article's quadrant taglines ("questions you know to ask", "the pothole you
didn't know the road could have") appear only in the X draft (S4), which is the citable
source for draft-only content.

Findings that surface during an unknowns pass fall into four types (adopted as
`discovery:blindspot`'s output taxonomy): **Landmine** (a change that will break
something non-obvious), **History** (a constraint that exists for a reason the code no
longer shows), **Convention** (an unwritten team rule the work must follow), and
**Missing concept** (a domain idea the prompt never named).

Two diagnostics ride the taxonomy:

- Over-specifying and under-specifying are the same failure seen from two sides: both
  mean the split between what you locked and what you left open didn't match your actual
  unknowns.
- When a long-horizon task comes back wrong, check the unknowns and the plan's
  adaptability before blaming the model: the usual root cause is an unknown that was
  never surfaced, not a capability gap.

The lifecycle is a loop: what an artifact teaches you becomes the starting map for the
next round. The author frames this as matching the map to the territory (S1, "Matching
map and territory") — cited here as his metaphor, not adopted as house vocabulary (see
`GLOSSARY.md` rejected terms).

## The five-pass pre-implementation workflow

The corpus composes its pre-implementation demos into one ordered flow. This repo ships a
skill per pass; the composition itself is judgment, not a gate — run the passes whose
unknowns you actually have, in this order when you run several:

1. **Blindspot pass** — `/discovery:blindspot`: surface unknown unknowns in the task's
   blast radius.
2. **Brainstorm / prototype** — `/planning:brainstorm` for direction candidates;
   `/prototype:explore-directions` or `/prototype:pressure-test` when the unknown is
   visual or interactive.
3. **Interview** — `/planning:interview`: convert known unknowns into decisions on the
   record.
4. **Reference port** — `/discipline:point-dont-copy` when the work leans on an external
   reference whose semantics must survive the port.
5. **Plan** — `/planning:plan`: lock the approach with the unknowns now known.

Notes: the sequencing is chat-portable — every pass works as plain conversation, the
artifact form is optional. Running later passes in a fresh session with the earlier
artifacts carried forward matches this repo's existing session-flow doctrine (the corpus
independently corroborates it; see `session-flow` plugin).

## Prompt-pattern catalog

Patterns the corpus demonstrated that have no owning skill; each entry is one canonical
prompt-line to adapt. Patterns with an owning skill are listed in the
[workflow](#the-five-pass-pre-implementation-workflow) above — invoke the skill instead.

- **Disclose your starting point** (primer for any pass): "Before we start: my starting
  point is X, my current thinking is Y, my experience level with this area is Z."
- **Teach me my unknowns** (explainer with a vocabulary ladder): served by
  `/education:explain`; ask it to end with the terms you should now be using.
- **Design-system HTML file**: "Generate a single HTML page from this codebase's real
  tokens and components — one section per component family — so future design
  conversations can cite it as the reference."
- **PR explainer page**: "Make a single-file HTML explainer of this PR for reviewers:
  annotated diff hunks, a module map of what talks to what, and the three questions a
  reviewer should ask."
- **Report/audit HTML view**: for recurring documents (status, incident timeline),
  ask the producing skill for an HTML rendering as an opt-in output, never the default.
- **Quiz me before I merge**: served by `/education:quiz-me`; the merge gate itself stays
  with `/verification:confirm` (one mechanism per concern).

Reconciliation note: the corpus's "tweakable plan" ordering (high-tweak decisions first,
mechanical work collapsed) is already `planning:plan`'s documented presentation default;
it needed no new mode here.

## Reply-affordance convention

**The rule.** A generated review artifact ends with a structured reply affordance: a
machine-legible way for the human's reaction to become the next prompt — steal/skip
choices, a chip-filled reply template, a decisions table, a confirmation token. Default
with judgment: apply it to artifacts that exist to collect a decision; skip it for purely
informational output. In session contexts that render artifacts (the `artifact-design`
built-in skill's territory), the affordance rides the artifact; in plain chat it is a
reply template in the closing message.

**Who is bound.** Skills that generate decision-collecting artifacts cite this section
instead of restating it.

**Conformance** = the template blocks in `prototype:explore-directions` (structured
steal/graft capture and the assembled-reply template) and `prototype:pressure-test` (the
validation answer set). Fleet audits check those surfaces against this section.

## Export-button rule

**The rule.** An interactive HTML artifact always ends with an export affordance that
turns UI state back into something the user can paste or commit. In the author's words:
"The trick is always to end with an export: a "copy as JSON" or "copy as prompt" button
that turns whatever I did in the UI back into something I can paste into Claude Code."
(S2, "Custom editing interfaces".) The doctrine recurs three times independently in the
corpus; it is what keeps a throwaway editor inside the agent loop instead of becoming a
dead end.

**Who is bound.** Skills that emit interactive HTML artifacts cite this section.

**Conformance** = the same template blocks named in the
[reply-affordance convention](#reply-affordance-convention); the export button is the
HTML-artifact form of the reply affordance.

## Deviation-log convention (opt-in)

**The rule (opt-in).** An implementation session MAY keep an append-only `DEVIATIONS.md`
beside `PLAN.md` recording, per entry: what the plan said, what was found, what was chosen,
and whether a human needs to revisit. Entry types: plan-confirmed / discovery / deviation /
human-decision. Default conservative: when in doubt, log. The convention's contract text
is owned by `implementation:implement-dispatch` ("Divergence in non-interactive runs");
this section records the house posture: opt-in for interactive sessions, required only
where a skill's own contract says so.

**Recorded trigger.** The moment a second plugin reads `DEVIATIONS.md` (rather than
writing its own), the convention-registry rule fires and this section graduates to a
registry row per `PLUGIN-PHILOSOPHY.md` "Convention registry".

## When HTML, and when not

The corpus's examples index (S3) organizes twenty demos into nine categories —
exploration and planning, code review and understanding, design, prototyping,
illustrations and diagrams, decks, research and learning, reports, custom editing
interfaces — which double as the "when is HTML worth it" taxonomy: reach for a rendered
page when the information is spatial (diffs, call graphs), comparative (side-by-side
directions), interactive (motion you can only feel), or recurring (reports that benefit
from structure and color).

- **Density rubric**: HTML earns its cost through tables, CSS, SVG, interaction, and
  spatial layout. Markdown pushed past its density limit produces the degraded
  workarounds (ASCII diagrams, unicode color) that signal you wanted a page.
- **Reading ceiling**: the author's ~100-line markdown ceiling is a practitioner
  anecdote, recorded as such — not a measured threshold.
- **Sharing**: the publish-and-share argument is satisfied in this environment by the
  Artifact tool; nothing extra to build.
- **Scoping rule**: HTML artifacts are for ephemeral and published outputs. They never
  replace version-controlled instruction surfaces — HTML diffs are noisy (the author's
  own admission) and generation costs 2-4x the markdown equivalent, so plans, skills,
  and docs stay markdown in git.

## The buy-in pattern

For work that needs stakeholder agreement, the corpus's buy-in document has five
sections: demo first; the pitch; pre-answered objections; spec at a glance; risk and
rollback with named per-person asks and a deadline. The pre-answered-objections element
is the industry-standard core: Amazon's PR/FAQ carries an internal FAQ anticipating hard
leadership questions (Bezos 2017 shareholder letter; Bryar & Carr's Working Backwards),
and every surveyed RFC process — Rust RFCs, Oxide RFDs, Google design docs, Uber-style
RFCs — requires drawbacks/alternatives-considered sections. In all of those orgs the
persuasion artifact and the decision record are one document with a lifecycle, which is
why this repo extends existing planning artifacts rather than minting a parallel one.

**Objection-evidence checklist** (reusable in PR descriptions): for each objection you
expect, write the question, the factual answer, and the evidence citation — before
anyone asks. An objection you can't answer factually is an unknown; route it back
through the [workflow](#the-five-pass-pre-implementation-workflow).

## Cautions from the source author

The corpus carries its own warning against exactly the move a plugin marketplace is
tempted to make, and this repo treats it as binding (it is why the deltas that landed are
judgment-preserving contract lines and doc entries, never generator skills):

> I’m a little bit afraid that people will read this article and turn it into a /html
> skill or something. While there might be some value in that, I want to emphasize that
> you don’t need to do much to get Claude to do this. You can just ask it to “make a HTML
> file” or “make a HTML artifact”.
>
> The trick is knowing what you want the artifact to do and how you might use it. You may
> over time make a skill, but for now I’d suggest just prompting from scratch to get a
> hang of how to use it in different cases. (S2, "How to Get Started".)

Two companions to the warning:

- **Stay in the loop** is the evaluation lens for any artifact tooling: "All of the above
  is to say that I think the real reason I use HTML is that I feel much more in the loop
  with Claude." (S2, "Stay in the Loop".) Tooling that produces artifacts the user never
  forms judgment about fails this criterion even when it satisfies density, sharing, and
  ease.
- **Throwaway-editor doctrine**: a custom editing interface is "not a product, or a
  reusable tool" — it is built for the exact thing being worked on and discarded. The
  marketplace instinct to generalize a good throwaway into a shipped generator is the
  failure mode the warning names.

## Heuristics awaiting evidence

The following corpus heuristics are recorded here as doc lines and candidate eval cases,
not as standing skill instructions — per `PLUGIN-PHILOSOPHY.md` "Instruction economy",
they graduate into a skill body only on observed, repeated stumble evidence:

- **Observed-fact evidence bar** (brainstorming): each candidate option cites an observed,
  falsifiable fact about the codebase (a path plus a claim that could be wrong), not just
  a plausible path.
- **Already-built-but-disconnected scan**: before proposing new work, scan for dead
  imports, dark feature flags, and unread tables — the improvement may already exist,
  disconnected.
- **Non-obvious-behavior keying** (quizzes): author questions against behaviors a reader
  would skim past, not against what the diff makes obvious.
- **Collapse self-check** (plans): before collapsing a section as "mechanical, trust me",
  re-check that nothing in it is actually a judgment call — the corpus's failure case is
  a design decision hidden in a collapsed section.

## Sources and citation shape

Citations in this doc use: URL, ISO retrieval date, and `sha256:<hex64>` over the raw
snapshot bytes captured at retrieval. Content drift produces a new citation, never an
in-place hash edit.

- **S1** — "A field guide to Claude Fable 5: Finding your unknowns", Thariq Shihipar,
  Anthropic blog, published 2026-07-06.
  `https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns`
  (retrieved 2026-09-01,
  `sha256:ac8229699555d38eb0dfe6c80dd2e85353f30471a7abff0894d342b5107aad26`)
- **S2** — "Using Claude Code: The Unreasonable Effectiveness of HTML", X article by the
  same author. `https://x.com/trq212/status/2052809885763747935` (retrieved 2026-09-01,
  `sha256:07dc71b1a7fabe264b9a80ee003edbcd1e74013895372a8ffe13ee4bb178e63c`)
- **S3** — HTML-effectiveness examples index (20 demos, 9 categories, plus the 11-demo
  "Know your unknowns" sub-collection). `https://thariqs.github.io/html-effectiveness`
  (retrieved 2026-08-31,
  `sha256:7e6da98b6b447ec39efdc6deb34602204e4641dc59f4e311e3f05fb23d74f98e`)
- **S4** — X draft of the field guide (citable only for draft-only content: the quadrant
  taglines, the lifecycle-loop image, and three links the published blog dropped).
  `https://x.com/trq212/status/2073100352921215386` (retrieved 2026-09-01; snapshot
  pinned in the corpus work slice)
- Buy-in grounding: Bezos 2017 shareholder letter
  (`https://www.aboutamazon.com/news/company-news/2017-letter-to-shareholders`), the
  Working Backwards PR/FAQ
  (`https://workingbackwards.com/concepts/working-backwards-pr-faq-process/`), Rust RFCs
  (`https://raw.githubusercontent.com/rust-lang/rfcs/master/README.md`), Oxide RFD 1
  (`https://rfd.shared.oxide.computer/rfd/0001`), Google design docs
  (`https://www.industrialempathy.com/posts/design-docs-at-google/`), and Uber-style
  RFCs (`https://blog.pragmaticengineer.com/scaling-engineering-teams-via-writing-things-down-rfcs/`),
  all retrieved 2026-09-01.
