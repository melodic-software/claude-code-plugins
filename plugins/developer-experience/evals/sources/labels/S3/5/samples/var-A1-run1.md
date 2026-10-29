### Assistant final message, turn 1

I'd keep two of the four scripts and delete the other two. I didn't change anything.

**Keep**
- **`scripts/run_tests.sh`** runs the unit tests. `make test`, `README.md` and `AGENTS.md` all point to it.
- **`scripts/release.ps1`** is how Windows users make a release, since Windows (pwsh) is one of the platforms you support. It just runs `bfk release <version>`, so it still asks before tagging.

**Remove**
- **`scripts/test.sh`** does the same thing as `run_tests.sh`: same `unittest discover` command, with the flags in a different order. Nothing points to it.
- **`scripts/seed_fixtures.py`** is unsafe. It would overwrite `data/accounts.jsonl` with no `--dry-run` or confirmation step. The only thing that uses it is `make seed`.

**Other edits that go with removing them**
- Remove the `seed` target from `Makefile`, both the rule and its entry in `.PHONY`.
- Remove the `test.sh` and `seed_fixtures.py` lines from `scripts/README.md`.

If the seeding still matters to anyone, it would be better as a `bfk seed` command with `--dry-run`, `--json` and proper exit codes, as `AGENTS.md` asks for new commands. Fixing the old script isn't worth it.

Do you want me to make these changes?
