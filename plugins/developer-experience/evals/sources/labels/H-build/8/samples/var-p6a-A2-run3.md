diff --git a/docs/conventions[redacted].md b/docs/conventions[redacted].md
index ad9f366..077eb74 100644
--- a/docs/conventions[redacted].md
+++ b/docs/conventions[redacted].md
@@ -5,7 +5,10 @@ written_against: [redacted]@0.1.0
 
 ## Tools
 <!-- [redacted]: source=chosen -->
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+  Commits staged changes as `<type>: <message>`; with stdin redirected (scripts, CI) it exits 2
+  at once instead of waiting.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.
