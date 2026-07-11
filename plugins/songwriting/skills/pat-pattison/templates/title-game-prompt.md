# Title Game Prompt Template

Use for the Pat Pattison Title Game — a chained title-generation exercise
where each new title is generated from the prior title's stressed vowel
plus a structural / emotional shift.

Use solo as a warmup or generation drill, or co-write as session opener
(per Songwriter Trysts ep. 40 protocol).

## Mode 1 — Solo cascade

### Step 1 — Set constraints (writer-facing)

```
Declare before we start:

- **Vowel rule:**
  [a] same stressed vowel every link
  [b] adjacent vowel on Pat's triangle each link
  [c] diphthong-component sharing OK

- **Stress count:**
  [a] free
  [b] fixed (e.g. all 3-stress)

- **POV:**
  [a] free
  [b] all 1st person
  [c] all direct address

- **Genre tint:**
  [a] free
  [b] specific ("all country" / "indie folk" / "pop")

- **Duration:**
  5 min / 10 min / 15 min

Tighter constraints = tighter clusters but less surprise.
Looser = more variety but harder to mine.

Pick.
```

### Step 2 — Seed (writer-facing)

```
Seed title — any title, doesn't have to be good. First one that arrives.

Or I can seed if you say "you pick" + a feeling / setting / theme.
```

### Step 3 — Run the cascade (model-side, surface chain to writer)

Generate titles one at a time, each derived from the prior:

```
Seed: "<title>"
  → vowel: <X>, stress: <N>

Title 2: <new title> (constraint: <which rule>)
  → vowel: <X>, stress: <N>

Title 3: <new title> (constraint: <which rule>)
  → vowel: <X>, stress: <N>

...

Title 12: <new title>
  → vowel: <X>, stress: <N>
```

No editing during the chain. Don't pre-judge any title. Push for 10-15
links.

### Step 4 — Mine the chain (writer-facing)

```
Which 2-3 titles pulled hardest? Underline them.

The strongest titles are usually NOT the ones you brought; they're the
ones the chain surfaced by phonetic adjacency.

Pick one to develop further → routes to `idea-to-title.md`.
```

## Mode 2 — Co-write cascade

### Step 1 — Each writer brings 5-10 candidate titles

To the session, before opening. No discussion of which is best.

### Step 2 — Open with No-Free Zone (read aloud)

Per `co-writing.md`:

- Say everything that comes to mind, no matter how dumb
- Silence = request for more
- Stay inside the song / cascade
- No technical talk during the cascade

### Step 3 — Cascade by trade-off

Writer A reads a title from their list. Writer B generates a new title
from A's title's stressed vowel + a shift. Writer B's new title goes to A.
A generates from B's new title. Repeat.

Strict turn-taking — partner generates EVERY OTHER title, not every third.

5-10 minutes without judging.

### Step 4 — Mine together

Both writers underline the 3-5 titles that pulled hardest. Discuss which
one the room agrees on (by either word or by shared silence-attention).

That title begins the song. Capture the rest in
`songwriting/songs/<slug>/ideation/title-candidates.md` for later.

## Constraint examples (vowel chains)

(Describing the cascade shape only — no specific song titles reproduced.)

**Same-vowel cascade (long-A territory):**
Seed → next stays in long-A → next stays in long-A → next stays...
Result: 10-15 titles all rhyming-compatible.

**Adjacent-vowel cascade (triangle walk):**
Seed at long-A → next moves to long-E (adjacent on tongue leg) → next moves
to long-I (next adjacent) → ...
Result: a walk along the vowel triangle, surfacing related but distinct
sonic territories.

**Diphthong-component cascade:**
Seed at long-A (which decomposes to short-ĕ + long-ē) → next picks up short-ĕ
or long-ē as primary → ...
Result: hidden assonance connections across what looks like different
vowels in spelling.

## Failure modes (recovery prompts)

```
"Writer judges each title before generating next"
  → re-establish No-Free Zone; silence = keep going

"All titles in chain are the same type"
  → vary type deliberately (Statement → Question → Image → Command)

"Stressed vowel keeps drifting"
  → tighten the vowel constraint OR move to vowel-triangle mode

"One writer dominates the cascade in co-write"
  → enforce strict turn-taking; partner generates every other title

"Titles all rhyme with cliche partners"
  → run the rhyme-stability test BEFORE the cascade; if stuck-vowel
    territory, change vowel altogether
```

## Coach posture

- Pat's framing: titles cluster in stressed-vowel families. The strongest
  title is usually surfaced by the cascade, not brought into it.
- Defuse "my title is precious" — after 10 chained titles, no single
  title feels load-bearing.
- The cascade is a warmup. Don't expect the song to come out of one
  cascade. Mining + development happen next.

## Cross-references

- `title-game.md` — full context
- `co-writing.md` — No-Free Zone protocol
- `hook.md` — seven title types
- `rhyme-sonic-bonding.md` — vowel triangle
- `phrasing.md` — front-/back-heavy
- `idea-to-title.md` — next-phase development of chosen title
- `brainstorm.md` — Path D (solo cascade) references this
