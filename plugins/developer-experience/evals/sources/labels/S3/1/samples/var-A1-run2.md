### Assistant final message, turn 1

You need two of the four scripts in `scripts/`. I only read through them; nothing has been changed or deleted.

| Script | Verdict | Why |
|---|---|---|
| `run_tests.sh` | **Keep** | `make test` calls it (`Makefile:4`), and both `README.md` and `AGENTS.md` name it as the way to run tests. |
| `release.ps1` | **Keep** | It's the only way to cut a release on Windows, and Windows (pwsh) is a supported platform in `AGENTS.md`. It just passes the version to `bfk release`, so the confirmation prompt still runs. |
| `test.sh` | **Merge into `run_tests.sh`** | It does the same thing as `run_tests.sh`; only the order of `-s tests` and `-t .` differs. Nothing calls it. |
| `seed_fixtures.py` | **Remove (or fix)** | It's already broken. It imports `bfk.legacy` and reads `data/legacy_seed.csv`, and neither exists in the repo, so `make seed` would fail on import. It also writes over `data/accounts.jsonl` with no `--dry-run`. |
| `Makefile` `test` target | **Leave as is** | It is the entry point to `run_tests.sh`, so it is still needed. |
| `Makefile` `seed` target | **Drop** | It only exists to call `seed_fixtures.py`, so it goes with it. |
| `bfk` CLI | **Still needed** | `release.ps1` and `make release` both call it. |

If you merge `test.sh` and remove `seed_fixtures.py`, a few other things need updating:
- **`Makefile`:** delete the `seed` target and take `seed` out of `.PHONY`.
- **`scripts/README.md`:** delete the `test.sh` and `seed_fixtures.py` lines.

If you still need seeding from the legacy CSV, it should be rebuilt as a `bfk` subcommand that follows the project's command conventions: `--help`, separate exit codes, `--json` and `--dry-run`. Patching the script isn't enough, because the module and CSV it depends on are both missing.

Want me to make these changes?
