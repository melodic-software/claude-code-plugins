---
bump: patch
---

### Fixed

- `prune-run-roots.py` also removes legacy run roots named without the leading dot: a directory directly under `$HOME` named `ev` followed by at least one more character (`ev8635`, `eval-runs`, `eval-13765`), under the same rules as a `.ev*` legacy root (a real directory holding a `claude-eval-*` sandbox directly inside it, nothing changed for 3 days, no process holding it, `chmod 700` on each `sealed/`), and only when it holds nothing but `claude-eval-*` sandboxes directly inside it. A matching directory with no sandbox, such as a user's `evolution`, or with anything beside its sandboxes, such as a user's `evals` folder, is reported and left, and a name outside the `.ev` and `ev` prefixes is never a candidate. Preflight's `stale_run_roots` lists these roots too.
