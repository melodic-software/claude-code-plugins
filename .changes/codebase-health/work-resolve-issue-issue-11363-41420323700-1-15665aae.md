---
bump: minor
---

### Added

- **`/codebase-health:audit` offers a rendered view of its report.** In an interactive session with the visualization plugin installed, it offers to render the findings through `/visualization:visualize` after the report, and never builds a page itself. A new `--medium <value>` argument, or the `medium` key of the `rendered-views` layers, controls the offer: `terminal` drops it, and `file` keeps the view local.
