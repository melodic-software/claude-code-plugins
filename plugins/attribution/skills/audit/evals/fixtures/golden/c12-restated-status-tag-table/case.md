| Number | Bounds | Status |
|---|---|---|
| 1,536 chars | Claude Code listing cap for description + when_to_use per skill; truncation is tail-first, so key use case goes first | Anthropic-prescribed |
| 1% of context window | Skill-listing budget; on overflow descriptions drop lowest-priority-first (usage-frequency/recency scored, *(community)* detail; official phrasing: least-invoked-first) while names always remain | Anthropic-prescribed; corroborated |
