diff --git a/AGENTS.md b/AGENTS.md
index b7b2480..48cf512 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -8,3 +8,32 @@
 - Build: `make build` (runs `scripts/build.sh`; `scripts/build.ps1` on Windows).
 - Check: `make check`.
 - Run the CLI: `make tq ARGS="<command>"`.
+
+Gotchas:
+
+- `make build` exits 0 and prints "Build finished." even when the build fails (neither build script
+  propagates `dotnet build`'s exit code). Read the output for `error` / `Build FAILED`, or run
+  `dotnet build Tarnquill.sln --nologo` directly when you need a reliable exit code.
+- `make check` prints `PASS`/`FAIL` per check and exits non-zero if any check failed. New checks go
+  in `tests/Tarnquill.Core.Checks/Program.cs` using the existing `Check(name, expected, actual)` helper;
+  there is no xUnit/NUnit and no `dotnet test`.
+
+## The `tq` CLI
+
+Exit codes: `0` success, `1` failure, `2` usage error.
+
+- `tq env check` — verifies `git` is installed. Safe to run any time.
+- `tq commit` — takes `--type` and `--message` flags and runs without prompting, so agents can use it.
+  It commits with the format:
+  `git commit -m "<type>: <message>"`, where `<type>` is one of `feat`, `fix`, `docs`, `chore`.
+- `tq item comment <id> --body <text>` — `<id>` must be numeric. This does **not** post anything; it
+  writes `.tarnquill/outbox/<id>.json` (gitignored). One file per item: a second comment on the same
+  item overwrites the first. Quote multi-word bodies:
+  `make tq ARGS='item comment 42 --body "Fixed in abc123"'`.
+
+## Scripts and environment
+
+- `scripts/clean-outbox.sh` deletes every queued comment in `.tarnquill/outbox/`. It is not
+  reversible; only run it when asked.
+- `TARNQUILL_FORGE_URL` points at the forge. When it is unset no forge is reachable — don't assume
+  anything has been sent remotely.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
