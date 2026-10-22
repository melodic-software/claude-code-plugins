---
bump: patch
---

### Fixed

- `share.sh ensure-running --open` starts the 30-second clock that deletes the owner's open page only after the browser has been handed the page, so an opener that takes time to start (such as one named by `SHARED_BROWSER`) still finds it.
