# Diagnose Section Prompt

Use this prompt when the user wants a Pat Pattison-style diagnosis of a
verse, chorus, bridge, or refrain. Runs the Five Compositional Elements
checklist plus the stable/unstable meta-question. Returns one focused
finding, not a list.

```text
Diagnose this song section using Pat Pattison's framework.

Section type:
<verse | chorus | bridge | refrain | transitional bridge>

Section lyric:
<paste section>

Central emotion of the whole song (one phrase):
<phrase>

Character of that emotion:
<stable | unstable | mixed>

Diagnostic pipeline:
1. Read the section aloud once for sensation.
2. Fill the Five Compositional Elements worksheet:
   - Number of lines
   - Line lengths (stresses per line)
   - Rhyme scheme (e.g., abab, aabb, abcb, xaxa, none)
   - Rhyme types per pair (perfect, family, additive, subtractive,
     assonance, consonance, partial, weak-syllable)
   - Rhythm (duple, triple, mixed; established pattern; variations)
3. Run the stable/unstable scan on the lyric controller across these
   levers:
   - Rhyme stability
   - Rhyme scheme closure
   - Phrase count and balance
   - Phrase length
   - Closure type (expected, deceptive, unexpected)
   - Sentence structure (complete declarative, fragment, conditional)
   - Verb tense
   - Point of view
4. Section job within the form (verse setup, chorus arrival, bridge
   release, etc.) — does the section's stability character match?

Return format:

Five Compositional Elements:
- Number of lines: ...
- Line lengths: ...
- Rhyme scheme: ...
- Rhyme types: ...
- Rhythm: ...

Stable/unstable verdict:
- Section lyric character: ...
- Levers carrying that character: ...
- Match with central emotion: supports | mutes | pushes-against
- Match with section job: yes | partially | no

Dominant problem (one):
- ...

Cheapest fix (one move):
- ...

Secondary observations (max 2, only if affect the dominant fix):
- ...
```

Example:

```text
Section type: chorus
Section lyric:
<two-line chorus draft>

Central emotion: defiant relief after walking out
Character: stable (resolved)
```
