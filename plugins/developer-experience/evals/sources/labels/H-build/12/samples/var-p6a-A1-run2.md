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
+  value doesn't arrive within 5s it exits 2 instead of hanging; change the wait with `--timeout <s>`.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.

--- `tq commit --help` output of the built command ---
usage: tq commit [--type <type>] [--message <text>] [--dry-run] [--json]

Commits staged changes with a "<type>: <message>" subject.
With no flags it asks for the type and message. When both --type and
--message are given it does not prompt, so it can run from scripts and CI.
If stdin is not a terminal, missing values are read from it (one per line);
if nothing arrives within 5 seconds it exits 2 instead of waiting forever.

  --type <type>      change type: feat, fix, docs, chore
  --message <text>   commit message
  --dry-run          print the commit subject without committing
  --json             print the result as JSON
  --help             show this help

exit codes: 0 ok, 1 failure, 2 usage

