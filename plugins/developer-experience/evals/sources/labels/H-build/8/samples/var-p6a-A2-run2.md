diff --git a/docs/conventions[redacted].md b/docs/conventions[redacted].md
index ad9f366..e40b6d1 100644
--- a/docs/conventions[redacted].md
+++ b/docs/conventions[redacted].md
@@ -5,7 +5,9 @@ written_against: [redacted]@0.1.0
 
 ## Tools
 <!-- [redacted]: source=chosen -->
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit [--type <t>] [--message <m>] [--dry-run]`: commits `<type>: <message>`. Reads from
+  the terminal only for values not given as flags; with stdin redirected a missing `--type` or
+  `--message` exits 2. `--dry-run` prints the commit and runs nothing.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.
