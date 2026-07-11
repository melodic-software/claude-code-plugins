---
name: pat-pattison
description: "Apply Pat Pattison lyric-craft methods (all 4 books + Berklee/Coursera/columns/workshops) to real songwriting work via an action router — writing, rewriting, rhyming, diagnosis, object writing, metaphor, meter/prosody, song form, POV, co-writes, daily practice. Use when: 'write a song', 'rhyme this', 'fix this lyric', 'object writing', 'diagnose my song', 'blank page', 'pat pattison', 'co-write session', 'demo review', or any lyric-craft request — for Suno prompt formatting use /suno instead (pair: write the lyric here, format it there)."
argument-hint: "[action] [args] (e.g., /pat-pattison rhyme, /pat-pattison diagnose, /pat-pattison workflow) — full action list in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

**Before emitting any rhyme suggestion, lyric line, rewrite, critique,
coaching step, title, form recommendation, image, or pre-lock judgement —
run the applicable section of [response-filter](research/response-filter.md).**

The filter is the gate. The filter activates the discipline. Without it,
generic LLM defaults — perfect rhymes, predictable end-lines, abstract
telling, cliche imagery, single-winner picks, list-and-leave coaching —
ship instead of Pat's craft.

The filter is fast: scan the applicable § section, NAME each box's pass /
fail / skip-with-reason out loud (or silently in reasoning), correct
before emission. Skips are valid; silent skips are not.

[response-filter](research/response-filter.md) holds the output-type → §1-§8
section map (rhymes, line / rewrite, critique, coaching, title / hook, form,
image, pre-lock) plus every checkbox and worked fail signature. See also
[coaching-protocol](research/coaching-protocol.md) for §4 dialog mechanics
and [book-references](research/book-references.md) for canonical source
citation form.

## Purpose

Apply Pat Pattison's lyric-craft methods to real songwriting work. Concept-
organized skill, not a chapter summary. Load only the context files needed
for the user's action, then coach or rewrite from those craft principles —
filtered through `response-filter.md` per the table above.

Use this for lyric writing, rewriting, diagnosis, rhyme finding, meter,
prosody, song form, hook, object writing, metaphor, cliche repair, point
of view, repetition, daily practice, co-writing, fragment development,
demo review, pre-lock audits, variation generation, and high-volume
single-line / single-section brainstorm. Use the workflow router when the
user describes a situation rather than a craft term.

## Stance — Tools, Not Rules

> "Tools, not rules." — Pat Pattison (recurring column / seminar framing;
> also the name of his *American Songwriter* magazine column)

Every principle below is a tool to deploy for effect, not a rule that
binds the writer. The skill names defaults so the writer can choose
deliberately, not so the writer can be policed. Checklists in this skill
are option lists, never gates — the writer can refuse any item, but
should know they're refusing.

Tools-not-rules applies to the AI itself: the response filter is a tool
the AI uses on its own work. Skips are valid when NAMED with a reason.

## Action Router

Arguments: `$ARGUMENTS`

`/pat-pattison <action> [args]`. Parse `$ARGUMENTS`: first token = action,
remainder = args. With no action, route on conversation context. Full action tables + Quick Decision Guide + Sample Invocations
live in [action-routing](research/action-routing.md). Load that file when
routing is ambiguous or when surfacing the menu to the user.

### Summary — situation-first actions

| Action | Trigger summary |
| --- | --- |
| `workflow` | situation router — picks one of 11 scenarios |
| `brainstorm` | blank page / no idea yet |
| `idea` | seed (image/feeling/phrase) but no title |
| `fragment` | partial line / section / hook that won't grow |
| `demo` | lyric in progress at any completion stage |
| `diagnose` | full draft review |
| `stability` | section-level stable/unstable scan |
| `align-melody` | lyric-melody mismatch / greedy spots |
| `title` | title generation from idea |
| `title-game` | Pat's chained title-cascade (solo or co-write) |
| `co-write-protocol` | No-Free-Zone session opener |
| `audit` | pre-lock per-line / per-section checklist |
| `variations` | labeled alternates across six axes |
| `line-brainstorm` | ONE line — 30-50 across 5 columns (end-line / content / internal / image / whole-line) |
| `section-brainstorm` | ONE section — line-brainstorm per line + stability profile + hot-spot map + box-model check |
| `coach` | step-by-step guided dialog through any task |
| `filter` | apply response filter to a paste-in (rhyme list / line / critique) — diagnostic mode |

