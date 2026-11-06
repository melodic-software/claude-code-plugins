---
bump: patch
---

### Fixed

- pr-merge's candidate listing matches trusted-actors.json's accounts by numeric id (`User.databaseId`, `Bot.databaseId`) instead of login, so a renamed App's pull requests stay candidates without a change to the list. It reads the open pull requests in one paginated GraphQL query, at most 10 pages of 100, with the open count on each page, which drops the separate count read: one call fewer per try. A list of exactly 1000 open pull requests now lists; more than 1000 still holds the run green.
