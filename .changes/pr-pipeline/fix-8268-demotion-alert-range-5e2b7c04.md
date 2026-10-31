---
bump: patch
---

### Fixed

- A post-merge demotion or failure record now says why it lists no range: main's runs could not be
  read, no green full run came first, the compare could not be listed, the range passes 300
  commits, the first-parent walk missed the base, or the last green run is at the failing commit,
  which implicates no merge. A failed read also emits a `::warning::`. Compare is paged, so a range
  past GitHub's 250-commit limit is walked, and the record lists 100 commits with an "and N more"
  compare link. A direct push is called one, its subject is quoted without backticks and cut to 100
  characters with its backslashes intact, and a commit with no GitHub login reads `unknown`.
