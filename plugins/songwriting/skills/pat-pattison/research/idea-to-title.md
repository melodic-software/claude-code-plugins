# Idea to Title — Developing a Seed Toward a Title

The writer has a seed: an image, a feeling, a phrase, a scene, a vibe —
but no title yet. This file routes seed → title.

Distinct from:

- `brainstorm.md` — no seed yet at all
- `fragment-development.md` — a partial line or section, not just a seed
- `hook.md` "Title generation" — title generation techniques (the seven types, Nashville method)

This file is the BRIDGE between seed and title generation. It walks the
writer from intuition to concrete title candidates.

## When to load

Trigger phrases: "I have an idea but no title", "I have an image I want to
write about", "this phrase is in my head", "I've been thinking about X but
no song yet", "I have a feeling I want to capture", "what title comes from
this".

## Workflow

### Step 1 — Distill the seed

Ask the writer to say the seed in one sentence. Out loud, if possible.
Then write it down. Then ask:

- **What** is the song about? (subject)
- **Who** says it? (speaker — first / second / third person)
- **To whom** is it said? (audience — listener / second-person you / no one specifically)
- **Why now**? (the precipitating moment that made this song want to exist)
- **What's the emotion underneath**? (not the emotion on the surface)

These five questions distill the seed into testable shape. The writer's
first-pass answers are often surface-level; gentle re-asking ("but what
underneath that?") usually surfaces the real seed.

### Step 2 — Object-write the seed's world

Set a 10-minute timer. Object-write the world the seed implies:

- the place it lives in
- the time of year / time of day
- the smells, textures, weather
- the person at the center
- the body language of the speaker

Per `object-writing.md`. Do NOT try to make it lyrical. The point is to
generate raw vocabulary, images, verbs, sensory anchors.

After the timer, mine for:

- the strongest image
- the most surprising verb
- the most specific noun
- a possible title fragment

### Step 3 — Generate title candidates

From the mined material AND the distilled seed sentence, generate 10-15
title candidates. Pat's seven title types (per `hook.md` "Title generation"):

1. **Statement** — declarative, ends with closure ("I Was Born in the Wrong Decade")
2. **Question** — interrogative ("Who Taught You How to Leave?")
3. **Command** — imperative ("Throw Away the Map")
4. **Phrase from the lyric** — a memorable line lifted from the verse
5. **Image-as-noun** — the central image becomes the title ("Brown Eyed Girl")
6. **Idiom recontextualized** — a familiar phrase used in new way
7. **Name** — a proper noun as title ("Eleanor Rigby")

Generate rapid-fire across all seven types. Don't edit. First-pass output.

### Step 4 — Stressed-vowel analysis on each candidate

For each candidate title, identify:

- **Stressed vowel(s)** — the title's load-bearing vowel sound(s)
- **Front-heavy vs back-heavy** — does the title's stress land early
  (lands on downbeat, feels anchored) or late (lands after downbeat, feels
  in motion)? Per `phrasing.md`
- **Stress count** — 2-stress, 3-stress, 4-stress, 5-stress
- **Syllable count** — exact (verify via `datamuse syllables` for long
  titles)

This analysis determines rhyme worksheet input, form fit, hook position,
and targeting opportunities.

### Step 5 — Run rhyme stability test on each candidate

For each surviving candidate, run a quick worksheet pass (per
`rhyme-worksheets.md` three-step algorithm):

- What perfect rhymes does the stressed vowel offer?
- What family rhymes? (apply Pat's phonetic family taxonomy)
- What can the song's world contribute? (proper nouns, settings, era words)
- Any obvious cliche partners to flag (moon/June, fire/desire)?

A title that can ONLY perfect-rhyme with cliche partners is a weaker title
than one with family-rhyme + world-vocabulary options. Pat's "writing a
lyric is like getting a gig" — more options = better choices.

### Step 6 — Test the title against form

Does this title repeat well, or live once?

- **Repeats well** → chorus or refrain form
- **Lives once** → AABA / verse-refrain
- **Conversational** → bridge target / through-written

Per `song-forms.md`. The title's emotional shape decides — not a default
form preference.

### Step 7 — Choose the title (or shelve)

Surface 2-3 surviving candidates with:

- stressed vowel
- front/back-heavy
- stress count
- 3-5 strongest rhyme candidates from internal generation
- proposed form fit

Let the writer choose. If none feels right, shelve and re-run Step 2 with
a different angle on the seed — or shelve the seed entirely for now.

A seed that doesn't yield a strong title isn't necessarily a bad seed.
Sometimes seeds need to season.

## Common failure modes

| Failure | Recovery |
|---|---|
| Writer jumps to drafting before titling | back up; the title is the structural seed (per `hook.md`) |
| Title is too abstract ("Hope", "Time") | route back through Step 2 — the abstraction needs a sense-bound collar |
| Title rhymes only with cliche partners | shift stressed vowel via near-rhyme reframe, OR shelve and re-seed |
| Multiple strong titles compete | pick the one whose stressed vowel + stress count best matches the emotional shape from Step 1 |
| Title feels strong but writer can't commit | object-write the song's world for another 10 min; the commitment usually follows material |

## Artifact pattern

If a slug exists, mined seed material + title candidates land in:

- `songwriting/songs/<slug>/ideation/seeds.md` — seed sentence + Step 1 answers
- `songwriting/songs/<slug>/ideation/title-candidates.md` — 10-15 candidates with stressed-vowel + form-fit analysis

After title lock:

- Move locked title to `songwriting/songs/<slug>/decisions/title-and-locks.md`
- Begin `LYRIC.md` and `BRIEF.md`

## Cross-references

- `brainstorm.md` — pre-seed phase (no idea yet)
- `object-writing.md` — Step 2 craft method
- `hook.md` "Title generation" — seven title types, Nashville method, targeting
- `phrasing.md` — front-heavy / back-heavy analysis
- `rhyme-generation.md` — internal rhyme search discipline
- `rhyme-worksheets.md` — three-stage worksheet
- `song-forms.md` — title repeats-well vs lives-once
- `fragment-development.md` — if seed is already a partial line, not just a seed
