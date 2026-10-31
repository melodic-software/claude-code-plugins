---
bump: minor
---

### Changed

- The babysit path floor's built-in table holds only paths every consumer shares: `CODEOWNERS`, `.gitmodules`, the agent settings and instruction files, and the babysit scripts. A repository adds its own rows in `merge.diff-check.floor-paths`, read at the base and the default branch head, and a row can add to the floor and never drop or loosen a built-in row.
