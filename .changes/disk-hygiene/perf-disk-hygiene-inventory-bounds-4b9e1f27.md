---
bump: minor
---

### Added

- Policy overlays take `additional_inventory_bounded_stores`, `{glob, reason}` entries appended to the baseline `inventory_bounded_stores` list of known-large tool stores. `inventory` takes the `--policy`, `--user-policy` and `--project-dir` flags `scan` takes, so every policy layer reaches it.

### Fixed

- `hygiene.py inventory` no longer walks known-large tool stores entry by entry. Each store the policy names (npm, NuGet, Cargo, Go, Gradle and Maven caches, XDG and macOS per-tool caches, Claude Code transcripts, plugin caches and logs by default) is one row with a `coverage` field, its size summed under a per-store and a per-run entry budget, so a home inventory finishes in bounded time. A store a classifier recognizes keeps its category and disposition. The summary lists the bounded rows, counts those whose size is a lower bound, and sets `fully_inventoried` false while any bounded or not-walked row exists.
- `scan --root-children --root-child <file>` admits a regular file on a home or any other non-volume-root target instead of withholding it as `not-a-directory`, so folders and loose root files go into one snapshot and one plan. The file passes the same link, cloud-placeholder, virtual-disk, protected-name and mount checks as a directory, and other non-directory types are withheld as `not-regular-file-or-directory`.
