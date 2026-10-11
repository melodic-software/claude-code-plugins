# Finding your unknowns

Graduated reference for the "Finding Your Unknowns" methodology: an artifact-first way of
working where, before and during an implementation, the agent produces small purpose-built
artifacts (explainers, brainstorms, interviews, mockups, plans) whose job is to surface
what you don't yet know while it is still cheap to find out. This doc owns the house
conventions the methodology graduated into this marketplace: the reply-affordance
convention, the export-button rule, and the opt-in deviation-log convention. It also owns the
pattern catalog and the boundaries (when HTML, when not; what deliberately stays
un-codified). Sibling docs: `plugin-philosophy.md` (governance),
`glossary.md` (vocabulary), `migration-playbook.md` (delivery).

**Sources.** The material derives from public posts by their named author (see
[Sources](#sources-and-citation-shape)). This doc stores no text from them, quoted or
paraphrased: it records what this repository adopted, in our words, and points at the source
section each decision rests on, which a reader opens to read the author's own words.

## Contents

- [Why this exists](#why-this-exists)
- [The unknowns taxonomy](#the-unknowns-taxonomy)
- [The pre-implementation workflow](#the-pre-implementation-workflow)
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

We adopted the methodology for its economics: each artifact is a cheap way to learn something
before it becomes expensive to fix, and each pass below trades a few minutes of artifact review
for a class of rework. For the author's own argument, see S1.

Caution on the framing: the author's stronger thesis about where output quality is now
bottlenecked (S1) is a single practitioner's vendor-published claim and is treated here as
direction, not doctrine.

## The unknowns taxonomy

We ask "what are your unknowns?" before prompting, across four quadrants:

- **Known knowns**: what the prompt already says.
- **Known unknowns**: open questions you are aware of.
- **Unknown knowns**: assumptions you hold without noticing; the agent cannot see them until
  you state them.
- **Unknown unknowns**: risks you have no reason yet to look for; only an artifact that shows
  the terrain brings these out.

The author's own quadrant taglines appear only in the X draft (S4), which is the citable source
for draft-only content.

Findings that surface during an unknowns pass fall into four types (adopted as
`discovery:blindspot`'s output taxonomy): **Landmine** (a change that will break
something non-obvious), **History** (a constraint that exists for a reason the code no
longer shows), **Convention** (an unwritten team rule the work must follow), and
**Missing concept** (a domain idea the prompt never named).

Two diagnostics ride the taxonomy:

- We treat over-specifying and under-specifying as one failure: in both, the split between
  what you locked and what you left open did not match your actual unknowns.
- When a task that ran for hours returns a wrong result, we check the unknowns and the plan's
  adaptability before blaming the model: the usual root cause is an unknown that was
  never surfaced, not a capability gap.

We run the method as a loop: what an artifact teaches becomes the starting map for the next
round. The author's own framing of this loop (S1, section "Matching map and territory") is his
metaphor, not adopted as house vocabulary (see `glossary.md` rejected terms).

## The pre-implementation workflow

The corpus composes its pre-implementation demos into one ordered flow, and this repo adds the
design, PRD, and decompose passes its own stage ladder (`/session-flow:workflow`) carries. This
repo ships a skill per pass; the composition itself is judgment, not a gate. New work whose
diff will not be quick to review and cheap to retry starts at the interview; the passes before
it run only when their unknown is present. Run the passes whose unknowns you actually have, in
this order when you run several:

1. **Blindspot pass**, `/discovery:blindspot`: surface unknown unknowns in the task's
   blast radius.
2. **Brainstorm / prototype**, `/planning:brainstorm` for direction candidates;
   `/prototype:explore-directions` or `/prototype:pressure-test` when the unknown is
   visual or interactive.
3. **PRD** (conditional), `/planning:prd`: only when the change is user-facing,
   business-driven, and needs alignment on the problem, the users, and the success metrics.
4. **Interview**, `/planning:interview`: convert known unknowns into decisions on the
   record. When an interview outgrows one session because the effort is too big to hold at
   once and still too foggy to phrase as decisions, escalate to **wayfind**,
   `/planning:wayfind`, which charts a decision map from the interview's ledger and hands
   back once the fog clears. Wayfind is never the first pass.
5. **Reference port**, `/discipline:point-dont-copy` when the work leans on an external
   reference whose semantics must survive the port.
6. **Design**, `/planning:design` then `/planning:design-handoff`: settle module layout,
   contracts, and variation verdicts when the work adds types, contracts, modules, or a
   topology or data-model change; the handoff writes them into PLAN.md's `## Design`, which is
   how they reach the implementer. Work with no design question records a one-line early exit.
7. **Plan**, `/planning:plan`: lock the approach with the unknowns now known.
8. **Decompose** (conditional), `/work-items:decompose`: only when the plan holds more than one
   independently shippable ticket; each ticket quotes its part of the design.

Notes: the sequencing is chat-portable. Every pass works as plain conversation, and the
artifact form is optional. Running later passes in a fresh session with the earlier
artifacts carried forward matches this repo's existing session-flow doctrine (the corpus
independently corroborates it; see `session-flow` plugin).

## Prompt-pattern catalog

Patterns the corpus demonstrated that have no owning skill; each entry is one house
prompt-line to adapt. Patterns with an owning skill are listed in the
[workflow](#the-pre-implementation-workflow) above. Invoke the skill instead.

- **Disclose your starting point** (primer for any pass): "Before we start: my starting
  point is X, my current thinking is Y, my experience level with this area is Z."
- **Teach me my unknowns** (explainer with a vocabulary ladder): served by
  `/education:explain`; ask it to end with the terms you should now be using.
- **Design-system HTML file**: "Generate a single HTML page from this codebase's real
  tokens and components, one section per component family, so future design
  conversations can cite it as the reference."
- **PR explainer page**: "Make a single-file HTML explainer of this PR for reviewers:
  annotated diff hunks, a module map of what talks to what, and the three questions a
  reviewer should ask."
- **Report/audit HTML view**: for recurring documents (status, incident timeline),
  ask the producing skill for an HTML rendering as an opt-in output, never the default.
- **Quiz me before I merge**: served by `/education:quiz-me`; the merge gate itself stays
  with `/verification:confirm` (one mechanism per concern).

Reconciliation note: the corpus's tweakable-plan ordering is already `planning:plan`'s
documented presentation default (high-tweak decisions first, mechanical work collapsed); it
needed no new mode here.

## Reply-affordance convention

**The rule.** A generated review artifact ends with a structured reply affordance: a
machine-legible way for the human's reaction to become the next prompt: steal/skip
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

**The rule.** Every interactive HTML artifact our skills emit ends with a control that
copies the state the user built out as text they can paste into the session or commit. For the author's version of this rule, see S2, section "Custom editing
interfaces". The doctrine recurs three times independently in the corpus; it is what keeps a
throwaway editor inside the agent loop instead of becoming a dead end.

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
registry row per `plugin-philosophy.md` "Convention registry".

## When HTML, and when not

The corpus's examples index (S3) groups its demos by category. Our test for when HTML is worth
it: reach for a rendered page when the information is spatial (diffs, call graphs),
comparative (side-by-side directions), interactive (motion you can only feel), or recurring
(reports that benefit from structure and color).

- **Density rubric**: HTML earns its cost through tables, CSS, SVG, interaction, and
  spatial layout. Markdown pushed past its density limit produces the degraded
  workarounds (ASCII diagrams, unicode color) that signal you wanted a page.
- **Reading ceiling**: the author's markdown length ceiling (S2) is a practitioner
  anecdote, recorded as such, not a measured threshold; we set none.
- **Sharing**: the publish-and-share need is met in this environment by the Artifact tool
  (see [Share session output as artifacts](https://code.claude.com/docs/en/artifacts));
  nothing extra to build.
- **Scoping rule**: HTML artifacts are for ephemeral and published outputs. They never
  replace version-controlled instruction surfaces. HTML diffs are noisy and generating HTML
  costs more than the markdown equivalent (for the author's own estimate, see S2), so plans,
  skills, and docs stay markdown in git.

## The buy-in pattern

For work that needs stakeholder agreement, we use a buy-in document whose core is pre-answered
objections (for the corpus's version, see S2): demo first; the pitch; pre-answered objections;
spec at a glance; risk and rollback with named per-person asks and a deadline. Pre-answered
objections are the industry-standard core: Amazon's PR/FAQ and every surveyed RFC process (Rust
RFCs, Oxide RFDs, Google design docs, Uber-style RFCs) carry the same element; see the buy-in
grounding in [Sources](#sources-and-citation-shape). In all of those orgs the persuasion
artifact and the decision record are one document with a lifecycle, which is why this repo
extends existing planning artifacts rather than minting a parallel one.

**Objection-evidence checklist** (reusable in PR descriptions): for each objection you
expect, write the question, the factual answer, and the evidence citation, before
anyone asks. An objection you can't answer factually is an unknown; route it back
through the [workflow](#the-pre-implementation-workflow).

## Cautions from the source author

The author warns against exactly the move a plugin marketplace is tempted to make: turning the
method into a dedicated generator skill instead of prompting for the artifact directly (S2,
section "How to Get Started"). This repo treats that caution as binding, which is why the deltas
that landed are judgment-preserving contract lines and doc entries, never generator skills.

Two companions to the warning:

- **Stay in the loop** is our evaluation lens for any artifact tooling (for the author's
  framing, see S2, section "Stay in the Loop"). Tooling that produces artifacts the user never
  forms judgment about fails this criterion even when it satisfies density, sharing, and
  ease.
- **Throwaway-editor doctrine**: we build a custom editing interface for the exact thing being
  worked on and discard it; it is never a product or a reusable tool. The marketplace instinct
  to generalize a good throwaway into a shipped generator is the failure mode the warning
  names.

## Heuristics awaiting evidence

The following corpus heuristics are recorded here as doc lines and candidate eval cases,
not as standing skill instructions. Per `plugin-philosophy.md` "Instruction economy",
they graduate into a skill body only on observed, repeated stumble evidence:

- **Observed-fact evidence bar** (brainstorming): each candidate option cites an observed,
  falsifiable fact about the codebase (a path plus a claim that could be wrong), not just
  a plausible path.
- **Already-built-but-disconnected scan**: before proposing new work, scan for dead
  imports, dark feature flags, and unread tables. The improvement may already exist,
  disconnected.
- **Non-obvious-behavior keying** (quizzes): author questions against behaviors a reader
  would skim past, not against what the diff makes obvious.
- **Collapse self-check** (plans): before collapsing a section as "mechanical, trust me",
  re-check that nothing in it is actually a judgment call. The corpus's failure case is
  a design decision hidden in a collapsed section.

## Sources and citation shape

Citations in this doc use: URL, ISO retrieval date, and `sha256:<hex64>` over the raw
snapshot bytes captured at retrieval. Content drift produces a new citation, never an
in-place hash edit. Recheck trigger: a re-retrieval whose hash differs from the recorded one.
No Claude docs page covers this methodology as of 2026-10-01, so the author's posts stay the
sources, each read at its link.

- **S1**: "A field guide to Claude Fable 5: Finding your unknowns", Thariq Shihipar,
  Anthropic blog, published 2026-07-06. No docs page covers it:
  (correlate with `https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns`)
  (retrieved 2026-09-01,
  `sha256:ac8229699555d38eb0dfe6c80dd2e85353f30471a7abff0894d342b5107aad26`)
- **S2**: "Using Claude Code: The Unreasonable Effectiveness of HTML", X article by the
  same author. `https://x.com/trq212/status/2052809885763747935` (retrieved 2026-09-01,
  `sha256:07dc71b1a7fabe264b9a80ee003edbcd1e74013895372a8ffe13ee4bb178e63c`)
- **S3**: HTML-effectiveness examples index (20 demos, 9 categories, plus the 11-demo
  "Know your unknowns" sub-collection). `https://thariqs.github.io/html-effectiveness`
  (retrieved 2026-08-31,
  `sha256:7e6da98b6b447ec39efdc6deb34602204e4641dc59f4e311e3f05fb23d74f98e`)
- **S4**: X draft of the field guide (citable only for draft-only content: the quadrant
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
