---
bump: patch
---

### Fixed

- `/harness-ops:plugins` audit no longer predicts `claude plugin update` for an in-repo record of a marketplace whose `directory` source is the repository the run stands in: the CLI reads that folder live and leaves the record pinned. The report lists the record as read live from the folder, pinned at its version, and suggests removing and re-adding the record if the pin matters.
