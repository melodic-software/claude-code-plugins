---
bump: patch
---

### Changed

- The control-skill contract now states four rules it was missing ([#9507](https://github.com/melodic-software/claude-code-plugins/issues/9507)).
  - A module folder's `README.md` indexes the features under it, and the hub's index then names it in place of a line per feature.
  - A drive through one entry point never marks another `driven`.
  - A journey belongs to the control skill of the app where the user starts and ends it. The pages it crosses in an integrated app are steps that app owns, and every service it depends on is a dependency service that Ready checks.
  - The server tier's Capture rows record the app's own process, and the `logs` row may name a counters recorder such as `dotnet-counters collect`.
