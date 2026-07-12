# Metaphor Recipe Prompt

Use this prompt when the user wants metaphor options for a subject via
Pat Pattison's eight named metaphor moves. Returns one candidate per
move, with the linking-quality and a usability note for each.

```text
Generate metaphor candidates using Pat Pattison's 8 named moves.

Subject (the noun, emotion, situation, or character to metaphorize):
<subject>

Context (one phrase describing the moment in the song this metaphor
serves):
<context>

POV constraint (optional):
<first person | second person | third person | any>

Tone constraint (optional):
<serious | playful | bitter | intimate | comic | any>

Process — run all 8 moves:

1. Expressed Identity — A is B (noun is noun). Pick a noun from a
   different family.
2. Qualifying Metaphor — adjective + noun, where the adjective is
   literally false applied to the noun. Pick an adjective from a
   different family.
3. Verbal Metaphor — noun + verb, where the verb is literally false
   applied to the noun. Pick a verb from a different family.
4. Playing in Keys — borrow terms from a "key" (semantic family). Pick
   a key — ocean, weather, kitchen, machinery, body, court, war, etc.
   — then borrow 3 of its terms.
5. Characteristic Questions — ask "what is this subject's [quality]?"
   for several qualities. Each answer is a metaphor seed.
6. Participles as Adjectives — turn a verb into a participle modifier.
   The verb should not literally belong to the subject's family.
7. Metaphor-vs-Simile Focus — write the same comparison as both
   simile (X is like Y) and metaphor (X is Y). Pick whichever keeps
   focus on the subject vs the comparator.
8. Simile for Multiple Comparisons — write one simile that opens 2-3
   sub-comparisons (X is like Y, which is also like Z, which feels
   like W).

For each candidate:
- State the linking quality (why the metaphor lands).
- Confirm the comparison is literally false.
- Rate the family-distance (close, medium, far) between subject and
  comparator.
- Note one extension the metaphor opens (a follow-on image or verb).

Return format:

Subject: ...
Context: ...

1. Expressed Identity: <subject> is <comparator>
   - Linking quality: ...
   - Literally false: yes/no
   - Family distance: ...
   - Extension opens: ...

2. Qualifying Metaphor: <adjective> <subject>
   - Linking quality: ...
   - Literally false: yes/no
   - Family distance: ...
   - Extension opens: ...

3. Verbal Metaphor: <subject> <verb>
   - Linking quality: ...
   - Literally false: yes/no
   - Family distance: ...
   - Extension opens: ...

4. Playing in Keys: borrowed key = <key>
   - Borrowed terms: ...
   - Linking quality: ...
   - Sample line:

5. Characteristic Questions: (one example)
   - Quality asked: ...
   - Answer: ...
   - Linking quality: ...

6. Participle as Adjective: <participle> <subject>
   - Linking quality: ...
   - Literally false: yes/no

7. Simile vs Metaphor focus:
   - Simile: <subject> is like <comparator>
   - Metaphor: <subject> is <comparator>
   - Focus winner: simile (keeps subject in focus) | metaphor (commits
     to comparator's world)

8. Simile for Multiple Comparisons:
   - Layered simile: ...
   - Sub-comparisons opened: ...

Top three picks (one for surprise, one for development, one for hook
position):
1. <pick from list above> — why: ...
2. <pick> — why: ...
3. <pick> — why: ...

Recommended next step:
<object-write the strongest candidate for 90 seconds | extend the
metaphor across a section | test as title via the title generator>
```

Example:

```text
Subject: jealousy
Context: chorus arrival — the speaker finally names what they feel
Tone: bitter, controlled
```
