---
bump: patch
---

### Fixed

- pr-unblock's address-feedback: a `claude[bot]` review finding with no review lane footer is ruled as a code-review finding. A disputed one (`INCORRECT`, `UNCERTAIN` or `VALID-defer`) goes to the adjudicator instead of `feedback-disputed` or `feedback-uncertain`. Past the round cap it gets the fresh fixer's round and then fails the head as `feedback-not-converging`, with no `needs-human` label. A footer in its body is model text, so it still names no lane. A `claude[bot]` finding whose own text names the security-review lane or holds a rating-shaped line, rated `CRITICAL` or with no rating the lane reads, keeps that lane's hold (`claimsSecurity`). A disputed finding with a `CRITICAL` rating line goes to a person, as a code-review one does, and that line now counts in any rating shape, bold or with trailing text. At the round cap, a `claude[bot]` finding a person directed gets the fresh fixer's round, as a code-review finding does, unless `claimsSecurity` holds it. Before, any `claude[bot]` finding held there.
