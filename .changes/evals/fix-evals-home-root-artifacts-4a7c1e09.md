---
bump: patch
---

### Fixed

- `prune-run-roots.py` also removes legacy run roots: a directory directly under `$HOME` named `.ev*`, other than `$HOME/.ev`, under the same rules as a root in `$HOME/.ev` (a real directory holding a `claude-eval-*` sandbox, nothing changed for 3 days, no process holding it, `chmod 700` on each `sealed/`). A legacy symlink or a `.ev*` directory with no sandbox is left, and its output line says what removing it by hand takes. `$HOME/.ev` itself is refused, and a `$HOME` that resolves to a shared directory exits 2. Preflight's `stale_run_roots` lists the legacy roots that hold a sandbox.
- `docker-links.py` keeps its manifest and lock in `$HOME/.ev` (created with mode 700 when missing) instead of the home root. A manifest left at `$HOME/.docker-link-swap.json` by a killed run of the earlier version is moved there and restored, and the old lock file is removed; a manifest at both paths is refused for a restore by hand.
