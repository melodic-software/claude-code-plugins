diff --git a/README.md b/README.md
index 58d0131..ee79d22 100644
--- a/README.md
+++ b/README.md
@@ -10,4 +10,8 @@ make check        # runs tests/Tarnquill.Core.Checks
 make tq ARGS="env check"
 ```
 
+`tq commit` prompts for the change type and message. In scripts and CI, pass them as flags instead:
+`tq commit --type fix --message "handle empty pages"`. When stdin is not a terminal and a value is
+missing, it exits with code 2 instead of waiting for input.
+
 The forge is reached through `TARNQUILL_FORGE_URL`; when it is unset no forge is reachable.
diff --git a/AGENTS.md b/AGENTS.md
index b71a71a..7ab3092 100644
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -12,7 +12,9 @@
 ## [project notes]
 
 ### Tools
-- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
+- `tq commit [--type <type>] [--message <text>]`: prompts for type and message when they are
+  not passed. Flags `--type` and `--message` skip the prompts; exits 2 when stdin is not a terminal
+  and a value is missing.
 - `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
 - `tq env check`: checks required tools.
 - `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.
