---
bump: minor
---

### Added

- **`/prototype:explore-directions` and `/prototype:pressure-test` honor the `rendered-views` `medium` preference.** Both take a `--medium` argument and read the `rendered-views` layers. In `explore-directions`, `terminal` or `file` drops the design-canvas offer, and the mockup stays a local file. In `pressure-test`, unless the request names a shell, `terminal` picks the terminal app and `file`, `artifact` or `hosted` picks the HTML demo shell. Each names the source of `medium`.
