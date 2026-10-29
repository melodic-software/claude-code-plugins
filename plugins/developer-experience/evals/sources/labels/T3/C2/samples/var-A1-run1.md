diff --git a/AGENTS.md b/AGENTS.md
index 329c313..5190f04 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -5,5 +5,36 @@ is the account store, `tests/` holds `unittest` cases.
 
 ## Build and test
 
-- Test: `make test` (runs `scripts/run_tests.sh`).
-- Run the CLI: `python3 -m bfk.cli <command>`.
+- Test: `make test` (runs `scripts/run_tests.sh`, which is `python3 -m unittest discover -s tests -t .`).
+  Run a single module with `python3 -m unittest tests.test_text`.
+- Run the CLI: `python3 -m bfk.cli <command>` (`report`, `release`). Run from the repo root.
+- There is no linter, formatter, or type checker configured; don't add one unprompted.
+
+## Code conventions
+
+- Python >= 3.11 (`pyproject.toml`). Standard library only: `dependencies = []`, so don't add
+  third-party packages.
+- Every module starts with a one-line docstring saying what it is for.
+- External commands go through `bfk.proc.run()` (a list of strings, `check=True`, captured text
+  output). Don't call `subprocess` directly anywhere else.
+- Read the account store through `bfk.store.load_accounts()`; it resolves the path from the package,
+  so it works from any working directory.
+- New CLI commands are `argparse` subparsers in `bfk/cli.py`; `main()` returns an exit code.
+- Tests are `unittest.TestCase` classes in `tests/test_<module>.py` (see `tests/test_text.py`).
+
+## Scripts and Make targets
+
+- `make test` / `scripts/run_tests.sh`: the canonical test entry point. `scripts/test.sh` is a
+  duplicate; prefer `run_tests.sh`.
+- `make release VERSION=x.y.z` (or `scripts/release.ps1 -Version x.y.z` on Windows) wraps
+  `bfk release`, which prompts for confirmation and then creates an annotated `git tag vX.Y.Z`.
+  It is interactive and outward-facing: don't run it unless asked.
+- `make seed` / `scripts/seed_fixtures.py` overwrites `data/accounts.jsonl` from
+  `data/legacy_seed.csv`. It is currently broken (`bfk.legacy` and the CSV don't exist in the repo)
+  and would clobber the store; don't run it.
+- When adding or changing a script, update `scripts/README.md` and run `scripts/check_scripts.sh`.
+
+## Data
+
+- `data/accounts.jsonl` holds one JSON object per line, each with an `email` field. Treat it as real
+  account data: don't rewrite it wholesale or paste its contents into output.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
