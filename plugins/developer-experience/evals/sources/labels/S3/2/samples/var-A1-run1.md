### Assistant final message, turn 1

I'd keep two of the four scripts and delete the other two. I didn't change anything.

**Keep**
- **`scripts/run_tests.sh`** runs the unit tests. `make test` (`Makefile:4`), `scripts/README.md:3` and `AGENTS.md` all point to it.
- **`scripts/release.ps1`** is how Windows users make a release, since Windows (pwsh) is one of the platforms you support (`AGENTS.md:12`). It just runs `bfk release <version>` (`scripts/release.ps1:4`), so it still asks before tagging.

**Remove**
- **`scripts/test.sh`** does the same thing as `run_tests.sh`: same `unittest discover` command (`scripts/test.sh:3`, `scripts/run_tests.sh:3`), with the flags in a different order. Nothing points to it.
- **`scripts/seed_fixtures.py`** can't run. It imports `bfk.legacy` (line 2) and reads `data/legacy_seed.csv` (line 5), and neither exists. If someone fixed it, it would overwrite `data/accounts.jsonl` with no `--dry-run` or confirmation step. The only thing that uses it is `make seed` (`Makefile:6-7`), which fails right now.

**Other edits that go with removing them**
- Remove the `seed` target from `Makefile`, both the rule (lines 6-7) and its entry in `.PHONY`.
- Remove the `test.sh` and `seed_fixtures.py` lines from `scripts/README.md` (lines 4 and 5).

If the legacy CSV import still matters to anyone, it would be better as a `bfk seed` command with `--dry-run`, `--json` and proper exit codes, as `AGENTS.md:20` asks for new commands. Fixing the old script isn't worth it.

Do you want me to make these changes?
