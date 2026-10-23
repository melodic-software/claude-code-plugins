---
bump: patch
---

### Changed

- pr-merge's `merge` job carries the head ref each untied pr-verify FAIL's verdict.json records, by artifact id, from one run to the next as the `pr-merge-head-refs` artifact (`.github/scripts/pr-merge/head-ref-map.mjs`), so the gate stops downloading every old-format untied FAIL on every sweep. Before the gate it reads the map from the newest scheduled or hand-started `pr-merge.yml` run on main other than itself, found the way the gate cursor is; after the gate a scheduled or hand-started run uploads that map plus its own downloads, for ids the artifact listing still lists. Only a run's own steps can upload its artifacts, and the map never passes through `actions/cache`. Any failure leaves no map, and the gate downloads as before. Permissions are unchanged.