### Summary — craft-term actions

| Action | Trigger summary |
| --- | --- |
| `rhyme` / `rhyme-generation` | rhyme search; internal Pat-framed generation primary |
| `datamuse` | live API supplement for vocabulary / syllables / semantic field |
| `worksheet` / `rhyme-dictionary` | rhyme worksheet from title / theme / section |
| `meter` | scansion, paradigms, Pentad, Goldilocks, In Memoriam, pitch-stress |
| `prosody` | motion-emotion, greedy spots, tone-of-voice, three phrasing types |
| `form` / `song-forms` | section identification, candy bar, form-fit, *Essential Guide to Lyric Form and Structure* (1991) worked examples |
| `hook` | title placement, hot spots (section + phrase level), targeting |
| `object-writing` | sense-bound writing, Rusty's collar, Kami-kazi |
| `metaphor` / `metaphor-recipe` | 3 types, 8 recipes, transitive/intransitive, grounded, tone center |
| `cliche` | cliche taxonomy + redemption |
| `repetition` / `box-model` | repaintable chorus, You-I-We, Past-Pres-Future, hidden Q/cmd |
| `verse` / `bridge` | verse development, travelogue, bridge writing |
| `pov` | camera distances, pronoun consistency |
| `daily` / `exercise` | daily practice curriculum, numbered drills across all 4 books |
| `co-write` | co-writing protocol + Title Game |
| `process` / `rewrite` | full workflow / lyric critique |
| `beyond-books` | Coursera / Berklee Online / Berklee Take Note essays / columns / podcasts / workshops |

Full tables with trigger phrases + file loads live in
[action-routing](research/action-routing.md). Quick Decision Guide with 35+
user-question → route mappings lives there too.

## Action Handlers

- **Pre-flight ALWAYS:** invoke `response-filter.md` section before output.
- If the user describes a situation (not a craft term), route via
  `workflow` to [workflows](research/workflows.md) (1-11 scenarios).
- If the user gives a draft, run `demo` (any stage) or `diagnose` (near-
  complete) first. Name the dominant problem; offer one focused revision.
  Do not list every issue.
- If the user asks for a prompt, generate one usable exercise immediately.
  Do not assign the full curriculum unless asked.
- **If the user asks for rhymes:** load
  [rhyme-generation](research/rhyme-generation.md) FIRST. Apply Pat's
  discipline (identity check, stability tier walk, vowel triangle, song's
  world vocabulary, cliche scan) to internal vocabulary. Surface 8-15
  labeled candidates across tiers. Use [ai-tools](research/ai-tools.md)
  (Datamuse) only as supplement for vocabulary breadth, syllable
  verification, or semantic-field mining. Internal generation is PRIMARY;
  Datamuse supplements.
- **If the user asks for a LOT of options for ONE line or ONE section:**
  load [line-brainstorm](research/line-brainstorm.md) — five-column dump
  (end-line word swaps × content word swaps × internal rhyme partners ×
  image alternates × whole-line variants), filtered through
  `response-filter.md` §1 + §2 + §7.
- **If the user wants step-by-step guidance:** load
  [coaching-protocol](research/coaching-protocol.md). Ask ONE question,
  wait for the answer, apply Pat's tool, surface next choice point.
  Never list-and-leave; never monologue 14 steps.
- If the user asks for a plan, give the smallest sequence that solves the
  craft problem.
- If the user pastes incomplete material (a fragment, an idea, half a
  song), route to `fragment`, `idea`, or `demo` — NOT to `diagnose`.
- If multiple actions apply, pick the dominant craft problem and mention
  the secondary file only when it affects the answer.

## Songwriter Workflow Scenarios

11 scenarios via `workflow` (chains in [workflows](research/workflows.md)):

1. Brand new song from scratch
2. Existing song revision
3. Writing from a title
4. Writing to an existing melody
5. Co-write session start
6. Diagnose without rewrite
7. Build a daily practice habit
8. Pure brainstorm (no seed yet)
9. Idea / seed but no title
10. Fragment in hand
11. Demo at any stage

