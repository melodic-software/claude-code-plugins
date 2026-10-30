---
description: "Contract case for the questionnaire hand-off on an assumption-sweep `person` item the user cannot answer (the retention window the team's DBA sets). Why hard: the Brief is locked and the natural handoff is /planning:plan alone, so the one question only the DBA can answer stays parked in the Brief with nobody asked to answer it, or the run fills in a window on her behalf."
tags: [interview, handoff, questionnaire, assumption-sweep]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The handoff recommends /planning:questionnaire for the deferred retention-window question the DBA holds, alongside a next pipeline step, without choosing a window or running the questionnaire itself"
---

/planning:interview We just finished the interview for a purge job that deletes closed support tickets after their retention window, and the Brief is locked. The assumption sweep found that the draft had fixed the retention window without asking. I told you I can't answer that: Dana, our DBA, sets it, and no document or system we can reach records it, so it stayed deferred to her. Everything else is settled and we know this codebase well. Hand off: what should I run next?
