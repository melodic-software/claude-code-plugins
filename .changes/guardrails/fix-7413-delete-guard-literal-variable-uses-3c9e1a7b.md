---
bump: patch
---

### Fixed

- `block-root-delete-target` judges a variable that the command assigns a literal as that literal in the forms `$S`, `$S/x`, `${S}` and `${S}/x`, quoted or unquoted. It used to bind only `"$S"` and `"$S/x"`. So `S=/tmp/run; mkdir -p $S/x; rm -rf $S` is judged as a delete of `/tmp/run`, not refused as a bare variable. The assignment can also follow other statements, when each statement before it ends in `;` or a newline. Those statements must hold no `&&`, `||`, `|`, `&`, comment, heredoc, group, subshell, quote, escape, expansion, or compound command such as `if` or `while`. A reassigned, substituted or unassigned variable stays refused, and so do a prefix assignment such as `S=/a true` and a use before the assignment. One case remains: an IFS set before the command runs, for example by a `BASH_ENV` file, can still split an unquoted use.
