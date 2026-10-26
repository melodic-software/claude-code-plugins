---
bump: minor
---

### Added

- `scripts/group-findings.mjs [--by <field>[,<field>...]] [--since <UTC ISO-8601>] [--rows]` runs `buffer.sh read` and prints the findings buffer grouped by the named top-level fields (default `producer`): a first line naming the keys, then each group with its row count, its occurrence count (distinct `source_id`) and its members, most occurrences first. `--since` cuts exactly, fraction included, and row values print with control, format (bidirectional and zero-width included) and separator characters escaped.

### Changed

- `/corrections:codify group` takes `--by`, runs `group-findings.mjs`, shows the field groups, then groups by mistake, and names the keys of both groupings.
