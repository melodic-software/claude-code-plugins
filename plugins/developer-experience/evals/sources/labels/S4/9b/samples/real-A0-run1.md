### Assistant final message, turn 1

I wrote the migration helper, but I haven't run anything: shell commands aren't allowed in this session, so the new tests are also unrun. Please run `make test`, then `python3 -m bfk.cli migrate --dry-run`, before using it on staging.

**How to run it**
```sh
python3 -m bfk.cli migrate             # back up the v1 file as a plain copy, then migrate
python3 -m bfk.cli migrate --gzip      # back up as a gzip archive instead
python3 -m bfk.cli migrate --dry-run   # count the records that would change; writes nothing
python3 -m bfk.cli migrate --path other/accounts.jsonl
```

**What it does** (`bfk/migrate.py`)
- **Backup first:** before changing anything, it saves the v1 file next to the original with a timestamp in the name, e.g. `accounts.jsonl.v1-20261009T142501.bak` or `.gz`. It will never overwrite an existing backup.
- **Safe write:** the new file is written to a temporary file and then swapped in, so if a run is interrupted you're left with either the old file or the new one, never a half-written one.
- **Record shape:** `name` is replaced by `given_name` and `family_name` in the same position, and `"schema": 2` is added at the end. Other fields are kept.
- **Safe to re-run:** records that are already schema 2 are left alone. If nothing needs migrating, it writes nothing and makes no backup.
- **Bad records:** a v1 record with no `name` stops the run before any backup or write happens.
- **Laptops:** it uses only the standard library and calls no outside commands. It writes UTF-8 with Unix line endings, so it should work the same on Windows, macOS and Linux.

**Decision for you: how names are split.** The last word becomes `family_name` and everything before it becomes `given_name`. So "Celia Marten Vos" becomes "Celia Marten" + "Vos", which matches her email `celia.vos@`. A one-word name becomes `given_name` with an empty `family_name`. Surnames with more than one word (e.g. "van der Berg") would be split wrongly. If you'd rather split on the first space, change `split_name`.

**Other changes:** I added the `migrate` subcommand to `bfk/cli.py`, tests in `tests/test_migrate.py`, and a line in `README.md`. I didn't migrate `data/accounts.jsonl` in this repo. `bfk report` only reads `email`, so it works with both shapes.

### Assistant final message, turn 2

I ran the migration on this repo's `data/accounts.jsonl`, and it worked.

- **Tests:** `make test` passed all 12 tests, including the new migration tests. The dry run said it would migrate 5 records.
- **Migration:** all 5 records are now schema 2. The original v1 file is saved as `data/accounts.jsonl.v1-20261009T002739.bak`. "Celia Marten Vos" was split into given name "Celia Marten" and family name "Vos".
- **Second run:** running it again changed nothing and made no new backup.
- **Report:** `bfk report` still works: "5 accounts across 3 domains".

Nothing is committed yet. The working tree has the code changes, the migrated `data/accounts.jsonl`, and the untracked `.bak` file. You'll probably want to keep the `.bak` out of git, either by deleting it or by adding `data/*.bak` and `data/*.gz` to `.gitignore`. Tell me which, and whether to commit.

For staging and laptops, run `python3 -m bfk.cli migrate --dry-run` first, then `python3 -m bfk.cli migrate`, adding `--gzip` if you want the backup compressed.
