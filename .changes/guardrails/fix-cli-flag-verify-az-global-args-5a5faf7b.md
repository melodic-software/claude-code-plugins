---
bump: patch
---

### Fixed

- `cli-flag-verify` no longer reports az global arguments such as `--only-show-errors` as unknown flags. `az --help` lists none of them, so a flag missing from the resolved help is also looked up in `az version --help`, which carries az's Global Arguments.
