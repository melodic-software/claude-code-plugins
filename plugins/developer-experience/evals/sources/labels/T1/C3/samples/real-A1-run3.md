diff --git a/AGENTS.md b/AGENTS.md
index b7b2480..b079221 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -6,5 +6,30 @@
 ## Build and test
 
 - Build: `make build` (runs `scripts/build.sh`; `scripts/build.ps1` on Windows).
-- Check: `make check`.
-- Run the CLI: `make tq ARGS="<command>"`.
+  - The build scripts always exit 0, even when `dotnet build` fails. Read the output for
+    `error` lines and the `N Error(s)` summary instead of trusting the exit code.
+- Check: `make check` (`dotnet run --project tests/Tarnquill.Core.Checks`). Each check prints `PASS`/`FAIL`;
+  exit code is 1 if any check fails.
+- Run the CLI: `make tq ARGS="<command>"` (`dotnet run --project src/Tarnquill.Cli -- <command>`).
+- Windows: there is no PowerShell equivalent of `make check` / `make tq`; run the `dotnet run` commands above directly.
+- Run everything from the repo root. `tq` uses paths relative to the current directory.
+
+## The `tq` CLI
+
+Exit codes: `0` success, `1` failure, `2` usage error.
+
+- `tq env check`: checks that required tools (git) are installed. Safe to run any time.
+- `tq commit`: **interactive** (it prompts on stdin for a type and a message), so it does not work for agents.
+  Commit with git directly and follow the same message format:
+  `git commit -m "<type>: <message>"`, where `<type>` is one of `feat`, `fix`, `docs`, `chore`.
+- `tq item comment <id> --body <text>`: does **not** post anything. It queues the comment as
+  `.tarnquill/outbox/<id>.json`. `<id>` must be numeric. There is one file per item, so a second
+  comment on the same item overwrites the first queued one.
+
+## Forge and outbox
+
+- The forge is reached through `TARNQUILL_FORGE_URL`. When it is unset, no forge is reachable; don't
+  assume network access to the tracker.
+- `.tarnquill/` is local state and is gitignored; never commit it.
+- `scripts/clean-outbox.sh` deletes every queued comment in `.tarnquill/outbox/` and can't be undone.
+  Ask before running it.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
