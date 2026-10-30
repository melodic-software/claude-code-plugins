diff --git a/AGENTS.md b/AGENTS.md
index b7b2480..a0c8d58 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -8,3 +8,38 @@
 - Build: `make build` (runs `scripts/build.sh`; `scripts/build.ps1` on Windows).
 - Check: `make check`.
 - Run the CLI: `make tq ARGS="<command>"`.
+
+Run all of these from the repo root.
+
+### Gotchas
+
+- `make build` **exits 0 even when the build fails**: both build scripts finish by printing
+  "Build finished.", and that print sets the exit status. Read the `dotnet build` output for
+  `error` lines, or run `dotnet build Tarnquill.sln --nologo` yourself if you need a real exit code.
+- `make check` is a plain console program, not xUnit/NUnit. To add a check, add a `Check(name, expected, actual)`
+  call in `tests/Tarnquill.Core.Checks/Program.cs`. A failed check prints a `FAIL` line and gives exit code 1.
+- On Windows without `make`, use `pwsh scripts/build.ps1`, `dotnet run --project tests/Tarnquill.Core.Checks`,
+  and `dotnet run --project src/Tarnquill.Cli -- <command>`.
+
+## The `tq` CLI
+
+| Command | Notes for agents |
+| --- | --- |
+| `tq commit` | **Interactive**: it prompts on stdin for a type and a message, so it hangs without input. Use `git commit -m "<type>: <message>"` directly instead. |
+| `tq item comment <id> --body <text>` | `<id>` must be all digits. This does **not** post anything: it writes `.tarnquill/outbox/<id>.json`, relative to the current directory, and **overwrites** any comment already queued for that item. |
+| `tq env check` | Only checks that `git` is installed. |
+
+Exit codes: `0` ok, `1` failure, `2` usage error.
+
+## Conventions
+
+- Commit messages: `<type>: <message>` where type is one of `feat`, `fix`, `docs`, `chore`
+  (this is the format `tq commit` produces).
+- The forge is configured with `TARNQUILL_FORGE_URL`. When it is unset, no forge is reachable, so don't
+  expect network-backed behavior.
+- `.tarnquill/` holds local state and is git-ignored.
+
+## Destructive scripts — ask before running
+
+- `scripts/clean-outbox.ps1` deletes every queued comment in `.tarnquill/outbox/`. Those comments are not saved
+  anywhere else.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
