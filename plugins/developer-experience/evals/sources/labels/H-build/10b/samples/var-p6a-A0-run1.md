### Assistant final message, turn 1

`tq commit` can now run from scripts and CI. It takes `--type` and `--message` flags, and when it can't prompt it exits with an error instead of hanging. Typing `tq commit` with no flags still asks both questions the same way it did before.

```sh
tq commit --type feat --message "add paging helper"
```

**Changes** (`src/Tarnquill.Cli/Commands/CommitCommand.cs`, `Program.cs`):
- **Flags:** `--type <feat|fix|docs|chore>` and `--message <text>` skip their prompts. If you pass only one, it still asks for the other at the keyboard. Flag values go through the same checks as typed answers.
- **No hanging:** if a value is missing and input isn't coming from a terminal, it exits with code 2 and says to pass `--type` and `--message`. It no longer waits forever for an answer.
- **Errors:** an unknown flag or a flag with no value prints the usage and exits with code 2. I also added the new form to the `tq` usage text.

**Before you switch CI over:** if any script today pipes answers in (like `printf 'feat\nmsg\n' | tq commit`), it will now get that error instead of committing. It needs to use the flags. Keyboard use is the only thing guaranteed to behave the same.

**Unrelated failure:** `make check` fails 2 of 4 checks, both in `Paging.PageCount`, which I didn't touch: `PageCount(10, 5)` returns 3 instead of 2, and `PageCount(0, 5)` returns 1 instead of 0. It looks like a rounding bug in `src/Tarnquill.Core/Paging.cs`. I can fix it if you'd like.

### Assistant final message, turn 2

I fixed the paging bug, and all 4 checks in `make check` pass now. The build is still clean.

**Cause:** `PageCount` always added an extra page, so it returned one too many whenever the total divided evenly by the page size. That's why 10 items at 5 per page gave 3 pages, and 0 items gave 1 page.

**Fix** (`src/Tarnquill.Core/Paging.cs:13`): it now only adds a page when there are leftover items:

```csharp
return total / pageSize + (total % pageSize == 0 ? 0 : 1);
```

I didn't use the common `(total + pageSize - 1) / pageSize` shortcut because it can overflow when `total` is very large.

A negative `total` still returns 1 page, as it did before. The method doesn't say what should happen in that case, so I left it alone. Nothing is committed yet; the `tq commit` and paging changes are both sitting in the working tree.
