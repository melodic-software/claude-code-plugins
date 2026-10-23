---
bump: patch
---

### Added

- `/fleet:reach` names `fleet-converge <lane>` as the way to converge dotfiles on any fleet lane (bare name, drift-refusing, no approval; no lane means the current lane).

### Changed

- `/fleet:reach` lets `fleet-converge` start a distro that has already been launched, because it checks the cloud-init launch marker first; the `wsl -d` ban on a target's drift-convergence path otherwise stands.
