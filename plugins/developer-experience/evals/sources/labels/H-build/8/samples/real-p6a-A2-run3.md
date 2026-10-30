diff --git a/docs/conventions[redacted].md b/docs/conventions[redacted].md
index ad9f366..077eb74 100644
--- a/docs/conventions[redacted].md
+++ b/docs/conventions[redacted].md
@@ -5,7 +5,10 @@ written_against: [redacted]@0.1.0
 
 ## Tools
 <!-- [redacted]: source=chosen -->
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit [--type <type>] [--message <text>] [--dry-run]`: commits staged changes as
+  `<type>: <message>`. Reads from the terminal only for values the flags leave out, and only
+  when stdin is a terminal; with stdin redirected (scripts, CI) both `--type` and `--message`
+  are required, else it exits 2 at once. `--dry-run` prints the commit and runs nothing.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.
