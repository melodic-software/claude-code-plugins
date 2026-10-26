---
bump: patch
---

### Fixed

- **`/education:illustrate` draws parts that hang off one center as a hub, even when each part has details.** The skill picks a diagram's kind by how its parts relate, not by how much each part says: a person's other bands are a `hub` with their details in `text`, and `compare` is only for options weighed against each other on the same points. ([#6169](https://github.com/melodic-software/claude-code-plugins/issues/6169))
