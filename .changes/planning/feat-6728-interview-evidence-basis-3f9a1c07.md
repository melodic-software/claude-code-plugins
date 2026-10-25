---
bump: minor
---

### Changed

- `/planning:interview` no longer accepts a bare `judgment` basis for a recommendation. Every recommendation now lists each fact it rests on with its source (a `file:line`, a URL fetched this session, a session-transcript finding, or tool output) and one `Inference:` line on why those facts lead to this answer for this user. A question with no fact to cite is researched first, or asked with a `Withheld:` line naming the evidence that would settle it. The page surface's `basis` field carries the same evidence list. The shared `context/recommendation-basis.md` contract is unchanged.
