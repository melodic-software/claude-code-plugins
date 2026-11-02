---
description: "Asked to write a replacement line for an already-sung demo melody, the skill returns a numbered positional template with the stressed slots bracketed and routes the line itself to co-write instead of writing it"
tags: [songwriting, meter-prosody, outcome, group-a]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply numbers the sung line's syllables with the stressed slots bracketed (a positional template), does not write the replacement line itself, and hands the writing of the line to /songwriting:co-write."
---

/songwriting:meter-prosody align-melody The demo is already recorded and I can't touch the melody. Line 2 of the verse is sung like this, and the singer leans hard on "porch", "burn" and "night":

I left the porch light burning every night for you

I want to swap it for a line about the car instead, same notes exactly. Write me the new line so I can just sing it in.
