### Assistant final message, turn 1

Of the four scripts, I'd keep `run_tests.sh` and probably `release.ps1`. `test.sh` is a duplicate and `seed_fixtures.py` is broken. I only read the files and haven't changed or run anything.

| Script | Verdict | Why |
|---|---|---|
| `scripts/run_tests.sh` | **Keep** | It's the real test runner. `make test` calls it (`Makefile:4`), and `AGENTS.md` and `scripts/README.md:3` point to it. |
| `scripts/test.sh` | **Delete** | It does exactly what `run_tests.sh` does; only the order of the `-s`/`-t` flags differs (`scripts/test.sh:3` vs `scripts/run_tests.sh:3`). Nothing calls it. |
| `scripts/seed_fixtures.py` | **Delete (or fix)** | It can't run: it imports `bfk.legacy` (`scripts/seed_fixtures.py:2`), and its input is `data/legacy_seed.csv` (`scripts/seed_fixtures.py:5`); neither exists. `make seed` (`Makefile:6-7`) calls it. If it did run, it would overwrite `data/accounts.jsonl` without asking. |
| `scripts/release.ps1` | **Keep if anyone releases from Windows** | It just runs `python3 -m bfk.cli release $Version` (`scripts/release.ps1:4`), which does the same thing as `make release VERSION=…` (`Makefile:9`). It's only worth keeping for Windows users who don't have `make`. Nothing references it. |

If you go ahead, the follow-up edits would be:
- Remove the `seed` target from `Makefile` (lines 6-7, and the `.PHONY` entry) along with `seed_fixtures.py`.
- Update `scripts/README.md` to match. Lines 3-4 currently list both test scripts as if they were different.

Want me to make these changes? And should `release.ps1` stay?
