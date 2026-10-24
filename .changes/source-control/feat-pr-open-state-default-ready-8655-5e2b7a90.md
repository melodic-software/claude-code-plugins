---
bump: major
---

### Changed

- The bundled default of `pr_open_state` is now `ready` (was `draft`). A consumer who sets nothing gets `/source-control:pull-request create` opening the PR as a draft and then running `ready` on it, which flips it after its gates; a consumer opts into `draft` with the `userConfig` value or the repository's `docs/conventions/source-control.yaml`, and a request for a draft still wins over every level. An unattended run (a loop lane, a CI lane, a dispatched worker or orchestrator, any `create --pushed` run) now follows the resolved value like an attended run instead of always leaving a draft, and runs `ready --unattended`, so its holds (a `Draft:` body line, a superseded item, a failed gate) still leave the PR a draft. `create --pushed` takes `--draft '<reason>'` (a requested draft whose `Draft:` line names the reason) and `--hold '<line>'` (a `Hold:` line in the body the PR opens with, before any flip). The `pull-request` skill, its create reference, `config-resolution.md`, the README option row and the evals are updated to match.
