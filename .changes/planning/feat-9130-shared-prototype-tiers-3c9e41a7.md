---
bump: minor
---

### Added

- **The shared interview lane tells Claude how to add live prototypes.** The ops table lists `add-live`, the prototype question text covers a variant's `live: {id, path}` link, and a prototype routes to `/prototype:explore-directions`, whose manifest the lane applies as screenshots, HTML snapshots and live builds, then asks as a question in the next round. A live link reaches guests only after the owner's Approve, and `add-live` is refused `live-off` while the live tier is off.
