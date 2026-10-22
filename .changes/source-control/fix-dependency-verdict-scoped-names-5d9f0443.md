---
bump: patch
---

### Fixed

- The dependency review reference now says scoped package names (`@scope/name`) and registry URLs are allowed in a verdict's reasons and evidence; only @-mentions of people are refused. The verdict job had refused every verdict naming a scoped npm package.
