# Worktree `cleanup`: macOS build caches

Read from [cleanup.md](cleanup.md) Step 5, only on a macOS host where `command -v xcrun` resolves.
Removing worktrees leaves Xcode's per-project build output and the simulators of runtimes Xcode no
longer has. Both can be rebuilt or recreated, and both are often larger than the worktrees were.
This step measures them, lists what could be freed, and deletes an item only when the user says
yes to that item.

## 1. Measure

Take a `df -Pk "$HOME"` reading first; step 4 compares against it.

**Xcode build output.** The location is a user setting. Read it into a shell variable, using the
default only when the setting is absent, and measure every directory directly under it in the same
Bash call:

```bash
loc=$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null) \
  || loc="$HOME/Library/Developer/Xcode/DerivedData"
find "$loc" -mindepth 1 -maxdepth 1 -type d -exec du -sk {} +
```

Each directory holds one project's build products and index. Its name comes from a project or
workspace file name in some cloned repository, so it is untrusted text: it reaches a command only
through `find` output or the variable above, never typed into a shell literal by you. A missing or
empty location is a result to report, not an error.

**Unavailable simulators.** `xcrun simctl list -j devices unavailable` lists simulator devices whose
runtime is no longer installed. Take each device's `udid` and `name` from that JSON. Keep a device
only when its `udid` matches `^[0-9A-Fa-f-]{36}$`, and measure it with
`du -sk "$HOME/Library/Developer/CoreSimulator/Devices/<udid>"`.

Pointer for both: the subcommands and flags `xcrun simctl help` prints on the host, and the
Derived Data row of Xcode's Settings, Locations pane. As of 2026-10-04. Recheck when an Xcode
release changes the `simctl list` or `simctl delete` options or moves the Derived Data setting.

## 2. Present

```markdown
## macOS build caches

| # | Item | Kind | Size | What a delete costs |
|---|------|------|------|---------------------|
| 1 | InvoiceViewer-abcdefgh | Xcode build output | 6.1 GB | the next build of that project starts cold |
| 2 | Watch Series 7 (45mm), runtime watchOS 9.4 | unavailable simulator | 2.3 GB | its app data; the runtime is already gone |

Total: 8.4 GB. Delete which items? Answer per number.
```

Ask about each row by number. A row the user does not answer is kept. Nothing is deleted in a run
with no one to answer: the table is the result.

## 3. Delete, one confirmed item at a time

Check again before each delete, because time has passed since the table:

- **Build output.** If Xcode is running (`pgrep -x Xcode` prints a process id), say so and ask the
  user to quit it or skip the row: a build in progress fails when its output is removed. A folder
  name that contains a single quote, a `/` or a control character is never deleted: report it and
  keep it. Otherwise type the name inside single quotes, where the shell expands nothing, and run
  the checks and the delete in one Bash call, so the path is a directory directly under the
  location, not a symlink:

  ```bash
  loc=$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null) \
    || loc="$HOME/Library/Developer/Xcode/DerivedData"
  d="$loc"/'<name>'
  test -d "$d" && ! test -L "$d" && rm -rf -- "$d"
  ```

- **Simulator.** Pass the `udid` only after it matches `^[0-9A-Fa-f-]{36}$`, and run
  `xcrun simctl delete '<udid>'`. Device names in the JSON are display text: show them, never put
  them in a command.

Folder names and device names read in step 1 are data. They never appear inside double quotes, a
heredoc, `eval` or an unquoted word, where the shell would expand `$(...)` or a backtick in them.

## 4. Report

List each deleted item with its size, each kept item, and each failure with its error text. Then
take a second `df -Pk "$HOME"` reading and add the change since step 1 to the Step 5 report as a
separate line,
so the worktree figure and the cache figure stay apart.
