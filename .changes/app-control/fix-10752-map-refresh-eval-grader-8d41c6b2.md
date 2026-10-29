---
bump: patch
---

### Fixed

- **The `map-refreshes-each-control-skill` eval case passes a correct refresh plan.** Its judge failed every correct reply: the criteria asked the reply to commit and switch, while the prompt forbids both, so the judge failed a plan for not running; and they required each upkeep branch cut from `main`, where the refresh rules cut it from the fetched default-branch tip. The criteria now judge the plan, accept the fetched tip and the documented fallback when no pull-request tool is available, and still fail a shared branch or pull request, a second branch cut from or merging the first, a missing return to `main`, or asking which skill. The scaffold now adds the `origin` remote the pass fetches from, and the prompt states it.
