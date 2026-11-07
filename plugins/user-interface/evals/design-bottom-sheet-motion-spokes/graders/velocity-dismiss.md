---
type: llm
arm: both
---
Expectation: "The answer dismisses on a fast release past a velocity threshold, not on drag
distance alone, and carries the release velocity into the settle".

PASS only if the swipe dismisses when the release is faster than a velocity threshold (a distance
threshold beside it is fine) and the release velocity is handed to the settle (a spring or the
closing animation). FAIL if dismissal depends on drag distance alone, or the settle ignores the
release velocity.
