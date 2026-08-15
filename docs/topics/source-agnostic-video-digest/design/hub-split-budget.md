# Hub split budget

Measured arithmetic for reducing `plugins/knowledge/skills/youtube-digest/SKILL.md` from 410 lines
while adding an X source section.

**One partition only.** The handoff carried a different partition of the same 410 lines (skill
protocol 70 / output contract 50 / queue+claims 61 / execution model 21 / …). That partition is
superseded here and must not be mixed with this one — two partitions in one design produce
contradictory move lists.

## Measured sections (`## ` heading offsets)

| Section | Lines |
|---|---|
| Watch action | 148 |
| Queue action | 61 |
| Output contract | 50 |
| Artifact landing (work root) | 20 |
| yt-dlp & throttle overrides | 20 |
| Action router | 16 |
| Transcript action | 16 |
| Resume action | 14 |
| Pre-computed context | 13 |
| Video slug derivation | 12 |
| Prerequisites | 12 |
| Eval fixtures | 12 |
| Source discipline | 4 |
| Gotchas | 4 |
| **Sum** | **402** (remaining 8 = frontmatter, headings, blanks) |

## The finding that changes the plan

**Watch action alone is 148 lines; everything else combined is 254.** Moving *every other section*
out still leaves the hub at 148 + router 16 + pre-computed context 13 ≈ **177** — under 200, but
with zero headroom for an X source section, and a "hub" that is nothing but the watch action.

**So the split only works if the Watch action itself is split.** The handoff's plan — move the
generic protocol and output contract out and leave the rest — does not reach the target.

## Concrete moves

Existing spoke sizes are measured, so the receiving files are known to have room.

| Move | Destination | Δ |
|---|---|---|
| Watch action 148 → keep a ~30-line phase spine (ordered phases + resume/claim contract) | `context/watch-pipeline.md` (currently 37) | −118 |
| Queue action 61 → keep ~8 lines of router + pointer | `context/watch-queue.md` (currently 144) | −53 |
| Output contract 50 → keep ~6 | new spoke | −44 |
| Artifact landing 20 | same spoke as output contract | −16 |
| yt-dlp & throttle overrides 20 | `sources/youtube.md` | −20 |
| Video slug derivation 12 → ~6 stays (mostly agnostic once the adapter owns the key) | `sources/*` + shared spoke | −6 |
| Eval fixtures 12 → ~2 | spoke | −10 |
| **Total removed** | | **−267** |

402 − 267 ≈ **135**, plus new pointer lines (~10–15) plus the widened description and preamble ≈
**150–175**. That clears 200 with room for the X source section.

## Two cautions

## RESOLVED — the gate was measuring the wrong thing in both directions

Research returned 2026-08-14, quotes re-derived from raw markdown rather than a summarizing fetcher.

**No authoritative source states a 200-line target.** Absent from `platform.claude.com` skill-authoring
best-practices (1,185 lines), `code.claude.com/docs/en/skills` (1,059 lines), the Agent Skills
specification (274 lines), agentskills.io skill-creation best-practices, and Anthropic's own
`anthropics/skills` → `skill-creator/SKILL.md`. Locally it is an **uncited tunable** whose two
neighbours are both anchored upstream:

```
DESC_CHAR_CAP=1536   ← matches Claude Code docs exactly
LINE_HARD_CAP=500    ← matches the spec and Anthropic docs exactly
LINE_SOFT_CAP=200    ← matches nothing upstream
```

Externally it is a real, widely-circulated **community convention that misattributes itself to
Anthropic** — falsified directly against the primary sources.

### There IS a token constraint — but attribute it precisely

**Agent Skills specification**, "Progressive disclosure" (verified verbatim from the raw source,
lines 248 and 251): *"**Instructions** (\< 5000 tokens recommended): The full `SKILL.md` body is
loaded when the skill is activated"*, alongside *"Keep your main `SKILL.md` under 500 lines."*

**Single-pool caveat, disclosed by the researcher against its own headline and independently
confirmed here.** The `< 5,000 tokens` recommendation rests on **one publishing pool**
(agentskills.io). **Anthropic's own documentation states no token figure at all** — verified: its
section *literally titled* "Token budgets" (`best-practices.md:1132`) reads only *"Keep SKILL.md body
under 500 lines for optimal performance"*, and the file has zero occurrences of 5000. Both spec
citations share a pool, so they are **one corroborator, not two**.

