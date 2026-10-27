---
bump: minor
---

### Added

- **`audit`: the detectors read YAML settings first.** `check-stamps.sh`, `list-corpus.sh`, `score-golden.sh` and `sweep-ledger.sh` read the team layer from `<home>/attribution.yaml` and the overlay from `<home>/attribution.local.yaml` (ADR 0075), `<home>` being the bound convention home, else `docs/conventions`. Each falls back to its `.claude/attribution.json` or `.claude/attribution.local.json` only when the YAML is absent, per file rather than per key, so a repository with no YAML reads what it read before. A YAML file that does not parse is named on stderr and read as absent, its `.claude/` JSON included.

### Changed

- **`audit`: one config reader serves all four detectors.** `lib.sh` carries `cfg_scalar` and `cfg_list` in place of each script's own jq reader, and every `--show-config` line names the layer that supplied its value. `check-stamps.sh` now names it for `stamp_expiry_days` and `trigger_less_stamp_check`, where it reported `(bundled default)` for a configured value. The jq-missing notice and `sweep-ledger.sh status`'s exit 4 now apply only when a JSON layer is present, and an `excluded_paths` glob holding a space is kept whole instead of split in two. The audit skill reads `.separation` from a YAML layer as well as a JSON one, and the jq prerequisite note says only the JSON layers need jq.
