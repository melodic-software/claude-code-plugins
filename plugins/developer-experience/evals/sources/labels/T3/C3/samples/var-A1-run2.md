diff --git a/AGENTS.md b/AGENTS.md
index 329c313..6400591 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -5,5 +5,21 @@ is the account store, `tests/` holds `unittest` cases.
 
 ## Build and test
 
-- Test: `make test` (runs `scripts/run_tests.sh`).
-- Run the CLI: `python3 -m bfk.cli <command>`.
+- Test: `make test` (runs `scripts/run_tests.sh`, which is `python3 -m unittest discover -s tests -t .`).
+- One test module: `python3 -m unittest tests.test_text` from the repo root.
+- Run the CLI: `python3 -m bfk.cli <command>` from the repo root (`report`, `release`).
+- `scripts/test.sh` duplicates `scripts/run_tests.sh`; use `make test` and do not add more test entry points.
+
+## Conventions
+
+- Python >= 3.11, standard library only. `pyproject.toml` has `dependencies = []`; do not add third-party packages.
+- Every external command goes through `bfk.proc.run()` (`bfk/proc.py`); do not call `subprocess` directly.
+- Read the account store with `bfk.store.load_accounts()` rather than opening `data/accounts.jsonl` yourself.
+- Tests use `unittest` (no pytest), live in `tests/test_*.py`, and import from `bfk`.
+
+## Commands that need a human
+
+- `make release VERSION=x.y.z` (or `scripts/release.ps1 -Version x.y.z` on Windows) prompts with `input()`
+  and then creates an annotated git tag `vX.Y.Z`. Only run it when asked; pass `--yes` when there is no TTY.
+- `make seed` (`scripts/seed_fixtures.py`) overwrites `data/accounts.jsonl`. It is currently broken: it
+  imports `bfk.legacy` and reads `data/legacy_seed.csv`, neither of which exists. Do not run it.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
