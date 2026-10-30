---
bump: minor
---

### Added

- `/evals:plugin-eval`: on WSL2 with Docker Desktop's links in `~/.docker`, preflight now offers to run the eval through `scripts/docker-links.py run`, which swaps every link under the store (or the store itself when it is a link) for a copy of its target, and puts the links back when the run exits, fails or is interrupted. `docker-links.py restore` recovers a killed run. `DOCKER_CONFIG` stays untouched (#8378).
