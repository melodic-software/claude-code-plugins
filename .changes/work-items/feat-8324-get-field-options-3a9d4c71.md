---
bump: minor
---

### Added

- The tracker seam's `get-field-options --field <name-or-id> [--repo <owner>/<repo>]` verb reads
  the options of one single-select issue field, so a caller such as planning's Work size can use a
  tracker's own size values. The GitHub adapter implements it from the organization issue-field
  listing `set-fields` validates against; a field the organization lacks prints an empty
  `options` list and exits 0, and an adapter that declares no `get-field-options` key exits 6
  (unsupported). The other bundled adapters' manifests, the adapter generator's verb list and the
  adapter-spec reference now declare the verb too (`false` outside GitHub).