Three claims, three different confidence levels — do not collapse them:

| Claim | Support |
|---|---|
| "The Agent Skills spec states `< 5000 tokens` recommended" | **HIGH** — verified verbatim |
| "Claude Code **enforces** a 5,000-token truncation on the rendered `SKILL.md`" | **HIGH** — a directly observed runtime behaviour |
| "Anthropic **recommends** a 5,000-token body" | **NOT SUPPORTED** — do not assert it |

**Corrected framing — the earlier version of this table called the compaction cap "independent
corroboration". That was laundering and it is retracted.** Two figures describing the same object
with the same value, published by parties in a governance relationship (the spec is the standard
Claude Code implements), are far more plausibly **causally linked** than independently derived:
setting a runtime truncation at exactly the spec's recommended body size has an obvious design
intent. Independence would require the cap to be 5,000 even had the spec said otherwise.

**But the finding is stronger without the fake second witness.** The compaction cap is not
corroboration of a recommendation — it is an **independent reason for the same action**, standing
alone even if the spec said nothing about tokens: a rendered `SKILL.md` over 5,000 tokens is
**silently truncated** after any compaction. Two independent routes to the same action beats one
recommendation plus a borrowed witness.

**Scope resolved, and it is what the whole hub/spoke case rests on:** the cap applies to the
**rendered `SKILL.md` message only**, not body-plus-spokes. `skills.md`, "Skill content lifecycle":
*"the rendered `SKILL.md` content enters the conversation as a single message."* Spoke reads are
ordinary Read results. Had the 5,000 spanned spokes too, the split criterion would collapse entirely.

**Both omitted halves of the compaction paragraph, reported in full:**

- Strengthens: *"Claude Code fills this budget starting from the most recently invoked skill, so
  **older skills can be dropped entirely** after compaction if you have invoked many in one
  session."* The 25,000 combined budget is a live eviction risk in a multi-skill session.
- Weakens: *"If the skill is large or you invoked several others after it, **re-invoke it after
  compaction** to restore the full content."* There **is** a documented user-side remedy. Urgency is
  lower than "silently truncated" alone implies.

### Local measurement — this repo already measured the fleet, and this skill is a top-three offender

`docs/topics/context-engineering-claude-5/design/article-sections.md` records a measurement at
`abe914eace` over **182 skills**:

- **0 of 182 exceed the 500-line cap** (max 497) — *"reads as full conformance"*
- **14 of 182 exceed the truncation cap** whole-file; 12 body-only
- At-cap skills run **5,058–10,509 est. tokens**
- **The top three — `planning/plan`, `source-control/babysit-prs`, and `knowledge/youtube-digest` —
  consume 29,706 est. tokens together, so a chain of three already exceeds the 25,000 budget**

This is in-repo prior measurement, not research, and it independently reproduces the central finding:
**the 500-line gate reports full fleet conformance while 14 skills silently violate the truncation
cap.** It also names *this skill* as one of the three heaviest in a 182-skill fleet.

The 500-line cap is a coarse **proxy** for a loaded-body budget; the token figure is the property of
the loaded body.

Measured: **410 lines, 38,436 characters, 4,579 words** — ~94 chars/line, unusually dense.

