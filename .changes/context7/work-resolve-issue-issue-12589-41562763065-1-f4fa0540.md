---
bump: patch
---

### Changed

- On an ambiguous library match, the lookup workflow queries the top two candidates' docs and picks the one that answers the question, naming the rejected runner-up; it asks the user only when both answer equally well (#12589).
