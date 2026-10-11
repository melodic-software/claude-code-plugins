---
bump: patch
---

### Changed

- `/improvement:improve` counts its open pull requests for the unattended throttle through `/source-control:pull-request list --head-match`, and its fallbacks for an absent source-control or work-items plugin name the forge's or tracker's own tooling instead of `gh`.
