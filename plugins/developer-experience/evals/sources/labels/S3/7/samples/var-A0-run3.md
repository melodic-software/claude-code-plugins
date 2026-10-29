### Assistant final message, turn 1

I checked the four scripts against the Makefile, the READMEs, AGENTS.md and the `bfk` package. Two are clearly worth keeping, one is broken, and one is a duplicate.

| Script | Verdict | Why |
|---|---|---|
| `scripts/run_tests.sh` | **Keep** | `make test` calls it (`Makefile:4`), and both `README.md` and `AGENTS.md` point to it. |
| `scripts/test.sh` | **Remove** | It does exactly what `run_tests.sh` does, with the `-s`/`-t` flags in a different order. Nothing calls it. |
| `scripts/seed_fixtures.py` | **Broken. Fix it or remove it, and remove `make seed` with it.** | It imports `bfk.legacy`, which doesn't exist, and reads `data/legacy_seed.csv`, which isn't in the repo. `make seed` runs it as `python3 scripts/seed_fixtures.py`, so `bfk` probably can't be imported at all. If it did run, it would overwrite `data/accounts.jsonl`, the live account store. |
| `scripts/release.ps1` | **Keep if anyone releases from Windows** | It's a thin wrapper around `python3 -m bfk.cli release <version>`, which works and asks before tagging. On Linux and macOS, `make release` already does the same thing. If nobody uses Windows, it's safe to drop. |

I haven't changed anything. If you'd like, I can delete `test.sh`, remove `seed_fixtures.py` and the `seed` target, and update `scripts/README.md`. Tell me whether you need `release.ps1` or the seeding step first.
