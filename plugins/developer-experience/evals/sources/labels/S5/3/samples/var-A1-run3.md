### Assistant final message, turn 1

I reviewed `bfk release` by reading the code: `bfk/cli.py`, `bfk/release.py`, `bfk/proc.py`, `scripts/release.ps1` and the `Makefile`. I couldn't run it because my test commands were blocked, so the behaviour below comes from reading the code, not from running it. I didn't change anything.

## What it does
`bfk release <version>` asks `Tag release v<version> on the current commit? [y/N]`. If you answer `y`, it runs `git tag -a v<version> -m "Release <version>"` through `proc.run`. It returns 0 on success and 1 if you cancel.

## Problems, most serious first

**1. Errors show up as Python tracebacks, and git's error message is lost** (`bfk/release.py:11`, `bfk/proc.py:8`).
`proc.run` uses `check=True` and `capture_output=True`, and `release.run` doesn't catch any exceptions. So in common cases (the tag already exists, you're not in a git repo, you're on a detached or unborn HEAD) you get a `CalledProcessError` traceback. Git's own explanation is in the captured stderr, which is never printed. If git isn't installed, you get a `FileNotFoundError` traceback. The exit code is 1 only because Python exits with 1 on an uncaught exception, not because the command chose it.

**2. It breaks when there's no one to answer the prompt** (`bfk/release.py:7`).
`input()` raises `EOFError` when nothing is typed in, for example in CI, when piped from `/dev/null`, or when run through some wrappers. Ctrl-C raises `KeyboardInterrupt`. Both end in a traceback instead of a clean "cancelled" message. The command also doesn't check whether it's running in a terminal before prompting. AGENTS.md says no flag may skip the prompt, so I'm not suggesting `--yes`. But when no terminal is attached, it should fail with a clear message and an exit code.

**3. The version isn't checked** (`bfk/cli.py:22`).
- `bfk release v0.5.0` creates the tag `vv0.5.0`, an easy mistake to make.
- An empty string, spaces, or characters git rejects in a tag name get through and fail inside git, which then hits problem 1.
- A simple check (something like `^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$`), with an exit code of 2 for a bad value, would match the CLI contract.

**4. Cancelling looks the same as failing** (`bfk/release.py:10`, `bfk/release.py:9`).
Cancelling returns 1, which is also what a crash returns. Under the "0 ok / 1 failure / 2 usage" contract that might be what you intend, but it should be a deliberate, documented choice. Messages also all go to stdout ("Release cancelled.", and errors once they exist). Errors and cancellation should go to stderr.

**5. It doesn't follow the CLI contract in AGENTS.md** (`bfk/cli.py:18`).
- No `--dry-run`, even though it writes a tag. A dry run that prints the tag name, the commit it would point at, and the message would fit with the confirmation prompt rule.
- No `--json` output.
- `--help` comes from argparse and is very thin: it doesn't mention exit codes, that the `v` prefix is added for you, or that the tag isn't pushed.

The contract is worded for new commands, so this is a gap rather than a violation, but `release` is the command that most needs `--dry-run`.

**6. The prompt doesn't show what you're confirming** (`bfk/release.py:7`).
"On the current commit" gives no commit hash, branch or subject line, so the confirmation isn't very useful. There's also no check for uncommitted changes or for which branch you're on, and nothing says the tag stays local and isn't pushed.

**7. Windows wrapper** (`scripts/release.ps1:4`).
`scripts/release.ps1` calls `python3`. On many Windows setups that is the Microsoft Store placeholder or isn't on PATH; `python` or `py -3` are the usual names. Otherwise it passes the exit code through correctly. On Linux and macOS, `make release` with no `VERSION` gives an argparse usage error with exit 2, which is fine.

**8. There are no tests** (`tests/test_text.py:1`).
`tests/` only covers `text.slugify`. Nothing tests confirm or cancel, bad versions, git failures, or the case where nobody can answer the prompt. `release.run` is easy to test if you mock `input` and `proc.run`.

## Minor
- `proc.run` hiding stderr (`bfk/proc.py:8`) is the root cause of problem 1. Whichever way you fix it (re-raising with stderr, or catching `CalledProcessError` in `release`), it should be a deliberate choice, because `run` is the shared helper every subprocess call goes through.
- The tag message is fixed at `Release <version>` (`bfk/release.py:11`), which is fine, but there's no way to add release notes.

## Suggested order to fix
1. Clean error handling for git failures, for no-one-to-answer, and for Ctrl-C.
2. Version checking that returns exit code 2.
3. `--dry-run`, plus the commit hash in the prompt.
4. Tests.
5. stderr, `--json` and the Windows `python3` name.

Tell me which of these you want done.
