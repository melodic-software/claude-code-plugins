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

2. **Ctrl-C at the prompt prints a traceback.** `input()` (`bfk/release.py:7`) raises `KeyboardInterrupt` and nothing catches it. There's also no `--dry-run`.

3. **The exit codes don't tell you what happened.** Cancelling returns 1, and a crash also exits with 1, so a script can't tell "the user said no" apart from "tagging failed".

4. **The version string isn't checked at all.**
   - `bfk release v0.5.0` creates the tag `vv0.5.0`, an easy mistake that's annoying to undo.
   - Anything is accepted (`foo`, `1.2.3 beta`, an empty string).
   - It doesn't check the version against `pyproject.toml`, which says `0.4.0`.
   - `make release` without `VERSION=` produces argparse's "the following arguments are required: version", which doesn't point at the `VERSION` variable.

5. **The prompt doesn't give enough to decide on.** It says "the current commit" but doesn't show which one (short SHA and subject line) or which branch. It doesn't warn about uncommitted changes or a detached HEAD.

6. **It's unclear that the tag is local only.** Neither the help text nor the success message says the tag hasn't been pushed. A clearer message would be `Tagged v0.5.0 (local). Push with: git push origin v0.5.0`.

7. **Messages go to the wrong output stream.** `Release cancelled.` goes to stdout, though it should go to stderr. `input()` also writes the prompt to stdout, so with `bfk release 0.5.0 > log` the prompt disappears and the command looks like it's hanging.

8. **Smaller issues:**
   - Only `y` confirms; `yes` cancels without saying why.
   - `scripts/release.ps1` calls `python3`, which often isn't available on Windows (`py` or `python` usually is).
   - There are no tests for `release`; `tests/` only covers `text.slugify`.

## Suggested fixes, if you want them
- Catch `CalledProcessError` and `OSError` and print git's stderr on one line.
- Strip a leading `v` from the version or reject it, and validate the format.
- Show the commit SHA and subject in the prompt.
- Use separate exit codes for "cancelled" and "failed".
- Add a test that fakes `input` and `proc.run`.

I can make any of these changes if you say which.
