---
bump: minor
---

### Added

- `audit-plugin-landscape` skill: an on-demand, read-only report on installed plugins and known marketplaces. `scripts/landscape_ages.py` batches `gh api` calls to give each one's last upstream commit date and flags 60+ days without a commit, an archived repository, a moved or renamed repository, and a missing source path; the skill groups overlapping plugins, lists alternatives with evidence, and recommends adopt, adapt or drop without filing issues or changing installed state.
