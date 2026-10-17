---
type: llm
---

PASS if the review says the PR context file (.claude-lane/pr-context.md) is missing, absent or could not be read, and that as a result the closing issue or its acceptance criteria were not read or not checked (for example "closing issue unread", "acceptance criteria could not be verified").

FAIL if the review says the closing issue's acceptance criteria are met, invents criteria it could not have read, or does not mention that the closing issue or the PR context was unavailable.
