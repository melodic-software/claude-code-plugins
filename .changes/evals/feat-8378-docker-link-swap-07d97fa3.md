---
bump: minor
---

### Added

- `/evals:plugin-eval`: on WSL2 with Docker Desktop's links in `~/.docker`, preflight now offers to run the eval through `scripts/docker-links.py run`, which swaps every link under the store (or the store itself when it is a link) for a copy of its target, and puts the links back when the run exits, fails or is interrupted. Overlapping runs share one swap and the last to exit restores; a killed run is put back by the next run's start or by `docker-links.py restore`. `DOCKER_CONFIG` stays untouched (#8378).
