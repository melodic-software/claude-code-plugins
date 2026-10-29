### Assistant final message, turn 1

Of the four scripts, `run_tests.sh` is the only one I'd keep without question. I worked this out by reading the files and searching for references. I couldn't run anything because shell access is blocked in this session, so I haven't actually run `make test` or `seed_fixtures.py`.

| Script | Verdict | Why |
|---|---|---|
| `scripts/run_tests.sh` | **Keep** | `make test` uses it (`Makefile:4`), and `scripts/README.md:3` and `AGENTS.md` both point to it. |
| `scripts/test.sh` | **Remove** | It does the same thing as `run_tests.sh`; only the order of the `unittest discover` flags differs (`scripts/test.sh:3`, `scripts/run_tests.sh:3`). Nothing refers to it. |
| `scripts/seed_fixtures.py` | **Remove or fix** | It looks broken. It imports `bfk.legacy.normalize_row` (`scripts/seed_fixtures.py:2`) and reads `data/legacy_seed.csv` (`scripts/seed_fixtures.py:5`), and neither exists in the repo. It also overwrites `data/accounts.jsonl` without asking (`scripts/seed_fixtures.py:9`). `make seed` (`Makefile:6-7`) is the only thing that calls it. |
| `scripts/release.ps1` | **Your call** | It just runs `python3 -m bfk.cli release $Version` (`scripts/release.ps1:4`), the same as `make release` (`Makefile:9`). Keep it only if someone tags releases on Windows without `make`. |

**Recommended cleanup:**
- Delete `test.sh`.
- Delete `seed_fixtures.py` and the `seed` target in the `Makefile`, unless the legacy CSV import is still needed. If it is, `bfk/legacy.py` and the CSV need to be restored first.
- Decide about `release.ps1` based on whether anyone releases from Windows.
- Update `scripts/README.md` to match. Lines 3-4 list `test.sh` and `run_tests.sh` as if they were separate scripts.

I haven't changed anything. Do you want me to make these edits?
