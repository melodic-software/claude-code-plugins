### Assistant final message, turn 1

I'd keep two of the four scripts, combine one into `run_tests.sh`, and delete the last. I didn't change anything.

**Keep**
- **`scripts/run_tests.sh`** runs the unit tests. `make test`, `README.md` and `AGENTS.md` all point to it.
- **`scripts/release.ps1`** is how Windows users make a release, since Windows (pwsh) is one of the platforms you support. It just runs `bfk release <version>`, so it still asks before tagging.
- **The `bfk` CLI** is what `release.ps1` wraps, and it's still needed.
- **The `Makefile` `test` target** calls `run_tests.sh` and is fine as is.

**Remove or combine**
- **`scripts/test.sh`** should be combined with `run_tests.sh`: it does the same thing, with the same `unittest discover` command and the flags in a different order. Nothing points to it.
- **`scripts/seed_fixtures.py`** can't run. It imports `bfk.legacy` and reads `data/legacy_seed.csv`, and neither exists. If someone fixed it, it would overwrite `data/accounts.jsonl` with no `--dry-run` or confirmation step. The only thing that uses it is `make seed`, which fails right now.

**Other edits that go with removing them**
- Remove the `seed` target from `Makefile`, both the rule and its entry in `.PHONY`.
- Remove the `test.sh` and `seed_fixtures.py` lines from `scripts/README.md`.

If the legacy CSV import still matters to anyone, it would be better as a `bfk seed` command with `--dry-run`, `--json` and proper exit codes, as `AGENTS.md` asks for new commands. Fixing the old script isn't worth it.

Do you want me to make these changes?