**Token estimate, computed under THIS REPO'S OWN established method** rather than an invented one.
The 182-skill fleet measurement used `chars/4.0` and treats the divisor and the
whole-file-vs-body-only choice as load-bearing (*"each move the answer more than the corpus change
did"*), so both are reported here and both are directly comparable to that measurement:

| Basis | Chars | Est. tokens (chars/4.0) | vs 5,000 cap |
|---|---|---|---|
| Whole file | 38,436 | **9,609** | **1.92×** |
| Body only (after frontmatter) | 37,620 | **9,405** | **1.88×** |

**Self-consistency check:** the fleet measurement records at-cap skills running 5,058–10,509 est.
tokens with `knowledge/youtube-digest` among the top three. 9,609 sits near the top of that range —
consistent, and it identifies which of the three this is.

An earlier version of this file gave a wide **6,100–9,600** range by averaging two different methods
(`chars/4` and `words×1.33`). That spread was an artifact of mixing divisors, not real uncertainty
about the file. Using the repo's own divisor removes it: the answer is **~1.9×**, not "somewhere
between 1.2× and 2×".

**Residual gap, honestly flagged:** this is still an *estimate*. A real tokenizer count needs the
count-tokens API, and no `ANTHROPIC_API_KEY` is present in this environment — so a precise figure is
a parked ask, not a blocked one. The ~1.9× verdict is robust enough to act on; a precise count would
only refine *how much* must move, which is plan-stage sizing rather than a design decision.

Two documented mechanics corroborate the token framing:

- *"once Claude loads it, every token competes with conversation history and other context."*
- Compaction: Claude Code *"re-attaches the most recent invocation of each skill after the summary,
  keeping the first 5,000 tokens of each."* A body over 5,000 tokens is **silently truncated after
  any compaction** — positionally, with no signal anything is missing.

**Caveat that will not be papered over:** *"under 500 lines for optimal performance"* is stated three
times and **"optimal performance" is never defined** in any official source. No attention or
recall rationale is given, so no attention-based benefit of a shorter body can be claimed from the
documentation.

### What this does to the split

- The **200 WARN cannot justify** splitting the 148-line Watch action. The completion criterion
  resting on it is unbacked and should be retired.
- The **500 PASS is also not the right instrument** — it passes a file that violates the spec.
- **The split is still required**, on a different and defensible warrant: the body is ~2× the
  `< 5,000 tokens` recommendation.

**And the warrant changes what moves.** Not "whatever gets the line count under 200", but *whatever
gets the body under 5,000 tokens, chosen along the conditional/source axis* — per-source detail that
is mutually exclusive per invocation, one level deep, with explicit "read this file **when** X"
routing. **Anything the hub would tell Claude to read every time stays in the hub.**

Documented split criterion, stated by mutual exclusivity rather than by any number: *"If certain
contexts are mutually exclusive or rarely used together, keeping the paths separate will reduce the
token usage."* And the documented anti-pattern to correct back: *"If Claude repeatedly reads the same
file, consider whether that content should be in the main SKILL.md instead."*

**Gate follow-ups (flagged, not applied — they belong to `skill-quality`, not this refactor):**
re-anchor or remove `LINE_SOFT_CAP=200`; add a token-based check for `< 5,000 tokens`, the constraint
the current 500-line PASS fails to catch.

**Citation note:** the caps live at `:175-177` in the repo copy (`plugins/skill-quality/scripts/check-skill.sh`)
and at `:122-124` in the installed cache (`skill-quality/0.5.0`). Same values; the repo copy has
diverged from the published version. Cite the copy you mean.

---

## Superseded framing (retained)

**The 200 figure is a WARN, not a FAIL — and its provenance is UNRESOLVED, under research.**
`check-skill.sh:124` sets `LINE_SOFT_CAP=200`; the hard cap is `LINE_HARD_CAP=500` at `:123`. The
handoff's completion criterion treats 200 as a gate ("reports no line WARN"), and that is the sole
justification for splitting a 148-line section that may read better in one place.

The user declined the recommendation to simply treat 200 as real, and directed that it be settled by
consensus research from official, authoritative sources rather than by judgment. **The whole move
table above is therefore provisional.** Outcomes:

- If an authoritative source states a ~200-line target → the table stands as required work.
- If 200 is local convention only → the hard constraint is 500, the hub at 410 already passes, and
  the split becomes an *optional* readability improvement to be argued on its own merits rather than
  a gate obligation. The Watch-action split in particular would need re-justifying.
- If the real official constraint is shaped differently (tokens, listing-budget percentage, or a
  progressive-disclosure split-trigger rather than a body-length count) → the line count is a local
  proxy and the target should be restated in the official terms.

Do not act on this table until that returns.

**Splitting only pays if spokes load conditionally.** Line count is the linter's measure, not the
context measure. If the hub instructs the agent to read every spoke, the tokens are identical and
the refactor bought nothing but a passing check. See thread T7.
