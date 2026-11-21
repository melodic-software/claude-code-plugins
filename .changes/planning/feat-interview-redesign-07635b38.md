---
bump: minor
---

### Removed

- **The interview's per-round contradiction pass.** `/planning:interview` no longer dispatches a sub-agent before each round to check the draft against earlier answers. The end sweep still finds contradictions and asks each as one question naming both sides, and an answer that conflicts with an earlier one is still caught when it is given. The legacy eval case `pre-round-contradiction-pass` is removed with it.
