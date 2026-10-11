---
bump: minor
---

### Added

- Five-layer settings: plugin defaults, the `css_browser_target`, `css_important`, `css_layer` and `css_token_fallback` options, `~/docs/conventions/user-interface.yaml`, the team file `<home>/user-interface.yaml` and the personal `<home>/user-interface.local.yaml`, read through one shared resolver. Every value reports the layer it came from.
- `scripts/detect.mjs --config` prints the resolved settings, and its project report gains the browserslist query, Stylelint and `@eslint/css` config, and the kinds of style files present.
- `/user-interface:setup`: `check` shows each value with its source layer, invalid keys, keys set twice in personal layers, legacy files, whether the personal file is gitignored, and a personal file the main checkout has but this worktree lacks; `apply` writes one key in one layer.
