---
bump: patch
---

### Added

- `/fleet:reach` names `fleet-converge <lane>`, run by its bare name, as the way to converge dotfiles on any fleet lane, with a dated pointer to the dotfiles design record for what it checks.

### Changed

- `/fleet:reach` allows a distro start that `fleet-converge` makes itself as the one exception to the `wsl -d` ban on a target's drift-convergence path; an agent never runs `wsl -d` on its behalf.
