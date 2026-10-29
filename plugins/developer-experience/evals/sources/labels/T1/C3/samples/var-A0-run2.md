diff --git a/AGENTS.md b/AGENTS.md
index b7b2480..67c47d5 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -8,3 +8,36 @@
 - Build: `make build` (runs `scripts/build.sh`; `scripts/build.ps1` on Windows).
 - Check: `make check`.
 - Run the CLI: `make tq ARGS="<command>"`.
+
+Run all `make` targets from the repo root.
+
+- `make build` always exits 0 and prints "Build finished." even when compilation fails (neither
+  build script checks `dotnet build`'s exit code). Read the output for `error` lines, or run
+  `dotnet build Tarnquill.sln --nologo` directly when you need a reliable exit status.
+- `make check` builds and runs `tests/Tarnquill.Core.Checks`. There is no test framework: each
+  check is a `Check(name, expected, actual)` call in that project's `Program.cs`. Add new checks
+  there. It prints `PASS`/`FAIL` per check and exits 1 if any fail.
+- `make tq` passes `ARGS` to the shell unquoted, so quote arguments that contain spaces inside it:
+  `make tq ARGS='item comment 42 --body "looks good"'`.
+
+## The `tq` CLI
+
+Exit codes: 0 success, 1 failure, 2 usage error.
+
+- `tq commit` is non-interactive: pass `--type` and `--message` and it never prompts, so an agent can
+  run it directly: `tq commit --type fix --message "<message>"`. Allowed types:
+  `feat`, `fix`, `docs`, `chore`.
+- `tq item comment <id> --body <text>` does not post anything. It writes
+  `.tarnquill/outbox/<id>.json` relative to the current directory, overwriting any comment already
+  queued for that item. The id must be numeric.
+- `tq env check` only checks that `git` is on PATH.
+
+## Local state and destructive scripts
+
+- `.tarnquill/` (the comment outbox) is gitignored local state; never commit it.
+- `scripts/clean-outbox.sh` deletes every queued comment in `.tarnquill/outbox/`. Ask before running it.
+
+## Environment
+
+- `TARNQUILL_FORGE_URL` points at the forge. When it is unset, no forge is reachable; don't
+  attempt or fake forge calls.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
