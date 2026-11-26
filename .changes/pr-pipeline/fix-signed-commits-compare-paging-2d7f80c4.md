---
bump: patch
---

### Fixed

- `check-signed-commits` pages the `since-sha...head` comparison 100 commits at a time until it has every commit the comparison counts, up to 10,000, instead of reading one unpaged response that stops at 250 commits and escalating the pull request to a person.
