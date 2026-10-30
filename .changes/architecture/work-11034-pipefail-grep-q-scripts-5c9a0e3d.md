---
bump: patch
---

### Fixed

- **`map-deployment`'s collector no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `collect-deployment.sh` reads the comment-stripped Terraform and the compose layer list through process substitution, so under `set -o pipefail` a `helm_release` or a listed layer can no longer read as absent when grep exits before the producer finishes writing.
