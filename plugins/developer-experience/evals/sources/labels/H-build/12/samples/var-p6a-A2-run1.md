diff --git a/docs/conventions[redacted].md b/docs/conventions[redacted].md
index ad9f366..bc79b9b 100644
--- a/docs/conventions[redacted].md
+++ b/docs/conventions[redacted].md
@@ -5,7 +5,9 @@ written_against: [redacted]@0.1.0
 
 ## Tools
 <!-- [redacted]: source=chosen -->
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit [--type <t>] [--message <m>] [--dry-run]`: commits `<type>: <message>`. Reads from
+  the terminal only for values not given as flags, and only when stdin is a terminal; otherwise a
+  missing `--type` or `--message` exits 2. Non-interactive flags: `--type`, `--message`, `--dry-run`, `--no-input`.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.

--- `tq commit --help` output of the built command ---
usage: tq commit [--type <type>] [--message <text>] [--dry-run]

examples:
  tq commit                                         prompt for type and message
  tq commit --type fix --message "handle empty input"  no prompts (CI, scripts)
  tq commit --type docs --message "x" --dry-run      show the commit, make none

options:
  --type <type>     one of feat, fix, docs, chore; prompted for if omitted
  --message <text>  commit message; prompted for if omitted
  --dry-run         print the git commit that would run and exit
  -h, --help        show this help

Prompts appear only in a terminal. When stdin is not a terminal, --type and
--message are required and a missing one fails at once.

exit codes: 0 committed (or dry run), 1 git commit failed or invalid prompt answer,
            2 usage error

