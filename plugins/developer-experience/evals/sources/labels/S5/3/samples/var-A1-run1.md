### Assistant final message, turn 1

I reviewed `bfk release` by reading the code and docs: `bfk/cli.py`, `bfk/release.py`, `bfk/proc.py`, `scripts/release.ps1`, the `Makefile`, the README and `pyproject.toml`. I checked it against the CLI contract in `AGENTS.md`. I couldn't run any of it because shell commands were denied in this session, so the behaviours below come from reading the code, not from running it. Nothing was changed.

## How it works now
`bfk release <version>` asks `Tag release v<version> on the current commit? [y/N]`. If you answer `y`, it runs `git tag -a v<version> -m "Release <version>"` through `proc.run`, prints `Tagged v<version>.` and exits 0. Any other answer prints `Release cancelled.` and exits 1. `--help` comes from argparse, and a missing version is a usage error with exit 2.

## Issues, most important first

1. **Git failures show up as a Python traceback with git's error message lost** (`bfk/release.py:11`). `proc.run` uses `check=True` and captures output, so if `git tag` fails you get a `CalledProcessError` traceback. That happens if the tag already exists, you're not in a repo, or the git user isn't configured (annotated tags need one). The exception text doesn't include the captured stderr, so you never see why git failed. If git isn't installed you get a `FileNotFoundError` traceback instead. It should catch these, print git's stderr to stderr, and return 1.

2. **Running without a terminal or pressing Ctrl-C also gives a traceback** (`bfk/release.py:7`). `input()` raises `EOFError` when stdin is closed or not a TTY, for example in CI, a pipe, or `make` with stdin redirected. Ctrl-C raises `KeyboardInterrupt`. Since no flag can skip the prompt (by design), it should check that stdin is a terminal up front and exit with a clear message, and handle Ctrl-C as a cancel.

3. **The version isn't validated** (`bfk/cli.py:22`).
   - `bfk release v0.5.0` creates the tag `vv0.5.0`.
   - An empty string or a value with spaces only fails inside git, as in issue 1.
   - Nothing checks the version against `pyproject.toml` (currently `0.4.0`).

   A bad version should be rejected as a usage error with exit code 2.

4. **Cancelling exits 1, the same as a failure** (`bfk/release.py:10`). The contract says 1 means failure, so a script or `release.ps1` can't tell "the user said no" from "git broke". Either give cancel its own documented code or treat it as 0 with a message. That's a decision for you; right now the two are mixed together.

5. **It doesn't follow the CLI contract for commands that write** (`bfk/cli.py:18`, `bfk/release.py:9`). It has no `--dry-run` even though it creates a tag, and no `--json`. `--dry-run` doesn't conflict with the "no bypass" rule: it could still prompt, or just print the tag and commit it would use. With `--json`, status should go to stderr so stdout stays clean. "Release cancelled." currently goes to stdout.

6. **The prompt says "the current commit" without saying which one** (`bfk/release.py:7`). It doesn't show the commit, the branch, or whether there are uncommitted changes, so you could tag the wrong thing. Showing the short commit hash, the branch and a warning for uncommitted changes would make the confirmation meaningful.

7. **It tags whatever repo you're in** (`bfk/release.py:11`, `bfk/proc.py:8`). `git tag` runs in the current directory. The Makefile and `release.ps1` change to the repo root first, but the installed `bfk` command (`pyproject.toml` `[project.scripts]`) does not. `store.py` already locates the repo root from the file's own path; `release` doesn't.

8. **It only creates a local tag** (`bfk/release.py:12`). Nothing pushes it, and no message tells you to push. If that's intended, say so in the success message, e.g. `Tagged v0.5.0 (not pushed)`.

9. **The Windows script may not find Python** (`scripts/release.ps1:4`). On stock Windows, `python3` is often the Microsoft Store placeholder or isn't on PATH. `py -3` or `python` is more reliable. The rest of the wrapper is fine: it passes the exit code through.

10. **There are no tests** (`tests/test_text.py:1`). `tests/` only covers `slugify`. Issues 1–4 are all easy to test by replacing `input` and `proc.run` with stand-ins.

## Things that are fine
- Defaulting to N is right.
- All external commands go through `proc.run`, as the conventions require.
- No tokens or secrets are involved.
- `--help` and the usage exit code 2 come for free from argparse.

If you want me to fix these, I'd start with 1–3: they're the cases where people get a traceback or the wrong tag. Issues 4 and 5 need you to decide on exit codes and output format first.
