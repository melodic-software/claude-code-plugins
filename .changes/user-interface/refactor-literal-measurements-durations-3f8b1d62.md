---
bump: minor
---

### Changed

- The `write-css` review script checks `transition` and `transition-duration` against the resolved `animation.duration_ms.large`, which callers now pass in `--config`, falling back to the shipped default, instead of the bundled linter's fixed limits; `css.rules.disable` still turns the `duration` rule off. The `duration` rule gives hover feedback its own `hover` role.
- The README's configuration section and `/user-interface:setup` describe the four layers the resolver reads and drop the `--user` write and the user-global layer; `setup apply` nests a dotted key as `reference/values.md` "Setting a key" says, and shows the shipped `defaults.yaml` values when `node` is missing. The schema description and the `defaults.yaml` header list the same four layers.
