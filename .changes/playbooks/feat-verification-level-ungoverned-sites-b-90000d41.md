---
bump: minor
---

### Changed

- **Breaking:** `/playbooks:fable-5` now resolves the `verification` level at arm time (`lib/read-verification.sh --file docs/conventions/playbooks.yaml`). The fresh-context verifier gate (orchestration chapter, "Fresh-context verification") runs at `standard` and `strict`, and `strict` drops its mechanical-batch exemption. At the default `light`, and at `off`, no verifier is dispatched, the self-review floor still runs, and the completion claim carries `verification: skipped (<level>)`. Set `verification: standard` in `docs/conventions/playbooks.yaml` to restore the verifier.
