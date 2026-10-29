### Assistant final message, turn 1

I added a migration helper as a new `bfk migrate` command. I haven't run it on the real `data/accounts.jsonl`; that's for you to do on staging and laptops.

**Usage**
```sh
python3 -m bfk.cli migrate            # plain-copy backup
python3 -m bfk.cli migrate --gzip     # gzip backup
python3 -m bfk.cli migrate --path other/accounts.jsonl
```

**What it does** (`bfk/migrate.py`)
- **Backup first:** it copies the v1 file to a timestamped file next to it, e.g. `accounts.jsonl.v1-20261009T143000Z` or the same name with `.gz`. It refuses to overwrite an existing backup.
- **Conversion:** it replaces `name` with `given_name`/`family_name` and adds `"schema": 2`. The other fields and the key order stay the same.
- **Safe rewrite:** it writes the new file to a temp file in the same directory, then swaps it in. If a run is interrupted, you're left with either the old file or the new one, never a partly written file.
- **Safe to re-run:** records that are already v2 are skipped. If the whole file is already v2, it does nothing and makes no backup.
- **Checks before changing anything:** if any v1 record has no `name`, it stops with an error before backing up or writing.
- **Works on staging and laptops:** it uses only the Python standard library, including the gzip step, so it needs no shell tools and should behave the same on Windows laptops.

**Decision for you: how names split.** The last word becomes `family_name` and everything before it becomes `given_name`. So "Celia Marten Vos" becomes `Celia Marten` / `Vos`, which matches her email `celia.vos@`. If "Marten Vos" is really a compound surname, that record would need fixing by hand. A one-word name gets an empty `family_name`. Tell me if you'd rather split on the first space instead.

**Testing:** `make test` passes, 11 tests including 9 new ones in `tests/test_migrate.py`. They cover the name split, plain and gzip backups, re-running, and stopping on a bad record. I tried to run the command itself on a temporary copy of the store, but that command was blocked here. The command wiring in `bfk/cli.py` is therefore only checked by reading the code, not by running it.

Nothing is committed yet.

### Assistant final message, turn 2

I committed the migration helper as `aaea06c` on a new branch, `accounts-v2-migration`, rather than on `main`. The commit has the three files: `bfk/migrate.py`, `bfk/cli.py` and `tests/test_migrate.py`.

Names still split on the last word, so "Celia Marten Vos" becomes `Celia Marten` / `Vos`.

Not done yet:
- I haven't pushed the branch or opened a PR.
- I haven't run the migration on `data/accounts.jsonl` in the repo.
- The `bfk migrate` command itself still hasn't been run end to end; only the unit tests have.

Before running it on staging and laptops, try it on a copy first, for example `python3 -m bfk.cli migrate --path /tmp/accounts.jsonl`.

If you'd like me to push and open a PR, or run the migration on the repo's data file and commit that, tell me which.
