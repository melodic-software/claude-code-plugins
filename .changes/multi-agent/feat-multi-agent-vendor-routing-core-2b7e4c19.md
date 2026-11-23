---
bump: minor
---

### Added

- Trust-model vendor routing core for `/multi-agent:route vendors`: closed JSON Schemas (`benchmark-registry.schema.json`, `verdict-record.schema.json`), pointer-only `reference/benchmarks.json`, `fetch-boards` wrapper over `scripts/fetch-docs.sh`, Read-only `board-reader` agent, and `vendor-decide` script with command-line tests.
- Vendor routing eval cases `ro-vendor-cites-sources` and `ro-vendor-unread-page-abstains` on fixture pages, plus fixture-page staging for `ro-vendor-everyday-default` and `ro-vendor-heavy-above-default`.
- `vendors` configuration block in `schemas/multi-agent.schema.json` and shipped switch defaults in `reference/defaults.yaml` (`routing: true`, `trials: false`, `auto_delegation: false`, plus `tiebreak`, `trials_prove`, `trials_fail`, per-vendor `in_use`/`rank`, and `sources.<id>.enabled`).
- Team benchmark rows support in `fetch-boards` and `vendor-decide` via `<repo>/docs/conventions/multi-agent/benchmarks.json` (appended after shipped rows; duplicate shipped ids refused with a note).
- Trial state script `skills/route/scripts/vendor-state` (`record`, `outcome`, `send-back`, `seen`) with `O_EXCL` outcome creation, per-machine data-folder resolution, machine-neutral outcomes keyed by `vendor:model:version:effort:work_type`, and command-line tests in `vendor-state.test.mjs`.
- Eval case `evals/ro-vendor-routing-off/` covering `vendors.routing: false` in the team layer.

### Changed

- `/multi-agent:route vendors` now fetches enabled registry pages through `fetch-boards`, dispatches `board-reader` per read page, decides via `vendor-decide` with `--settings` from the resolved `vendors` object, cites every source with its read state, carries the untrusted-content framing inline, names each tool's own skill for MCP-vs-CLI decisions, grants `vendor-state`, runs `vendor-state seen` to relay `registry recheck due` on new model ids, records reviewed `trial` verdicts with `vendor-state record`, and reports rejected `proven` results without re-entering trial automatically.
- `scripts/resolve-roles.sh` and `skills/setup/scripts/setup.sh` validate `vendors.*` across layers (rejecting `trials_fail: 1` and unknown tiebreak steps) and emit the resolved `vendors` object with per-key source layers.
- `vendor-decide` accepts `--state-dir` (defaulting to the plugin data-folder rule), routes proven pairs with basis `proven`, excludes failed pairs, routes active trials with basis `trial`, writes nothing on routine runs, and honors `--settings` for routing-off decisions, silent `in_use: false` skipping, one-line unavailable notes for `in_use: true`, ordered `tiebreak` steps and vendor ranks, per-source enable overrides, and inactive-trials notices when counts are unset.
- `reference/vendors.md` now states the trust model and points to `reference/benchmarks.json`, with the dated checked column and model names removed; `reference/config.md` and `README.md` document the `vendors` keys, layers, team rows file, trial state location, and `send-back` command.
