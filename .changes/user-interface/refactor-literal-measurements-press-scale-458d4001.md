---
bump: minor
---

### Added

- `animation.scale.press` (default `0.97`): the scale a pressed control takes. The press behavior and the write-css `press-feedback` recipe now name it instead of stating 0.95 to 0.98, 0.96 and 0.97 in different places.
- `spacing.control_padding` (default `0.75rem`, `1.25rem`, block then inline): a control's padding, used by the write-css `label-centered-on-its-letters-with-text-box` recipe.
- `reference/values.md`: the one place that says which value wins (a matching project token, then a team or personal key, then `css.token_fallback`, then the key's default), how a recipe's `{{key}}` placeholder is filled, and how a team file nests keys. Every skill's config step points there and names any setting the resolver dropped.

### Changed

- `write-animation`, `audit` and `design` now pass the `css_*` userConfig values to the resolver, so `css.token_fallback` set there is honored.
- `write-css` and `setup` fall back to the shipped `reference/defaults.yaml` when the resolver cannot run; `write-css` uses a key's value, not its own, when the project has no token source.
