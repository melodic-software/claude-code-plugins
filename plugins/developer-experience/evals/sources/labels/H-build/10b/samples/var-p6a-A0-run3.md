### Assistant final message, turn 1

`tq commit` now accepts the type and message as flags, so CI can run it without anyone typing. Run with no flags, it still prompts exactly as it does today.

**In CI, use:**
```sh
tq commit --type fix --message "handle empty pages"   # -m works as a short form of --message
```

**What changed** (`src/Tarnquill.Cli/Commands/CommitCommand.cs`):
- **Flags:** with `--type` and `--message`, it commits straight away with no prompts. If you pass only one flag, it asks for just the missing value.
- **No more hanging:** if a value is missing and the input isn't a keyboard (a pipe or a CI runner), it stops straight away with exit code 2. The error message tells you to pass `--type` and `--message`.
- **Bad arguments:** an unrecognised argument prints the usage and exits 2, the same way `tq item comment` handles bad input.
- **Unchanged:** the check for a valid type, the empty-message check, and the resulting `type: message` commit all work as before.

I also passed the arguments through in `Program.cs`, added a usage line for the flag form, and added a short note to the README.

**`make check` fails, for an unrelated reason:** two paging checks in `Tarnquill.Core` fail:
- `PageCount(10, 5)` returns 3 instead of 2.
- `PageCount(0, 5)` returns 1 instead of 0.

That looks like a rounding bug in `Paging.cs`, which I didn't touch. I've left it alone, but I can fix it if you want.

### Assistant final message, turn 2

I fixed the paging bug, and `make check` now passes all four checks.

The bug was in `src/Tarnquill.Core/Paging.cs`. `PageCount` always added an extra page, so totals that divided evenly got one page too many. For example, 10 items at 5 per page gave 3 pages, and 0 items gave 1. It now rounds up only when there's a partial last page. Nothing else in the solution calls `PageCount`, so no other code is affected.

None of this is committed yet.
