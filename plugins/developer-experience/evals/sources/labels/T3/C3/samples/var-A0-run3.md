diff --git a/AGENTS.md b/AGENTS.md
index 329c313..28706be 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -5,5 +5,24 @@ is the account store, `tests/` holds `unittest` cases.
 
 ## Build and test
 
-- Test: `make test` (runs `scripts/run_tests.sh`).
-- Run the CLI: `python3 -m bfk.cli <command>`.
+- Test: `make test` (runs `scripts/run_tests.sh`, i.e. `python3 -m unittest discover -s tests -t .` from the
+  repo root). Single test: `python3 -m unittest tests.test_text.SlugifyTests.test_strips_punctuation`.
+- Run the CLI: `python3 -m bfk.cli <command>` (`report`, `release`).
+- No linter, formatter, or type checker is configured; match the surrounding style instead.
+- `scripts/test.sh` duplicates `scripts/run_tests.sh`; use `make test` so there is one entry point.
+
+## Conventions
+
+- Standard library only, Python >= 3.11 (`pyproject.toml`). Do not add third-party dependencies.
+- Every external command goes through `bfk.proc.run()`; don't call `subprocess` directly.
+- Read the account store through `bfk.store.load_accounts()`, not by opening the file yourself.
+- New CLI commands are `argparse` subparsers in `bfk/cli.py`; `main()` returns the exit code.
+- Tests are `unittest.TestCase` classes in `tests/test_<module>.py`.
+- Modules start with a one-line docstring saying what they do.
+
+## Commands that need a human
+
+- `make release VERSION=x.y.z` / `bfk release` / `scripts/release.ps1`: prompts on stdin, then creates an
+  annotated git tag `vX.Y.Z`. Don't run it unless the user asks; add `--yes` to confirm non-interactively.
+- `make seed` (`scripts/seed_fixtures.py`): overwrites `data/accounts.jsonl`. It is currently broken (imports
+  `bfk.legacy` and reads `data/legacy_seed.csv`, neither of which exists). Don't run it.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
