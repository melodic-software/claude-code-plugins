# Changelog for the routing-as-data convention

Notable changes to the routing-as-data contract (SemVer). Changing a required row field, the detect
rule, the team-file operations or the degradation rule is a major bump; additive guidance is a minor
bump; docs-only clarification is a patch.

## [2.0.0] - 2026-10-22

- Team layer, breaking: `routing.rows` may re-rank or override an existing row, and may add a row
  only when its id matches a bundled row or an installed plugin or skill. A team file may not add a
  new `kind: tool` row. A team row that reuses a bundled id may not change that row's `kind`,
  `detect` or `account`. A row that breaks any of these rules is dropped, and the disclosure names
  it. Each adopter's team-file schema `description` states the same rules.
- Adopters: `user-experience` adopts the 2.0.0 limits, with a deviation: its schema `description`
  states only the two add limits, while its code enforces the third. `user-interface` records a
  deviation, applying team-added rows with no id limit, no `kind: tool` refusal and no restriction
  on a bundled-id override, tracked in #8788.

## [1.0.1] - 2026-10-09

- Adopters: `user-experience` moves from Planned to Adopts (group field `job`, first team-layer
  implementer).

## [1.0.0] - 2026-10-09

- Route rows: versioned file with a `note`, closed schema, ranks 1..n per group with the project as
  implicit rank 0, `kind`, `account` and `status` enums, slash-invocation ids for `kind: skill`, and
  the `pointer` rule (none on own-marketplace skill rows, required `https://` elsewhere).
- Detection by name: bare detects resolve to the detecting plugin's own marketplace through its
  `claude plugin list --json` record, with a disclosed name-match fallback and an `uncertain` map.
- Team layer: `<home>/<plugin>.yaml` through the convention-home pointer, one `routing` key with
  `rows`, `disable` and `deny`, combined by key, schema shipped inside the plugin.
- Degradation: built-in routes with disclosure when the team file is missing, malformed or
  unreadable; `deny` fails open, and a hard block belongs in managed settings or permissions.
- Adopter: `user-interface`.
