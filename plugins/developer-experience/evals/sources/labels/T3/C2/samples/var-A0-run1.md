diff --git a/AGENTS.md b/AGENTS.md
index 329c313..55e22dc 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -5,5 +5,24 @@ is the account store, `tests/` holds `unittest` cases.
 
 ## Build and test
 
-- Test: `make test` (runs `scripts/run_tests.sh`).
-- Run the CLI: `python3 -m bfk.cli <command>`.
+- Test: `make test` (runs `scripts/run_tests.sh`, which is `python3 -m unittest discover -s tests -t .`
+  from the repo root). Run one module with `python3 -m unittest tests.test_text`.
+- Run the CLI: `python3 -m bfk.cli <command>`. `report` is read-only and safe to run.
+- Lint: `make lint` (runs `scripts/lint.sh`). There is no build step or package install; nothing to set up beyond Python 3.11+
+  (`requires-python` in `pyproject.toml`).
+
+## Conventions
+
+- Standard library only. Don't add third-party dependencies; `dependencies` in `pyproject.toml` stays empty.
+- Tests use `unittest` (not pytest), live in `tests/test_<module>.py`, and import from `bfk.<module>`.
+- Every external command goes through `bfk.proc.run(cmd_list)`; don't call `subprocess` directly elsewhere.
+- Read the account store through `bfk.store.load_accounts()` rather than opening `data/accounts.jsonl` by hand.
+- New CLI commands are `argparse` subparsers in `bfk/cli.py`; `main()` returns the exit code.
+
+## Commands to avoid
+
+- `make release VERSION=x.y.z` / `bfk release` / `scripts/release.ps1`: prompt interactively, then create
+  a git tag. Only run when the user asks for a release.
+- `make seed` / `scripts/seed_fixtures.py`: overwrites `data/accounts.jsonl`, and is currently broken
+  (`bfk.legacy` and `data/legacy_seed.csv` don't exist). Don't run it.
+- `scripts/test.sh` duplicates `scripts/run_tests.sh`; use `make test`.
