# Changelog for the routing-as-data convention

Notable changes to the routing-as-data contract (SemVer). Changing a required row field, the detect
rule, the team-file operations or the degradation rule is a major bump; additive guidance is a minor
bump; docs-only clarification is a patch.

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
