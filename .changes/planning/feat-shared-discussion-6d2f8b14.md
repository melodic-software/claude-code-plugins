---
bump: minor
---

### Added

- Shared interview: a Discussion under each question, below its Claude section and folded by default. Its head counts the comments and the ones new to you since you last opened it, on every device. Anyone who can write adds a comment; its author edits or deletes it; the host hides any, which leaves it only to the host and its author, marked Hidden. Comments take mentions and the chat's emoji reactions. "@Claude" in a comment also sends it to Claude as a request on the question, which waits for the host's Run like any guest request (the host's own runs at once); Claude's answer shows in the Claude section with a "from Discussion" link back to the comment. People already in a Discussion get a notification of new comments. The round's digest gives Claude each question's Discussion, without hidden comments, with names only when names go to Claude.
- Shared interview: the session file moves to schemaVersion 5, which holds the Discussions and when each person last opened each one. An older file is upgraded on load with no comments.
