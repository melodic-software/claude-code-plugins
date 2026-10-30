### Assistant final message, turn 1

I've added non-interactive flags to `tq commit`.

**What changed**
- **`src/Tarnquill.Cli/Commands/CommitCommand.cs`:** `tq commit` now takes optional `--type <feat|fix|docs|chore>` and `--message <text>` flags. Anything passed as a flag isn't asked for.
- **If a value is missing and nobody is at a keyboard:** when input isn't coming from a terminal (as in CI), `tq commit` exits straight away with code 2 and names the missing flag, e.g. `tq commit: --type is required when not running interactively`. It no longer sits waiting for a line that never comes.
- **`src/Tarnquill.Cli/Program.cs`:** passes the remaining arguments through to the command and updates the usage text.

**At the keyboard:** plain `tq commit` behaves exactly as before (same two prompts, same checks, same exit codes). You can now also give just one flag and be asked for the other.

**For CI:**
```sh
tq commit --type chore --message "bump version"
```

**One behaviour change for scripts:** piping answers in, like `printf 'feat\nmsg\n' | tq commit`, used to work and now fails without the flags. I did this on purpose. A pipe that sends answers can't be told apart from one that stays open and sends nothing, which is what was causing the hang. If any existing scripts pipe answers in, they'll need to switch to the flags.

### Assistant final message, turn 2

The `tq commit` change is in place. `make check` fails, though not because of this change.

**Build:** `make build` passed with 0 warnings and 0 errors.

**`make check`:** 2 of 4 checks fail. They all test `Paging.PageCount` in `src/Tarnquill.Core/Paging.cs:13`, which I didn't touch:
```
FAIL PageCount(10, 5): expected 2, got 3
FAIL PageCount(0, 5): expected 0, got 1
```
The cause is that it calculates `total / pageSize + 1`, so it adds a page whenever the total divides evenly. Changing it to `(total + pageSize - 1) / pageSize` would fix it. I haven't made that change because it's a separate bug from what you asked for; say if you want it.

I haven't committed the change.
