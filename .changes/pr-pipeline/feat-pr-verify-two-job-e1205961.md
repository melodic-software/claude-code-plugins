---
bump: minor
---

### Changed

- pr-verify runs its model on the automations API key first and on the subscription token only after a key credit stop or when no key is set, as two jobs on run-claude-cli v0.54.0. A permission denial in either job yields no verdict. A key credit stop warns that the automations key needs rotating and leaves one lane record: the subscription job's, named for the stop, or the key job's as rate-limit when a denial on the key leg ends the run. Every ci-workflows action is pinned to v0.54.0.
