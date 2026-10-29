diff --git a/AGENTS.md b/AGENTS.md
index b71a71a..5f20a7c 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -12,7 +12,9 @@
 ## [project notes]
 
 ### Tools
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit [--type <type>] [--message <text>]`: prompts for type and message when they are
+  not passed. In scripts/CI pass both flags; with stdin not a terminal a missing value exits 2
+  instead of waiting for input.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.
