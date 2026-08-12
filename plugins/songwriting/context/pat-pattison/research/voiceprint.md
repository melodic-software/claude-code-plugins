# Writer Voiceprint — Register Calibration Before Line Generation

**What this file is.** Plugin-authored / writer-derived from the Sofía sessions
(2026-08-12). The procedure below — characterizing a writer's register from their
own accepted lines, and judging candidates against that characterization — is this
repo's, not Pat's. He publishes no such build, and no box below is sourced to him.
What is his is the object it aims at: the writer's own voice is the thing the whole
apparatus serves. *Songwriting Without Boundaries* (2011) opens on that, reproduced
here exactly as [brainstorm.md](brainstorm.md) prints it:

> "I decided to set four 14-day challenges to help you explore your writer's voice
> more fully"
> — Pat Pattison, *Songwriting Without Boundaries* (2011)

That sentence carries no Challenge or Day locator anywhere in this corpus — it is
the book's own framing, so it is cited as book-and-year only (per
[book-references.md](book-references.md)). It licenses the TARGET: the writer's
voice is what the work explores. It licenses nothing about the method. Pat does not
say how to characterize a register from accepted lines, and this file does not claim
he does.

The stance the file operates under is his, and it is quoted whole elsewhere in this
corpus:

> "There are no rules, only tools."
> — Pat Pattison, *Writing Better Lyrics* (2009), Chapter 18

A voiceprint is a tool. It describes; it does not legislate.

## The principle already exists here — the mechanism did not

[response-filter.md](response-filter.md) states the principle twice. §4's coaching
checklist carries **Coach toward writer's voice** — "the AI does NOT impose its
preference" — and the filter's posture table opens on the row `Voice | The writer's
voice | The AI's preferred voice`. [coaching-protocol.md](coaching-protocol.md) says
it again: "The author posture imposes the AI's voice. The coach posture surfaces the
writer's voice," closing on "the writer's voice arrives at the writer's song."

All of that is posture: *do not impose mine*. None of it says what the writer's voice
IS. With no answer to that, "don't impose mine" degrades into "guess" — and a guess
about register defaults to a fancy-plain dial, which is the failure recorded below.
This file is the mechanism underneath those statements. It is not a second way of
saying them, and it does not restate them.

## Not point of view, and not the section's register

[point-of-view.md](point-of-view.md) owns who is speaking in the song — persona,
addressee, pronoun grammar, camera distance. This file owns whose craft-register the
words are in: the writer's, across every song and every speaker they write. The two
are independent. A first-person confession and a third-person narrative can both sit
inside one writer's register, and a line can hold flawless POV consistency and still
be a line this writer would never say.

It is also not the section's register. Whether a line fits a talk-sung verse or a
lifted chorus is an inside-this-song question, and it belongs to
[line-edit-rubric.md](line-edit-rubric.md) pass 8. Whether it sounds like this
writer is an across-all-their-songs question, and it belongs to that file's pass 11.
Same word, two reference objects; keep them apart.

## The failure this file exists to prevent

*One writer's judgements, from the Sofía sessions (2026-08-12), recorded as evidence
that a voiceprint is needed — NOT as this plugin's target register.*

| Candidate | Writer's verdict | The lesson the AI drew | Why that lesson was wrong |
| --- | --- | --- | --- |
| `silt` | rejected — too literary | "go plainer" | plainness was never the target |
| `cruel`, `too` | rejected — too basic | "go fancier" | fanciness was never the target |
| `picturesque` | accepted | (unexplained) | a multisyllable that PAYS |
| `so` | never | (unexplained) | a plain word below the writer's floor |

The assistant read these as points on a single fancy-plain dial and oscillated along
it, correcting one rejection into the next. They are not on one dial. They are four
observations about ONE band, whose upper edge is set by whether a long word earns its
length and whose lower edge is set by whether a short word carries any weight.

These specific words are that writer's, on that night. Shipping them as the plugin's
target register would replace the AI's preferred voice with one writer's — the same
defect at one remove. What generalizes is the build, not the band.

## The build — three stages

This is a sibling of two builds already in the corpus, and deliberately shares their
shape: [worksheets.md](worksheets.md)'s three-stage worksheet (focus, list, look up)
and [object-writing.md](object-writing.md)'s "Cataloging the good stuff" post-write
harvest. Both take the writer's own material and persist it where later work reuses
it. So does this.

One rule carries over verbatim in force from object-writing.md's sense inventory:
**quote the writer's own words — a summary is not evidence.** "He likes concrete
nouns" is not a voiceprint entry. The quoted line is.

### Stage 1 — gather the accepted corpus

Only material the writer has ACCEPTED counts:

- lines locked into a song's canonical `LYRIC.md`
- lines the writer drafted themselves — worksheets, ideation, notebook material
- candidates the writer picked out of a menu the AI surfaced

Excluded: AI-generated lines not yet accepted; lines still under discussion; lines
accepted provisionally with a flag on them. Rejections are gathered too, but they are
Stage 3 and they are kept separate — they are a different kind of evidence.

Gather across every song the writer has worked, not just the one that is open. This is
a characterization of the writer, so a single song's corpus under-samples it.

