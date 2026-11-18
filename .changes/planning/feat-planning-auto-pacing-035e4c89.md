---
bump: minor
---

### Added

- `question_pacing` takes a third value, `auto`: before the first round the interview asks one question at a time when the topic is broad and open-ended (many independent directions, little settled upstream), and rounds otherwise, stating its choice and how to switch in one line. The default stays `round`.
- Once the user confirms the shared understanding, the interview offers the spec step for work that needs one: `/planning:prd` when product intent (users, success measures) is still unsettled, `/planning:plan` for an engineering task.
