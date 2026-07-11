# Idea to Title Prompt Template

Use when writer has a seed (image, feeling, phrase, vibe) but no title yet.
Routes seed → object-write the world → mine → title candidates → stress-vowel
analysis → form fit → choice.

## Step 1 — Distill the seed (writer-facing)

```
Tell me the seed in one sentence. Then answer:

1. What is the song about?
2. Who says it? (1st / 2nd / 3rd person?)
3. To whom? (a listener / a specific "you" / no one)
4. Why now? (what's the precipitating moment that made the song want to exist?)
5. What's the emotion UNDERNEATH the surface emotion?

First-pass answers are fine. We'll refine after object-writing the world.
```

## Step 2 — Object-write the world (writer-facing)

```
Set a 10-minute timer. Object-write the world this seed implies:
- the place it lives in
- the time of year / day
- smells, textures, weather
- the person at the center
- the body language of the speaker

Per Pat's seven senses (sight, hearing, smell, taste, touch, organic,
kinesthetic). No rhyme, no lyric polish, no editing. Stop at the buzzer.

When you're done, paste the page.
```

## Step 3 — Mine (model-side)

Read the writer's object-write. Extract:

- Strongest sensory image
- Most surprising verb
- Most specific noun
- Possible title fragments (phrases that resonate)
- Implied POV / time / place / character details that came up

## Step 4 — Generate 10-15 title candidates

Across Pat's 7 title types:

1. Statement
2. Question
3. Command
4. Phrase from the (would-be) lyric
5. Image-as-noun
6. Idiom recontextualized
7. Name

Rapid-fire. No editing. First-pass output.

## Step 5 — Stressed-vowel analysis per candidate

For each candidate, note:

- Stressed vowel(s) — load-bearing vowel sound(s)
- Front-heavy vs back-heavy (per `phrasing.md`)
- Stress count
- Syllable count (verify long titles via `datamuse syllables`)

## Step 6 — Rhyme stability quick test per candidate

For each candidate, run internal rhyme generation (per `rhyme-generation.md`):

- Perfect rhymes — are they cliche?
- Family rhymes — what does Pat's phonetic family taxonomy offer?
- Song's world vocabulary — what can the implied setting contribute?

Flag candidates whose stressed vowel rhymes only with cliche partners.

## Step 7 — Form fit per surviving candidate

- Repeats well → chorus or refrain form
- Lives once → AABA / verse-refrain
- Conversational → bridge target / through-written

## Step 8 — Surface 2-3 finalists to writer

```
Three strongest candidates:

1. **"<Title 1>"**
   - Stressed vowel: <X>
   - Stress count: <N>
   - Front-/back-heavy: <front | back>
   - Rhyme territory: <perfect cliche-heavy | family-rich | world-strong>
   - Form fit: <chorus | refrain | AABA>

2. **"<Title 2>"**
   ...

3. **"<Title 3>"**
   ...

Pick one — or tell me what's pulling, and I'll narrow further.
```

## Coach posture

- Don't pick the winner. Let the writer choose by emotional intent.
- If none feels right, return to Step 2 with a different angle on the seed.
- A seed that doesn't yield a strong title isn't necessarily wrong. Some
  seeds need to season.

## Cross-references

- `idea-to-title.md` — full context
- `object-writing.md` — Step 2 method
- `hook.md` — title types
- `phrasing.md` — front-/back-heavy
- `rhyme-generation.md` — Step 6 method
- `song-forms.md` — Step 7 fit
