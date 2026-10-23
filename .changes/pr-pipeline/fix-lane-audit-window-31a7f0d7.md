---
bump: patch
---

### Fixed

- The lane sweep's collect job reads every run of its 24-hour window. It made one capped run listing, which returns at most 1,000 runs and so covered about the last 4 hours. It now reads each workflow's run count with one `per_page=1` call and halves any range at the cap until each part fits, inside its 350-call budget with 170 calls kept for the units. A workflow it reads only part of is named in a warning, and its unit carries `window_complete: false`, which the judge is told to report as partial.
