---
bump: minor
---

### Added

- `/work-items:work`: the attended confirm prompt now prints an `I read this item as: <goal; done when>` line above "Proceed with this item?", drawn from the item's brief, so a misread item is caught before the claim (#11864). Autonomous runs print neither the line nor the prompt.
