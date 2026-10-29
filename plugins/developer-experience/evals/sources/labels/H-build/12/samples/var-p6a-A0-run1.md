diff --git a/AGENTS.md b/AGENTS.md
index b71a71a..5f20a7c 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -12,7 +12,9 @@
 ## [project notes]
 
 ### Tools
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit [--type <type>] [--message <text>] [--dry-run] [--json]`: prompts for type and message
+  when they are not passed. Pass the flags in scripts/CI; `--dry-run` shows the commit without
+  making it and `--json` prints the result as JSON.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.

--- `tq commit --help` output of the built command ---
usage: tq commit [--type <type>] [--message <text>]

