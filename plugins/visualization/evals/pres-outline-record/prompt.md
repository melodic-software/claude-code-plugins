---
description: "Asked for slides from typed notes, the skill delivers the markdown outline record (title, a sentence per section, per-slide heading, text and speaker notes) and no hand-built deck page"
tags: [visualization, present, outcome, outline-record]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A markdown outline with a deck title, one sentence per section, and at least three slides each carrying a heading, its text and speaker notes, delivered as the outline itself; no HTML deck page or slide markup is written into the reply."
---

/visualization:present Turn my notes below into a short deck for Thursday's ops review. Keep it to three or four slides.

Notes:

- Problem: support tickets opened after 18:00 wait a median of 9 hours for a first reply. The Lisbon account complained twice last month.
- Proposal: a follow-the-sun rota. Dublin, Manila and Austin each cover an 8-hour block of one shared queue, so nobody works nights.
- Cost: 4 new hires in Manila; finance has seen the budget line.
- Ask: approval for the Manila hires by December so the rota starts in Q1.
- Say out loud: we tried an on-call pager in 2024 and people burned out.
