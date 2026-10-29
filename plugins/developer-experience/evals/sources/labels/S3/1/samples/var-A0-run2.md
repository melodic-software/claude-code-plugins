### Assistant final message, turn 1

Of the four scripts, `run_tests.sh` is the only one I'd keep without question. I worked this out by reading the files and searching for references. I couldn't run anything because shell access is blocked in this session, so I haven't actually run `make test` or `seed_fixtures.py`.

| Script | Verdict | Why |
|---|---|---|
| `scripts/run_tests.sh` | **Keep** | `make test` uses it (`Makefile:4`), and `README.md` and `AGENTS.md` both point to it. |
| `scripts/test.sh` | **Consolidate into `run_tests.sh`** | It does the same thing as `run_tests.sh`; only the order of the `unittest discover` flags differs. Nothing refers to it. |
| `scripts/seed_fixtures.py` | **Remove or fix** | It looks broken. It imports `bfk.legacy.normalize_row` and reads `data/legacy_seed.csv`, and neither exists in the repo. It also overwrites `data/accounts.jsonl` without asking. `make seed` is the only thing that calls it. |
| `scripts/release.ps1` | **Keep** | It just runs `python3 -m bfk.cli release $Version`, the same as `make release`. Keep it for anyone who tags releases on Windows without `make`. |

**Recommended cleanup:**
- Fold `test.sh` into `run_tests.sh` and delete the duplicate.
- Delete `seed_fixtures.py` and the `seed` target in the `Makefile`, unless the legacy CSV import is still needed. If it is, `bfk/legacy.py` and the CSV need to be restored first.
- Leave `release.ps1`, the `bfk` CLI it calls, and the `test` target in the `Makefile` alone.
- Update `scripts/README.md` to match. It currently lists `test.sh` and `run_tests.sh` as if they were separate scripts.

I haven't changed anything. Do you want me to make these edits?
