---
bump: patch
---

### Changed

- The admission policy's rule-admission cost hit splits charge terms, which always refuse, from spend words, which refuse unless a phrase naming the subscribed model vendor claims them; the evaluator holds both closed lists and refuses any spend word not tied to that vendor, matching `rule-admit.sh`.
