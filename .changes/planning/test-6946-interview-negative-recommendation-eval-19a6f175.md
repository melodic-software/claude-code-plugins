---
bump: patch
---

### Added

- **An interview eval case for a question whose natural recommendation is negative.** `interview-negative-recommendation-yes-accepts` floats a side idea (rewriting the admin page in React) that the interview should recommend against, and checks that round 1 asks about it and words the question so that answering "yes" accepts the recommendation. The skill body is unchanged: a with-and-without run of this case decides whether a wording rule is added.
