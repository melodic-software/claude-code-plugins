---
bump: major
---

### Added

- `/planning:interview` gains a fourth question surface, `document`, beside terminal, page and shared session. A decision another person holds becomes a Markdown document they fill in: the interview asks the user only about the send (who it goes to, what they need back), writes each question in the shared question shape under its register `Q<N>` to `<memory_dir>/<topic-slug>/document-<recipient-role-slug>.md`, records each as an `open` row awaiting the recipient, and resolves those rows by id through the normal read-back when the filled document returns. Ask for it with `/planning:interview document <topic>`, or in words ("make a questionnaire for the DBA"). The surface registry takes an `onRequest` entry field, so this surface is never offered beside the others.

### Removed

- The `questionnaire` skill and its eval cases. Its behavior lives in `/planning:interview`'s document surface, and the interview's and `/planning:prd`'s handoffs now recommend `/planning:interview document <topic>` for a question only another person can answer.
