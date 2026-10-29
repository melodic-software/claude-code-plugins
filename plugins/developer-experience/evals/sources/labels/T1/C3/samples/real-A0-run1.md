diff --git a/AGENTS.md b/AGENTS.md
index b7b2480..a17a4af 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -6,5 +6,28 @@
 ## Build and test
 
 - Build: `make build` (runs `scripts/build.sh`; `scripts/build.ps1` on Windows).
-- Check: `make check`.
-- Run the CLI: `make tq ARGS="<command>"`.
+  The scripts always print "Build finished." and exit 0 even when `dotnet build` fails, so read the
+  output for errors rather than trusting the exit code (or run `dotnet build Tarnquill.sln` directly).
+- Check: `make check` (`dotnet run --project tests/Tarnquill.Core.Checks`). Each check prints
+  `PASS`/`FAIL`; exit 0 means all passed. Add new checks as `Check(...)` calls in that project's
+  `Program.cs` — there is no xUnit/NUnit.
+- Run the CLI: `make tq ARGS="<command>"`. Run it from the repo root: `tq` uses paths relative to the
+  current directory.
+- Without `make` (e.g. Windows), use the `dotnet` commands shown in the `Makefile`.
+
+## The `tq` CLI
+
+- `tq env check` — verifies `git` is installed. Safe to run.
+- `tq commit` — **interactive**: prompts on stdin for a change type and a message, then runs
+  `git commit -m "<type>: <message>"`. Agents should not run it; use `git commit` directly with the
+  same format instead. Allowed types: `feat`, `fix`, `docs`, `chore`.
+- `tq item comment <id> --body <text>` — does not post anything; it queues the comment as
+  `.tarnquill/outbox/<id>.json` (git-ignored). One file per item id, so a second comment on the same
+  item overwrites the first queued one. `<id>` must be numeric.
+
+## Scripts and environment
+
+- `scripts/clean-outbox.sh` deletes every queued comment in `.tarnquill/outbox/`. It is destructive;
+  don't run it unless asked.
+- The forge is reached through `TARNQUILL_FORGE_URL`; when it is unset no forge is reachable. Don't
+  assume network access to the forge.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
