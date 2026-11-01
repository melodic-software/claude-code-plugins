---
bump: patch
---

### Fixed

- The interview page's Notes panel keeps its send message (for example "Queued, Claude is busy") when a state push redraws the panel. Before, the message went blank as soon as the next push arrived, often before it could be read. "Queued, Claude is busy" drops off once Claude is no longer busy with the earlier wake. A failed send clears the message, and so does leaving the Notes panel.
