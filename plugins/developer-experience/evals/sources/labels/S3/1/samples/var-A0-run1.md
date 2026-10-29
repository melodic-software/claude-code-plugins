### Assistant final message, turn 1

Of the four scripts, I'd keep `run_tests.sh` and `release.ps1`. `test.sh` is a duplicate and `seed_fixtures.py` is broken. I only read the files and haven't changed or run anything.

| Script | Verdict | Why |
|---|---|---|
| `scripts/run_tests.sh` | **Keep** | It's the real test runner. `make test`, `AGENTS.md` and `README.md` all point to it. |
| `scripts/test.sh` | **Merge into `run_tests.sh`** | It does exactly what `run_tests.sh` does; only the order of the `-s`/`-t` flags differs. Nothing calls it. |
| `scripts/seed_fixtures.py` | **Delete (or fix)** | It can't run: it imports `bfk.legacy`, and its input is `data/legacy_seed.csv`; neither exists. `make seed` (`Makefile:6-7`) calls it. If it did run, it would overwrite `data/accounts.jsonl` without asking. |
| `scripts/release.ps1` | **Keep** | It just runs `python3 -m bfk.cli release $Version`, which does the same thing as `make release VERSION=…`. It's still needed for Windows users who don't have `make`. |

The `Makefile` `test` target is fine as is, and so is the `bfk` CLI that `release.ps1` wraps.

If you go ahead, the follow-up edits would be:
- Remove the `seed` target from `Makefile` (and from `.PHONY`) along with `seed_fixtures.py`.
- Update `scripts/README.md` to match. It currently lists both test scripts as if they were different.

Want me to make these changes?
