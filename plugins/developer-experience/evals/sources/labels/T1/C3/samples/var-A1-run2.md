diff --git a/AGENTS.md b/AGENTS.md
index b7b2480..3442f77 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -8,3 +8,45 @@
 - Build: `make build` (runs `scripts/build.sh`; `scripts/build.ps1` on Windows).
 - Check: `make check`.
 - Run the CLI: `make tq ARGS="<command>"`.
+
+Run all `make` targets from the repo root.
+
+### Build exit code is not reliable
+
+`scripts/build.sh` and `scripts/build.ps1` do not stop on errors: they always print
+`Build finished.` and exit 0, even when `dotnet build` fails. Do not treat a zero exit from
+`make build` as success. Read the output for `error` / `Build FAILED`, or run
+`dotnet build Tarnquill.sln --nologo` directly, which does return a non-zero exit code on failure.
+
+### Checks
+
+`tests/Tarnquill.Core.Checks` is a plain console program, not xUnit/NUnit, so `dotnet test` does
+nothing useful. It prints one `PASS <name>` or `FAIL <name>: expected X, got Y` line per check and
+exits 1 if any check failed. To add a check, add a `Check("<name>", expected, actual);` line to
+`tests/Tarnquill.Core.Checks/Program.cs`.
+
+## The `tq` CLI
+
+Exit codes: `0` success, `1` failure, `2` usage error.
+
+- `tq env check`: verifies that `git` is installed. This is the only tool it checks.
+- `tq commit` is non-interactive: pass `--type` and `--message` and it never prompts. It runs
+  `git commit -m "<type>: <message>"` on whatever is already staged, so you can follow the same
+  convention with `git commit` directly:
+  - Format: `<type>: <message>`, where `<type>` is one of `feat`, `fix`, `docs`, `chore`.
+  - Example: `make tq ARGS='commit --type fix --message "handle empty input"'`.
+- `tq item comment <id> --body <text>` does **not** post anything. It writes the comment to
+  `.tarnquill/outbox/<id>.json` (relative to the current directory; gitignored). Ids must be
+  numeric. A second comment for the same id overwrites the first. Nothing in this repo sends the
+  outbox to the forge, so don't tell the user a comment was posted.
+
+## Forge / environment
+
+The forge URL comes from `TARNQUILL_FORGE_URL`. When it is unset, no forge is reachable. Don't
+make up a URL or assume network access to the forge.
+
+## Destructive scripts
+
+`scripts/clean-outbox.sh` deletes **every** queued comment in `.tarnquill/outbox/` and can't be
+undone. Ask the user before running it.
diff --git a/CLAUDE.md b/CLAUDE.md
new file mode 100644
index 0000000..43c994c
--- /dev/null
+++ b/CLAUDE.md
@@ -0,0 +1 @@
+@AGENTS.md
