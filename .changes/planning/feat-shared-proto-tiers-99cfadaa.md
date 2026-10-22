---
bump: minor
---

### Added

- A shared interview session has a `prototypeTiers` setting (`shared_session.prototype_tiers`, default screenshots and HTML snapshots, live off) with Screenshots, HTML snapshots and Live prototypes switches under Prototypes in the Host settings. A view switched off leaves guests' state (a picture variant's asset while screenshots are off, an html one's while snapshots are off), and a guest's request for an html variant answers 404 while snapshots are off; the owner still sees every view, each hidden one named. With every view off, a prototype question shows as text with a note and still takes picks. Live prototypes is only stored for now. A session from before the setting loads and is written back unchanged.
