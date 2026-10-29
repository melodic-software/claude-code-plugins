diff --git a/AGENTS.md b/AGENTS.md
index 329c313..f7522e4 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -5,5 +5,27 @@ is the account store, `tests/` holds `unittest` cases.
 
 ## Build and test
 
-- Test: `make test` (runs `scripts/run_tests.sh`).
-- Run the CLI: `python3 -m bfk.cli <command>`.
+- Test: `make test` (runs `scripts/run_tests.sh`, which is `python3 -m unittest discover -s tests -t .`
+  from the repo root). `scripts/test.sh` is a duplicate; use `make test`.
+- Run one test module: `python3 -m unittest tests.test_text` from the repo root.
+- Run the CLI: `python3 -m bfk.cli <command>` (`report`, `release`). Installed entry point is
+  `bfk = bfk.cli:main` (`pyproject.toml`).
+
+## Conventions
+
+- Standard library only, Python >= 3.11. Do not add entries to `dependencies` in `pyproject.toml`.
+- Tests use `unittest` (not pytest): files are `tests/test_*.py`, classes subclass `unittest.TestCase`,
+  and import from `bfk.*`.
+- Every external command goes through `bfk.proc.run_checked(cmd)` with `cmd` as a list of strings; don't call
+  `subprocess` directly elsewhere.
+- Read the account store through `bfk.store.load_accounts()`; pass `path=` to point it at a fixture in
+  tests instead of reading `data/accounts.jsonl`.
+- New CLI subcommands are `argparse` subparsers in `bfk/cli.py`; keep the logic in its own `bfk/` module
+  (as `release` does with `bfk/release.py`).
+
+## Commands to avoid
+
+- `make release VERSION=x.y.z` / `bfk release` / `scripts/release.ps1`: prompts on stdin, then creates
+  an annotated git tag. Only run when the user asks for a release.
+- `make seed` (`scripts/seed_fixtures.py`): overwrites `data/accounts.jsonl`, and is currently broken
+  (`bfk.legacy` and `data/legacy_seed.csv` do not exist). Don't run it.
