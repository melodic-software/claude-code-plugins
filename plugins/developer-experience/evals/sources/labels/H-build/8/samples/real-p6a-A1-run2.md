diff --git a/AGENTS.md b/AGENTS.md
index b71a71a..cd4c2ca 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -12,7 +12,9 @@
 ## [project notes]
 
 ### Tools
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit`: prompts for type and message. In scripts/CI pass `--type <t> --message <m>`
+  to skip the prompts. With stdin not a terminal, piped answers still work, but if a missing
+  value doesn't arrive within 5s it exits 2 instead of hanging.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.
