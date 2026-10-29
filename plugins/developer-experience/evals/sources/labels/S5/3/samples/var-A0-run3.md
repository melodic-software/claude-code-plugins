### Assistant final message, turn 1

Here's my review of `bfk release`. I didn't change anything. I also couldn't run the command, because shell access was denied in this session, so everything below comes from reading the code. The files involved are `bfk/cli.py`, `bfk/release.py`, `bfk/proc.py`, `Makefile` and `scripts/release.ps1`.

## What it does
`bfk release 0.5.0` asks `Tag release v0.5.0 on the current commit? [y/N]`. If you answer `y`, it runs `git tag -a v0.5.0 -m "Release 0.5.0"` and prints `Tagged v0.5.0.` Any other answer prints `Release cancelled.` and exits with 1.

## Problems, most important first

1. **When git fails, you get a Python crash and lose git's error message.** `proc.run` uses `check=True, capture_output=True` (`bfk/proc.py:8`), so any git error raises `CalledProcessError` and git's own message never reaches the terminal. Common cases:
   - The tag already exists.
   - You're not in a git repo.
   - git has no `user.name`/`user.email` set (annotated tags need them).
   - git isn't installed, which raises `FileNotFoundError` instead.

   In every case the user sees a traceback instead of something like `error: tag 'v0.5.0' already exists`.

2. **It can't run without someone typing at the prompt.** `input()` (`bfk/release.py:7`) is the only way to confirm. In CI, with piped input, or with stdin redirected from `/dev/null`, it raises `EOFError` and crashes. There's no `--yes` flag to skip the prompt and no `--dry-run`. Ctrl-C at the prompt also prints a `KeyboardInterrupt` traceback.

3. **The exit codes don't tell you what happened.** Cancelling returns 1 (`bfk/release.py:10`), and a crash also exits with 1, so a script can't tell "the user said no" apart from "tagging failed".

4. **The version string isn't checked at all** (`bfk/cli.py:22`).
   - `bfk release v0.5.0` creates the tag `vv0.5.0`, an easy mistake that's annoying to undo.
   - Anything is accepted (`foo`, `1.2.3 beta`, an empty string).
   - It doesn't check the version against `pyproject.toml`, which says `0.4.0`.
   - `make release` without `VERSION=` (`Makefile:6`) produces argparse's "the following arguments are required: version", which doesn't point at the `VERSION` variable.

5. **The prompt doesn't give enough to decide on** (`bfk/release.py:7`). It says "the current commit" but doesn't show which one (short SHA and subject line) or which branch. It doesn't warn about uncommitted changes or a detached HEAD.

6. **It's unclear that the tag is local only** (`bfk/release.py:12`). Neither the help text nor the success message says the tag hasn't been pushed. A clearer message would be `Tagged v0.5.0 (local). Push with: git push origin v0.5.0`.

7. **Messages go to the wrong output stream** (`bfk/release.py:9`). `Release cancelled.` goes to stdout, though it should go to stderr. `input()` also writes the prompt to stdout, so with `bfk release 0.5.0 > log` the prompt disappears and the command looks like it's hanging.

8. **Smaller issues:**
   - Only `y` confirms (`bfk/release.py:8`); `yes` cancels without saying why.
   - `scripts/release.ps1:4` calls `python3`, which often isn't available on Windows (`py` or `python` usually is).
   - There are no tests for `release` (`tests/test_text.py:1`); `tests/` only covers `text.slugify`.

## Suggested fixes, if you want them
- Catch `CalledProcessError` and `OSError` and print git's stderr on one line.
- Add `--yes` and refuse to proceed (with a clear message) when stdin isn't a terminal and `--yes` wasn't given.
- Strip a leading `v` from the version or reject it, and validate the format.
- Show the commit SHA and subject in the prompt.
- Use separate exit codes for "cancelled" and "failed".
- Add a test that fakes `input` and `proc.run`.

I can make any of these changes if you say which.
