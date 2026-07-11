# Title Generation Prompt

Use this prompt when the user wants Pat Pattison-style title candidates
from a seed idea, theme, character, situation, or emotion. Generates
candidates through the seven title types plus the Nashville stressed-
vowel-sound method plus the "four-or-five-angles-down-the-road"
heuristic.

```text
Generate title candidates using Pat Pattison's title pipeline.

Seed idea (one sentence describing what the song is about):
<seed>

Tone:
<serious | playful | bitter | intimate | comic | wistful | defiant | other>

POV constraint:
<first person | second person | third person | unknown>

Genre lean:
<country | folk | pop | rock | R&amp;B | hip-hop | other | unknown>

Process:
1. Distill the seed to a one-phrase emotional core.
2. List the seed's surrounding word family — image, action, location,
   relationship, conflict, body, time.
3. For each of the seven title types, generate 2-4 candidates:
   - One-word title
   - Place-name title
   - Person-name title
   - Color or sensory-detail title
   - Comparative title (more X than Y, less X than Y)
   - Word-play title (pun, double meaning, idiom flip)
   - Sonic-bonding title (alliteration, assonance, internal rhyme)
4. Apply the four-or-five-angles-down-the-road heuristic — push past
   the obvious title to the angle most writers would not reach.
5. Apply the Nashville stressed-vowel-sound method — pick the seed's
   stressed vowel, list other words sharing that vowel, recombine.
6. For each candidate, mark its rhyme-stability surface (how easy is
   it to find rhymes for its stressed vowel?) and its emotional fit
   with the seed.

Return format:

Emotional core:
<one phrase>

Word family:
- Images:
- Actions:
- Locations:
- Relationships:
- Conflicts:
- Body / time:

Title candidates by type:

One-word:
- ...

Place-name:
- ...

Person-name:
- ...

Color / sensory:
- ...

Comparative:
- ...

Word-play:
- ...

Sonic-bonding:
- ...

Four-or-five-angles candidates:
- ...

Stressed-vowel-sound candidates:
- ...

Top three picks (one for arrival, one for surprise, one for risk):
1. <pick> — fit: ..., rhyme surface: ...
2. <pick> — fit: ..., rhyme surface: ...
3. <pick> — fit: ..., rhyme surface: ...

Recommended next step:
<rhyme worksheet | object-write the title's world | form choice>
```

Example:

```text
Seed: a woman finally tells her husband she's leaving after years of patience
Tone: defiant but tender
POV: first person
Genre lean: country
```
