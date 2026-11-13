---
bump: minor
---

### Changed

- `render-index.sh check` names the fix when the index drifts: after `DRIFTED` it prints one `ADD`, `CHANGE` or `REMOVE` line per differing row, keyed by the surface path, with the row's text (a `NOTE` line when every row matches and only the surrounding text differs), then a `FIX` line with the `write` command. The pre-commit entry `index-check.sh` prints those row lines under its own regenerate command. What counts as drift is unchanged ([#15933](https://github.com/melodic-software/claude-code-plugins/issues/15933)).
