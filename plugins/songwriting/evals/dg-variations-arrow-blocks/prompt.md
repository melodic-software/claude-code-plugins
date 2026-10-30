---
description: "A variations request comes back as three or four labeled full-section blocks with the changed line marked, not a list of bare one-line candidates, with the rubric's syllable counts run as datamuse.sh commands. A stand-in curl keeps datamuse.sh offline. Needs --scaffold --allow-tools Bash."
tags: [songwriting, diagnose, outcome, group-a]
plugins: ["../..", "datamuse-path"]
max_turns: 24
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "Three or four labeled variations of line 3, each shown as the full four-line verse with the changed line marked with the ► glyph and the unchanged lines kept in context; no more than four variations in the chat menu; the candidates' syllables counted with datamuse.sh syllables."
---

/songwriting:diagnose variations Line 3 of this verse feels flat. Give me a bunch of versions of it:

Dust on the dashboard, a map I never fold
Your sweater in the back seat, still smelling like the cold
I really miss you and I'm feeling kind of sad
Eighty miles of nothing and the radio gone bad

I already counted syllables: 11, 13, 12, 13. There's no melody yet and no voiceprint, and I don't need a file saved; just show me the versions here.
