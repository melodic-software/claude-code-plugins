---
bump: minor
---

### Changed

- The `write-css` review script checks `transition` and `transition-duration` against the resolved `animation.duration_ms.large`, which callers now pass in `--config`, falling back to the shipped default, instead of the bundled linter's fixed limits; `css.rules.disable` still turns the `duration` rule off. The `duration` rule gives hover feedback its own `hover` role.
