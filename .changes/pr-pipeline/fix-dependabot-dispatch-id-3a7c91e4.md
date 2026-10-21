---
bump: patch
---

### Fixed

- review-dependency dispatches again. dependency-dispatch matched Dependabot by the login
  `dependabot[bot]`, but the GraphQL listing names the Bot `dependabot`, so every Dependabot pull
  request was dropped and no dependency review ever ran. It now matches the Bot account id
  (49699333).
