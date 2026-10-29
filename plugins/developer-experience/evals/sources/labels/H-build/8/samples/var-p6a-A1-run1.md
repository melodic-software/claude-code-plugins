diff --git a/AGENTS.md b/AGENTS.md
index b71a71a..49dd5cf 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -12,7 +12,8 @@
 ## [project notes]
 
 ### Tools
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit`: prompts for type and message. When stdin is not a terminal it exits 2
+  instead of waiting for input.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.
