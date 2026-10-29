diff --git a/AGENTS.md b/AGENTS.md
index b71a71a..2bcd5ba 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -12,7 +12,9 @@
 ## [project notes]
 
 ### Tools
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit`: prompts for type and message at a terminal. In scripts/CI pass
+  `--type <type> --message <text>`; without a terminal it fails with exit 2 instead of waiting.
+  Also supports `--dry-run`, `--json`, `--yes`, `--help`.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.

--- `tq commit --help` output of the built command ---
usage: tq commit [--type <type>] [--message <text>] [--dry-run] [--json]

With no flags, prompts for the change type and message.
Pass --type and --message to run without prompts (scripts, CI).
Without a terminal, both are required; tq commit never waits for input.

  --type <type>     change type: feat, fix, docs, chore
  --message <text>  commit message
  --dry-run         show the commit that would be made; do not commit
  --json            write the result as JSON on stdout

exit codes: 0 ok, 1 failure, 2 usage

