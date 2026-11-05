---
bump: minor
---

### Changed

- `plugin-eval` runs the Docker link swap on WSL2 without asking when `DOCKER_CONFIG` is unset, every `~/.docker` link points under `/mnt/`, and no link target holds a `tls/` directory, and says so in the run report. When any condition fails it refuses and names the links, as before.
- `docker-links.py` refuses the swap with exit 2, changing nothing, when a `tls` directory sits under any link's target, and names that directory.
- The `sandbox-docker-symlink` eval case accepts running the CLI through the link swap as resolving the links.
