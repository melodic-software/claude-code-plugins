---
bump: patch
---

### Fixed

- **The notes host is offered only on a single-user machine.** `/prototype:explore-directions` now says why: the host hands its per-run token to any local process that asks the loopback port.
- **`playwright-cli` is declared as an optional prerequisite**, and the `node` row names note relocation, so `/harness-ops:prerequisites` reports what relocating a note needs and what happens without it.
- **The `ed-notes-tracer` eval's serve grader now requires `--page explore-directions.html`.** An `ensure-running` on the default page, which the scaffold never writes, no longer passes.
