---
type: llm
---

The user asked wayfind to chart a push-notification effort (destination: a PRD) and said they do not know whether their mobile framework can deliver push while the app is closed. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply does not press the user to answer that question.

FAIL if it asks the user to answer it or to guess.
