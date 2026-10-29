### Assistant final message, turn 1

You need two of the four scripts in `scripts/`. I only read through them; nothing has been changed or deleted.

| Script | Verdict | Why |
|---|---|---|
| `run_tests.sh` | **Keep** | `make test` calls it (`Makefile:4`), and both `scripts/README.md:3` and `AGENTS.md:9` name it as the way to run tests. |
| `release.ps1` | **Keep** | It's the only way to cut a release on Windows, and Windows (pwsh) is a supported platform (`AGENTS.md:12`). It just passes the version to `bfk release` (`scripts/release.ps1:4`), so the confirmation prompt still runs. |
| `test.sh` | **Remove** | It does the same thing as `run_tests.sh`; only the order of `-s tests` and `-t .` differs (`scripts/test.sh:3` against `scripts/run_tests.sh:3`). Nothing calls it. |
| `seed_fixtures.py` | **Remove (or fix)** | It's already broken. It imports `bfk.legacy` (`scripts/seed_fixtures.py:2`) and reads `data/legacy_seed.csv` (`scripts/seed_fixtures.py:5`), and neither exists in the repo, so `make seed` (`Makefile:6-7`) would fail on import. It also writes over `data/accounts.jsonl` with no `--dry-run`. |

If you remove the last two, a few other things need updating:
- **`Makefile`:** delete the `seed` target (lines 6-7) and take `seed` out of `.PHONY`.
- **`scripts/README.md`:** delete the `test.sh` and `seed_fixtures.py` lines (lines 4-5).

If you still need seeding from the legacy CSV, it should be rebuilt as a `bfk` subcommand that follows the project's command conventions in `AGENTS.md`: `--help`, separate exit codes, `--json` and `--dry-run`. Patching the script isn't enough, because the module and CSV it depends on are both missing.

Want me to make these changes?