### Stage 2 — characterize on four dimensions, with quoted evidence

The four dimensions are the writer's own naming, sharpened into questions that can be
answered from quoted lines:

| Dimension | The question it answers | Evidence form |
| --- | --- | --- |
| Vocabulary band | Which multisyllables PAY at this writer's standard, and which register as showing off? Which plain words fall below their floor? | accepted words and rejected words, both quoted |
| Syntax shapes | Which sentence forms appear in the accepted lines — fragment, inversion, subordinate clause, direct address, list, question? Which never appear? | the accepted lines quoted whole, not described |
| Image density | How many concrete sense-bound images does an accepted line carry, and per section? Where do the accepted lines allow abstraction? | the count taken on the quoted lines |
| Irony level | How much distance sits between what the speaker says and what the song means — sincere, wry, self-accusing, deadpan? | quoted line plus the line's actual meaning named |

Never write a dimension as a single adjective. "Conversational-literate" is a label,
and a label is not usable at emission time — the emitting skill cannot check a
candidate against it. Each dimension is a quoted-evidence entry with its edges named.

**This file's working floor:** a dimension is recorded only when at least two quoted
accepted lines from different sections back it. That is this file's own operating
minimum, chosen so no dimension rests on a single line — it is not a measured finding
and not a threshold anyone has validated. Below the floor, the dimension is recorded
as `UNKNOWN`, which is a usable answer. A guessed dimension is not.

### Stage 3 — record the rejections, with the writer's stated reason

Rejections are the discriminating evidence, and the failure table above is why:
`picturesque` accepted and `silt` rejected are only informative *together*.
Acceptances alone under-determine the band's edges.

For each rejection record, verbatim: the candidate, the writer's verdict, and the
writer's reason in the writer's own words. Where no reason was given, record
`no reason given`. Do not infer one — an inferred reason is exactly the oscillation
this file exists to stop.

## Where the artifact lives

Register is a property of the WRITER, not of one song, so the voiceprint is cross-song
and lands with the other reusable cross-song artifacts — the `songwriting/shared/` row
of [artifact-persistence.md](artifact-persistence.md):

```text
songwriting/shared/voiceprint.md
```

Not per-song. A per-song copy fragments one writer into as many registers as they have
songs, and each copy drifts from the others.

**Deliberate per-song departure.** When a song is written outside the writer's own
band on purpose — a character singing in a register that is not the writer's — the
departure is a recorded craft decision, so it goes where this corpus already records
craft decisions: the song's `decisions/` folder, alongside the title lock (see
[idea-to-title.md](idea-to-title.md)). The judgement then runs against
baseline-plus-named-departure. An unnamed departure is judged against the baseline and
fails, which is the correct outcome — an accidental departure is a defect.

A consuming project's own songwriting layout still wins over these paths, per
artifact-persistence.md.

## When it is built, and when it is rebuilt

Built BEFORE line generation. It is an input, not a review step, so the requirement
lives in the co-write skill's input gate rather than in a post-hoc checklist.

| Condition | Action |
| --- | --- |
| Writer rejects a candidate on register grounds | append the rejection and its stated reason to Stage 3; re-read the dimension it lands under |
| Writer accepts a line falling outside a recorded band | the band was drawn too narrow — widen it with the new line quoted; do not silently re-judge the old entries |
| No voiceprint exists and lines are wanted | build one from whatever accepted material exists; if there is none, SAY SO before emitting and name the gate as skipped |
| Writer says "that doesn't sound like me" | this file's own recheck trigger — the dimension that missed gets a quoted counterexample added |

## Honest limits

- A voiceprint describes; it does not legislate. The writer may write outside it at
  will, and that is the "tools, not rules" stance applied to their own register.
- It can only describe what has already been accepted. A writer's register moves, and
  a voiceprint built from one song over-fits that song's world.
- It does not replace the sing-check. The rubric filters; the writer's ear decides.
- It says nothing about whether a line is GOOD. It answers a narrower question — is
  this line in this writer's hand — which is the question that went unasked.

## Cross-references

- [response-filter.md](response-filter.md) — §4 states the posture this file gives a
  mechanism to; §2 loads this file before line-writing
- [coaching-protocol.md](coaching-protocol.md) — "the writer's voice arrives at the
  writer's song"; the same principle, no mechanism
- [point-of-view.md](point-of-view.md) — who speaks in the song; a different axis
- [line-edit-rubric.md](line-edit-rubric.md) — pass 11 is the per-candidate
  voiceprint match; pass 8 is the section's register, a different reference object
- [worksheets.md](worksheets.md) — the three-stage build this one is modelled on
- [object-writing.md](object-writing.md) — "Cataloging the good stuff"; the
  quote-don't-summarize evidence rule
- [artifact-persistence.md](artifact-persistence.md) — the `shared/` layout row
- [idea-to-title.md](idea-to-title.md) — `decisions/` as the home of a recorded
  craft decision
- [variations.md](variations.md) — labeled option menus judged against the voiceprint
- [audit-checklist.md](audit-checklist.md) — the pre-lock pass this feeds
- [book-references.md](book-references.md) — canonical book naming
