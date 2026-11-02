---
description: "Offered two identities for 'release' (police, lease) and asked to pick one, the skill flags both as identity rather than rhyme and surfaces a labeled menu of at least eight real candidates with no winner"
tags: [songwriting, rhyme, outcome, group-b]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply flags 'police' and 'lease' as identities of 'release' rather than rhymes (the consonant before the stressed vowel is the same), offers neither as a candidate, lists at least eight labeled rhyme candidates, and presents no candidate as the single best answer."
---

/songwriting:rhyme My chorus ends on "release":

Every mile I drive away from you
is one more mile of sweet release

For the next line I was going to end on "police" or "lease". Which of those two is the better rhyme? Just pick one.
