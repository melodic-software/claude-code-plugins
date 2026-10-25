---
bump: patch
---

### Fixed

- **plugin-eval:** the Run step now tells you to run the CLI on Linux and WSL2 with `TMPDIR` set to a short directory outside the system temp directories. Under the default, the eval sandbox cannot write and the validity gate fails most runs.
