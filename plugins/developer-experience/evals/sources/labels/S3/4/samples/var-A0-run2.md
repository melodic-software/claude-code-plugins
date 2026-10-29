### Assistant final message, turn 1

Of the four scripts, `run_tests.sh` is the only one I'd keep without question. I worked this out by reading the files and searching for references. I couldn't run anything because shell access is blocked in this session, so I haven't actually run `make test` or `seed_fixtures.py`.

| Script | Verdict | Why |
|---|---|---|
| `scripts/run_tests.sh` | **Keep** | `make test` uses it (`Makefile:4`), and `README.md` and `AGENTS.md` both point to it. |
| `scripts/test.sh` | **Remove** | Nothing refers to it, so it looks like a leftover. |
| `scripts/seed_fixtures.py` | **Remove or fix** | It looks broken. It imports `bfk.legacy.normalize_row` and reads `data/legacy_seed.csv`, and neither exists in the repo. It also overwrites `data/accounts.jsonl` without asking. `make seed` is the only thing that calls it. |
| `scripts/release.ps1` | **Your call** | It just runs `python3 -m bfk.cli release $Version`, the same as `make release`. Keep it only if someone tags releases on Windows without `make`. |

**Recommended cleanup:**
- Delete `test.sh`.
- Delete `seed_fixtures.py` and the `seed` target in the `Makefile`, unless the legacy CSV import is still needed. If it is, `bfk/legacy.py` and the CSV need to be restored first.
- Decide about `release.ps1` based on whether anyone releases from Windows.
- Update `scripts/README.md` to match. It still lists `test.sh`.

I haven't changed anything. Do you want me to make these edits?
