---
bump: patch
---

### Fixed

- `block-dangerous-git` lets a plain `git reset --hard` or `git clean -f` through on the Bash tool when git places both the work tree's top level and the common git directory under the system temp directory, the scratch repositories agents create and throw away ([#9779](https://github.com/melodic-software/claude-code-plugins/issues/9779)). The command has to be that one git invocation alone. It still blocks when `HOME` is under a temp root, in a linked worktree of a repository outside it, in a repository outside it, when the command carries a `-c` global, runs git through a wrapper or alias, or holds a separator, quote, escape, expansion, redirection or glob character, and on the PowerShell tool.
- `block-root-delete-target` reads `rm -rf "$S"` as the literal `S` was set to when the command opens with `S=<literal>` and one `&&`, `;` or newline, even with other statements between the assignment and the delete (#9779). The binding still needs every `$S` to be a whole double-quoted word and the rest of the command to hold no quote, backslash, `$`, backtick, glob or brace character, and a second assignment to `S`, arithmetic, `let`, `unset`, `for`, `getopts`, a `{S}>` redirection or any other builtin that sets a variable by name drops it, so the operand blocks as a bare variable as before.
