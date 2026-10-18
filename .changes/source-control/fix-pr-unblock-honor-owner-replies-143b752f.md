---
bump: patch
---

### Fixed

- `comments --ci` follows a trusted person's reply on a thread the lane left open. The review-thread tool now gives each comment an `author`, and marks as `direction` any reply from a person on the trusted-actor list that came after the lane's escalation. The skill applies that decision within the same path rules, and never records it as `INCORRECT`.
