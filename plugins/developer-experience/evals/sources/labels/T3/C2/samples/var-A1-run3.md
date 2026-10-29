diff --git a/AGENTS.md b/AGENTS.md
index 329c313..0a4a4ad 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -5,5 +5,25 @@ is the account store, `tests/` holds `unittest` cases.
 
 ## Build and test
 
-- Test: `make test` (runs `scripts/run_tests.sh`).
-- Run the CLI: `python3 -m bfk.cli <command>`.
+- Test: `make test` (runs `scripts/run_tests.sh`, which is `python3 -m unittest discover -s tests -t .`).
+- Single test module: `python3 -m unittest tests.test_text` from the repo root.
+- Run the CLI: `python3 -m bfk.cli <command>` (`report`, `release`, `migrate`).
+- Run commands from the repo root; `scripts/seed_fixtures.py` uses relative paths.
+- `scripts/test.sh` duplicates `scripts/run_tests.sh`; use `make test`.
+
+## Code conventions
+
+- Python >= 3.11, standard library only: `pyproject.toml` has `dependencies = []`. Don't add third-party
+  packages.
+- Every external command goes through `bfk.proc.run()` (list of strings, captured text output). Don't
+  call `subprocess` anywhere else.
+- Read accounts through `bfk.store.load_accounts()`, not by opening `data/accounts.jsonl` directly.
+- New subcommands are argparse subparsers in `bfk/cli.py`; keep the module docstring's command list current.
+- Tests go in `tests/test_<module>.py` as `unittest.TestCase` subclasses.
+
+## Commands that need a human
+
+- `make release VERSION=x.y.z` / `bfk release` (and `scripts/release.ps1` on Windows) prompts on stdin
+  and then creates a git tag. Don't run it without the user's go-ahead; it blocks when no one answers.
+- `make seed` overwrites `data/accounts.jsonl`. It's also broken right now: `bfk.legacy` and
+  `data/legacy_seed.csv` don't exist. Don't run it.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
