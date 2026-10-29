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
+  are required, else it exits 2 at once. `--dry-run` prints the commit and runs nothing; `--json` prints the result as JSON.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.

--- `tq commit --help` output of the built command ---
usage: tq commit [--type <type>] [--message <text>] [--dry-run]

Commit staged changes as "<type>: <message>".

examples:
  tq commit                                   ask for type and message
  tq commit -t feat -m "add paging"           commit without prompts
  tq commit -t fix -m "..." --dry-run         show the commit, change nothing

options:
  -t, --type <type>      change type: feat, fix, docs, chore
  -m, --message <text>   commit message
      --dry-run          print the commit that would be made; run nothing
  -h, --help             show this help

Values the flags leave out are asked for at a terminal. When stdin is not a
terminal (scripts, CI), both --type and --message are required.

exit codes: 0 committed (or dry run), 1 git commit failed or a prompted
answer was invalid, 2 usage error (missing or invalid flag)

