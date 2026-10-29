diff --git a/AGENTS.md b/AGENTS.md
index b71a71a..49dd5cf 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -12,7 +12,9 @@
 ## [project notes]
 
 ### Tools
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit [--type <type>] [--message <text>] [--dry-run] [--json]`: prompts for type and message
+  when they are not passed. In scripts/CI (stdin not a terminal) both flags are required; it exits 2
+  instead of waiting for input.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.

--- `tq commit --help` output of the built command ---
usage: tq commit [--type <type>] [--message <text>] [--dry-run] [--json]

Creates a git commit with the message '<type>: <text>'.
Any of --type/--message left out is prompted for when run at a terminal.
When stdin is not a terminal (CI, scripts), both flags are required.

  --type <type>     change type: feat, fix, docs, chore
  --message <text>  commit message
  --dry-run         show the commit that would be made without making it
  --json            print the result as JSON on stdout
  -h, --help        show this help

Exit codes: 0 ok, 1 failure, 2 usage error.

