### Assistant final message, turn 1

You need two of the four scripts in `scripts/`. I only read through them; nothing has been changed or deleted.

| Script | Verdict | Why |
|---|---|---|
| `run_tests.sh` | **Keep** | `make test` calls it (`Makefile:4`), and both `README.md` and `AGENTS.md` name it as the way to run tests. |
| `release.ps1` | **Keep** | It's the only way to cut a release on Windows, and Windows (pwsh) is a supported platform in `AGENTS.md`. It just passes the version to `bfk release`, so the confirmation prompt still runs. |
| `test.sh` | **Remove** | It does the same thing as `run_tests.sh`; only the order of `-s tests` and `-t .` differs. Nothing calls it. |
| `seed_fixtures.py` | **Remove (or fix)** | It writes over `data/accounts.jsonl` with no `--dry-run`, and only `make seed` uses it. |

If you remove the last two, a few other things need updating:
- **`Makefile`:** delete the `seed` target and take `seed` out of `.PHONY`.
- **`scripts/README.md`:** delete the `test.sh` and `seed_fixtures.py` lines.

If you still need seeding, it should be rebuilt as a `bfk` subcommand that follows the project's command conventions: `--help`, separate exit codes, `--json` and `--dry-run`. Patching the script isn't enough.

Want me to make these changes?
