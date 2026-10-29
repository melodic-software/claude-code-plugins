### Assistant final message, turn 1

`tq commit` now accepts flags, so your CI job can run it without anyone typing. I haven't built or run any of this, because shell commands were blocked in this session. Please run `make build`, `make check` and the commands below before relying on it.

**For CI:**
```sh
tq commit --type fix --message "bump paging defaults"
```

**At the keyboard:** typing plain `tq commit` still asks for the type and message, with the same wording and exit codes as today.

**What changed** (in `src/Tarnquill.Cli/Commands/CommitCommand.cs`):
- **New flags:** `--type` and `--message` skip their prompts. If you give only one, it asks for the other at a terminal.
- **No more hanging:** when nothing is typing into the command (as in CI) and either flag is missing, it stops straight away with exit code 2 and says to pass both flags.
- **Bad flag values:** an unknown `--type` or an empty `--message` exits 2 and lists the valid types.
- **Project rules for new commands:** it also gets `--help` (`-h`), `--dry-run` (shows the commit it would make without making it) and `--json` (prints the result as JSON; in that mode the prompts go to stderr so the JSON output stays clean).
- **Other files:** `Program.cs` now passes the arguments through and its usage line is updated. `AGENTS.md` no longer says "no flags bypass the prompts".

**One behaviour change:** piping the answers in, like `printf 'feat\nmsg\n' | tq commit`, now exits 2 instead of reading them. I did it this way because reading from a pipe is exactly what hangs in CI, and the flags replace it. If anything relies on piping, tell me and I'll keep that working instead.

**To check once it builds:**
```sh
make tq ARGS="commit --help"
make tq ARGS="commit --type feat --message test --dry-run --json"
make tq ARGS="commit" < /dev/null   # should exit 2 immediately, not hang
make tq ARGS="commit"               # at a terminal: prompts exactly as before
```

### Assistant final message, turn 2

The build works now, and the new `tq commit` flags behave as intended. But `make check` fails on 2 checks in the paging code, which this change didn't touch.

**`tq commit` results** (built with 0 warnings and 0 errors):
- **Flags given, `--dry-run --json`:** printed `{"ok":true,"dryRun":true,"message":"feat: test"}` and exited 0.
- **No flags, input from `/dev/null`:** exited 2 straight away with "stdin is not a terminal; pass --type and --message", instead of waiting.
- **`--type nope`:** exited 2 with "unknown change type 'nope' (expected feat/fix/docs/chore)".
- **`--help`:** shows the usage text and the exit codes.

**Not tested:**
- **Prompts at a real terminal:** I can't run an interactive session here. That path is the original prompt code, unchanged.
- **A real commit (without `--dry-run`):** I didn't make one, so the repo stays clean.
- **CI's exact situation:** the hang there is input left open with nothing ever typed. My `/dev/null` test goes through the same "no terminal" check, but I didn't reproduce the open-input case itself.

**The failing checks:**
```
FAIL PageCount(10, 5): expected 2, got 3
FAIL PageCount(0, 5): expected 0, got 1
```
`src/Tarnquill.Core/Paging.cs:13` adds a page every time (`total / pageSize + 1`), so it overcounts whenever the total divides evenly, including 0. The usual fix is `(total + pageSize - 1) / pageSize`. It's a one-line change, but it's a separate fix, so I haven't made it. Should I?

The changes to `CommitCommand.cs`, `Program.cs` and `AGENTS.md` are not committed. Tell me if you want a commit or a branch.
