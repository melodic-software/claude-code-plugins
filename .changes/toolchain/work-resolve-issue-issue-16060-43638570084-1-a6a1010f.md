---
bump: minor
---

### Changed

- `/toolchain:check` and `/toolchain:lint` accept any covered ecosystem id as a filter: one with a
  record under `.claude/ecosystems/` at any layer, one inferred this run from the repo's build
  files, or one with a bundled default. Detection, `all` and the outside-every-ecosystem rule read
  the same set. The resolution ladder's new "Covered ecosystems" section defines it: before
  detection, a run infers each ecosystem whose build files it finds with no record or bundled
  default (a `Cargo.toml`, say) and names each inferred id with its globs. A filter that nothing
  covers is asked about, or, with nobody to ask, runs nothing and is reported. `/toolchain:check`
  still leaves the lint-only `yaml` and `cross-cutting` surfaces to `/toolchain:lint`.
- `/toolchain:lint` resolves an ecosystem with no record by inferring from the repo's build files
  before it falls back to the bundled default, as `/toolchain:check` already did.
