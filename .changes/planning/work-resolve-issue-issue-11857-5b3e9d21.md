---
bump: minor
---

### Added

- `/planning:interview` rounds group their questions under topic headers when a round spans several topics, and every round ends with an index table (`Q`, one-line recommendation, basis, main alternative) so the user can answer by exception or by topic.
- A `discussing` register status: when the user asks to talk a question through, its row moves to `discussing`, and the question is asked again afterwards with the recommendation revised old → new → why. `scripts/check-open-questions.sh` accepts `discussing`, counts it in `open=` and exits 1 on it as it does on `open`.
- A `Held:` line in the round header names each question held for an in-flight lookup and what it waits on. A held question gets its register row when the line first names it.
- Every recommendation carries an `Origin:` line, and every alternative an `origin:` note: the user, a named source with its link, or new (ours).
- A `question_pacing` user setting: `round` (default) or `single`, which asks the same frontier one question per message in the terminal lane.