Each scenario lists which context files to load in what order. Every
scenario routes through [response-filter](research/response-filter.md) at
emission time.

## What This Skill Does Not Do

Pat's books cover lyric craft and structure. This skill does not handle:

- melody writing,
- chord progressions or harmonic analysis,
- arrangement, production, recording, mixing, or mastering,
- vocal performance coaching,
- music business, licensing, royalties, or contracts,
- Suno prompt formatting.

For Suno formatting, use `/suno lyrics`. The skills are independent:
`/pat-pattison` develops lyric craft; `/suno` formats the finished lyric
for Suno syntax. Do not import files from `/suno` or assume `/suno` has
loaded this skill.

## Output Style

Be concrete and craft-first. Prefer:

- short diagnosis before rewrite,
- labeled rhyme/stability risks,
- timed prompts with exact instructions,
- before/after examples when rewriting,
- cross-file routing only when it helps the user act.

Do not quote long passages from Pat's books. The context files contain
short, verified anchor quotes only; answer mostly in your own words.

When citing a source, use the canonical naming form in
[book-references](research/book-references.md): short title + year +
"Chapter N" (never "Book X" or "Ch N").

### Internal rhyme-generation discipline

Rhyme requests run the full internal discipline in
[rhyme-generation](research/rhyme-generation.md) through `response-filter.md`
§1 — internal generation primary (8-15 labeled candidates, never a single
winner); Datamuse (`scripts/datamuse.sh`, see [ai-tools](research/ai-tools.md))
supplements only for high-volume, syllable, or semantic-field breadth. The
"user asks for rhymes" handler above is the operational routing.

### Coaching posture — depth-first dialog

Guidance / "help me think through" / "what next" requests route through
[coaching-protocol](research/coaching-protocol.md): ask ONE question, wait,
restate decided-vs-open, apply Pat's tool, surface the next ≥3-option choice
point — never a pre-decided 14-step plan or list-and-leave dump.

### Checklists are tools, not gates

When running audit-checklist or pre-lock walkthroughs (per
[audit-checklist](research/audit-checklist.md)), present each box as a
deliberate choice point — not pass/fail. A writer may skip any box. A
skip names a reason; silent skips are not OK. Same posture applies to
the response filter itself.

## Artifact Persistence

Named per-song work (title given, multi-session) persists under the consuming
project's root. Default layout (relative to `${CLAUDE_PROJECT_DIR}`):

| Artifact kind | Default path |
|---|---|
| Per-song work | `songwriting/songs/<slug>/` |
| Pre-title work (brainstorm / idea / fragment) | the song's `ideation/` subfolder |
| Line / section brainstorm output | the song's `variations/` or `worksheets/` |
| Daily practice | `songwriting/practice/<YYYY>/<YYYY-MM-DD>.md` |
| Broader research not tied to one song | `songwriting/research/<topic>.md` |
| Reusable rhyme inventories / audit checklists | `songwriting/shared/` |

Per-song folder anatomy: `PLAN.md` / `BRIEF.md` / `LYRIC.md` / `ideation/` /
`variations/` / `worksheets/` / `research/` / `decisions/` / `journal/`.
Slug = song title kebab-cased, lowercase, no version qualifiers (`v1`, `final`,
dates) — one canonical song per slug; rewrites overwrite within the slug.

**Consumer override:** if the consuming project's `CLAUDE.md` or rules define
their own songwriting artifact layout, that layout wins — the table above is
the default, not a mandate.

**Template override:** when loading any `templates/<name>.md`, check
`${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` first — a
project-level override wins over the skill default (first match), so writers
layer custom versions without forking the plugin.

When the user asks for variations / multiple options, write each option to a
`variations/<line>.md` file as a labeled menu — don't dump options inline.
When introducing a rhyme pair, run the identity-vs-rhyme check (pre-vowel
consonants MUST differ) via the song's `worksheets/audit-checklist.md` Step 3
before declaring "this rhymes" — identity is NOT rhyme (per
[rhyme-fundamentals](research/rhyme-fundamentals.md)).
