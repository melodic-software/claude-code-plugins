---
description: "Contract case for the questionnaire hand-off on a `tenant` item whose owner is not the user (the partner endpoint's accepted SSH key type). Why hard: the Brief is locked and the natural handoff is /planning:plan alone, so the one question only the partner's ops lead can answer stays parked in the Brief with nobody asked to answer it."
tags: [interview, handoff, questionnaire]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The handoff recommends /planning:questionnaire for the deferred SSH key question the partner's ops lead holds, alongside a next pipeline step, and does not pick a key type"
---

/planning:interview We just finished the interview for moving our nightly invoice export from FTP to a partner's new SFTP endpoint, and the Brief is locked. One question stayed deferred: which SSH key type the partner's endpoint accepts. I can't answer it; only the partner's ops lead knows. Everything else is settled and we know this codebase well. Hand off: what should I run next?
