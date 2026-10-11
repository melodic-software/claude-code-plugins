---
bump: patch
---

### Changed

- `/planning:interview` words each question so a bare "yes" accepts the recommendation: a negative recommendation is asked as "Should X stay out of this change?", not "Should we do X?" answered "No". The `interview-negative-recommendation-yes-accepts` eval case failed on all three with-plugin runs before this rule.
