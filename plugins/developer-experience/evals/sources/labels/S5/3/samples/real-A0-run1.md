### Assistant final message, turn 1

I reviewed `bfk release` (`bfk/cli.py`, `bfk/release.py`, `bfk/proc.py`, and the `make`/`release.ps1` wrappers) by reading the code. I didn't run it because shell access was denied partway through, and I didn't change anything.

**What it does:** `bfk release 0.5.0` asks `Tag release v0.5.0 on the current commit? [y/N]`. If you answer `y`, it runs `git tag -a v0.5.0 -m "Release 0.5.0"`.

## Findings, most important first

1. **Git's error messages are thrown away.** `proc.run` captures git's output and stops on failure (`bfk/proc.py:8`), and `release.run` doesn't handle that failure (`bfk/release.py:11`). If the tag already exists, you're not in a git repo, or `user.email` is unset, the user sees a Python traceback ending in `CalledProcessError`. Git's actual message (e.g. `fatal: tag 'v0.5.0' already exists`) is never printed. This is the biggest usability problem.

2. **It can't be run without a person at the keyboard.** `input()` (`bfk/release.py:7`) crashes with an `EOFError` traceback when there's no interactive input, for example in CI, `echo | …`, or `< /dev/null`. There's no `--yes`/`-y` option to skip the prompt, and no `--dry-run`. Pressing Ctrl-C at the prompt also prints a traceback instead of a clean cancel.

3. **The version isn't checked.**
   - `bfk release v0.5.0` creates the tag `vv0.5.0`, and the prompt makes this easy to miss.
   - `""`, `"0.5 beta"`, or other values that aren't valid tag names go straight to git and then hit problem 1.
   - Nothing compares the version with `pyproject.toml` (currently `0.4.0`), so you can tag a version that doesn't match the package.

4. **Exit codes are ambiguous.** Cancelling returns 1 (`bfk/release.py:10`), and a crash also exits with 1. A script calling it, including `release.ps1` which passes `$LASTEXITCODE` through, can't tell "user said no" from "tagging failed". The `return 2` at `bfk/cli.py:25` can never be reached.

5. **Output goes to the wrong place.** `Release cancelled.` goes to stdout, not stderr. `input()` also writes the prompt to stdout, so redirected output gets mixed with the prompt.

6. **It doesn't check the repo state, and the tag stays local.**
   - It tags whatever `HEAD` is in the current directory. It doesn't check the branch (e.g. `main`), uncommitted changes, or whether you're at the repo root. The `make` and `.ps1` wrappers do `cd` to the root first, but the `bfk` command itself doesn't.
   - It never pushes. The help says "tag a release" and the output says `Tagged v0.5.0.`, but neither says the tag exists only locally.

7. **The help is thin.** `bfk release --help` doesn't say which commit gets tagged, what the tag will be named (the `v` prefix), that the tag isn't pushed, or what the exit codes mean.

8. **Running `make release` without `VERSION` gives a confusing error.** It produces argparse's `the following arguments are required: version`, which doesn't tell a `make` user to pass `VERSION=…`.

9. **There are no tests.** `tests/` only has `test_text.py`. Nothing covers the prompt, cancelling, or git failing.

## Suggested direction (when you want changes)
- Catch `CalledProcessError` and print git's stderr with a clean non-zero exit.
- Add `--yes` and `--dry-run`.
- Handle `EOFError` and `KeyboardInterrupt` as a cancel.
- Strip or reject a leading `v`, and check the version format.
- Use separate exit codes for "cancelled" and "failed".
- Send status and error messages to stderr.
- Add `unittest` cases that mock `input` and `proc.run`.

Want me to go ahead with any of these?
