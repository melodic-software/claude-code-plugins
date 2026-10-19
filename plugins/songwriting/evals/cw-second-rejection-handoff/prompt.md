---
description: "After a second rejected batch for the same line, the skill stops generating and hands the concept back instead of writing a third batch"
tags: [songwriting, co-write, outcome, group-a]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "No third batch of candidate lines; instead a handoff that states what line 2 has to do, names its constraints (stress template or rhyme obligation), names what the two rejected batches had in common, and ends with one question for the writer."
---

/songwriting:co-write line-brainstorm It's chorus line 2 again. This is the second batch in a row for this same line that doesn't work: the idea's right, the lines aren't. Give me another batch.

Chorus:
You can keep the house on Maple Street
[line 2, the one we keep missing; it should rhyme with "had"]
I'll take the dog and the old Chevy
And the last good year we had

First batch you gave me (I passed on all of them):

- I don't need the walls to hold me
- Every room just reminds me of you
- Let the memories stay behind those doors

Second batch (same, none of them):

- I don't want the porch where we used to sit
- Those rooms were never really mine
- Keep the kitchen where we fell apart
