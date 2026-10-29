### Assistant final message, turn 1

I reviewed `bfk release` by reading the code: `bfk/cli.py`, `bfk/release.py`, `bfk/proc.py`, the Makefile, `scripts/release.ps1` and the README. I didn't change anything. I tried to run some harmless checks (`--help`, answering "n", closed stdin), but Bash permission was denied, so none of this is confirmed by running it.

## What it does
`bfk release 0.5.0` asks `Tag release v0.5.0 on the current commit? [y/N]`. If you answer `y`, it runs `git tag -a v0.5.0 -m "Release 0.5.0"` and prints `Tagged v0.5.0.` Any other answer prints `Release cancelled.` and exits with code 1.

## Problems, most serious first

1. **When git fails, you get a Python traceback and git's error message is lost** (`bfk/release.py:11`, `bfk/proc.py:21`). `proc.run` captures git's output and raises an error if git fails. Nothing catches that error or prints what git said. So if the tag already exists, you're not in a git repo, or `user.email` isn't set, you see a `CalledProcessError` traceback without the reason.

2. **It can't run without someone typing an answer** (`release.py:7`). There's no `--yes` flag. With stdin closed (`</dev/null`, some CI runners), `input()` raises `EOFError` and shows a traceback. In CI with stdin left open, it may just hang. Pressing Ctrl-C also shows a traceback instead of a clean cancel.

3. **The version isn't checked.**
   - `bfk release v0.5.0` creates the tag `vv0.5.0`. This is an easy mistake to make, since the prompt and the tags both show a `v`.
   - `bfk release ""` creates the tag `v`.
   - Values like `0.5.0 beta` or `../x` reach git unchanged; git rejects some of these, which brings back problem 1.

4. **No safety checks before tagging.** It tags HEAD even if the working tree has uncommitted changes, you're on a branch other than `main`, or HEAD is already tagged. The prompt says "current commit" but doesn't say which commit (no short SHA or subject line), so you're confirming without knowing what you're tagging.

5. **The tag may not match the package version.** `pyproject.toml` says `version = "0.4.0"`, and `bfk release 0.5.0` will tag without checking or changing that. Either check that they match or document that bumping the version is a separate step.

6. **Exit codes and output streams:**
   - Cancelling exits with 1, the same code a failure would get. Scripts like `release.ps1` can't tell "the user said no" from "it broke".
   - "Release cancelled." goes to stdout. Status messages like this usually go to stderr.

7. **It doesn't say what to do next.** It never pushes the tag, which is a fine choice, but the output doesn't mention `git push origin v0.5.0`, so the tag can easily stay local by accident.

8. **No dry run.** There's no `--dry-run` to show the tag name, commit and message without creating anything.

## Smaller points
- `--help` shows "tag a release (asks for confirmation)" and the `version` argument with an example, which is good. It doesn't say the `v` is added for you, or that the tag goes on HEAD.
- Running `make release` without `VERSION=` produces argparse's "the following arguments are required: version" error, which doesn't mention the `VERSION=` variable the user actually needs to set.
- None of the code involved has tests. `tests/` only covers `slugify`. `release.run` would be easy to test by patching `input` and `proc.run`.

## Suggested fixes, if you want them
1. Catch `CalledProcessError` and print git's stderr with a non-zero exit.
2. Strip a leading `v` (or reject it) and check the version format.
3. Add `--yes`, and handle `EOFError` and `KeyboardInterrupt` as a cancel.
4. Show the short SHA in the prompt and refuse to tag if the working tree is dirty.
5. Print the push command after tagging.

Tell me which of these you want and I'll implement them with tests.
