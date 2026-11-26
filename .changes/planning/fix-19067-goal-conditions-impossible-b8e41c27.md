---
bump: patch
---

### Fixed

- **`/planning:draft-goal-condition` refuses two drafts the goal evaluator can only end as impossible.** Step 2 now treats an element that must happen before a fixed clock time as fragile and writes the time as an end of its own (`…, or date -u shows <time> or later`). It also checks every required element against the others and the repository's gates, and refuses a draft where one element requires a state another forbids, such as a hold label that keeps a required check red beside an element that needs that check green.
