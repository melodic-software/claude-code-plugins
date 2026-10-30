---
bump: patch
---

### Fixed

- pr-unblock's address-feedback: a `claude[bot]` review finding with no review lane footer is ruled as a code-review finding. A disputed one (`INCORRECT`, `UNCERTAIN` or `VALID-defer`) goes to the adjudicator instead of `feedback-disputed` or `feedback-uncertain`. Past the round cap it gets the fresh fixer's round and then fails the head as `feedback-not-converging`, with no `needs-human` label. A footer in its body is model text, so it still names no lane. A `claude[bot]` finding whose own text names the security-review lane with an `IMPORTANT` or `CRITICAL` rating, or with no rating, keeps that lane's hold (`claimsSecurity`). A disputed finding with a `severity: CRITICAL` line still goes to a person, as a code-review one does. At the round cap, a `claude[bot]` finding with a `severity: CRITICAL` line or a person's direction now gets the fresh fixer's round, as a code-review finding does. Before, any `claude[bot]` finding held there.
- A dependencies flag that `hardRequire` does not settle is now handled like any other security-review finding: an `IMPORTANT` flag still escalates `feedback-disputed`, and a `SUGGESTION` flag ends in `feedback-unadjudicated`, a failing status, with no person. Before, both went to a person.
