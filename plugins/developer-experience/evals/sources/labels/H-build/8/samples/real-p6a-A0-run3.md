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
