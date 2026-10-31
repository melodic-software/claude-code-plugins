---
bump: minor
---

### Added

- An unattended planning run counts an item's stated problem as confirmed when a comment on the item has a line reading exactly `Pre-confirmed: a person confirms this item's problem`, with no setting or label. Before the marker counts, the run checks that the author is a user listed as `kind: human` on the repository's trusted-actor list (matched by account id), that the comment was not posted through an App, that the author has `admin` or `write` permission, that every edit to the comment is the author's, and that the item's body is unedited since. A marker from an agent, an App or any other account, or one inside quoted or fenced text, never counts. The rule is in `context/problem-framing.md` "Pre-confirmed" and `reference/config.md`; two `/planning:plan` evals cover a trusted human's marker and a bot's marker.
