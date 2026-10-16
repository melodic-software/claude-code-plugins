---
bump: patch
---

### Fixed

- `block-hook-bypass`: a redirect target written `$VAR/rest`, `${VAR}/rest`, `"$VAR/rest"` or `"$VAR"/rest` is judged as the literal path it expands to when the command begins with `VAR=<unquoted literal>` ended by `;`, `&&` or a newline, and nothing else in the command can change `VAR`. `S=/tmp/x; cat > "$S/run.sh"` now gets the same answer as `cat > /tmp/x/run.sh`. A resolved repository file or `.work/` path still blocks, as do single-quoted or escaped `$`, a reassignment, a prefix assignment, a conditional or subshell assignment, a child-shell target, `eval`/`source`, and variables bash sets itself.
- `block-hook-bypass` block message: an agent with neither Write nor Edit (for example a read-only verifier) is told to write to an unquoted literal path under an exempt root, and the python lane names the roots a script file can be written under and run from with `python3 <file>`.

### Changed

- Shared hook library: the Bash command parser also reports each redirect operand as written, quotes and escapes included (`HOOK_SEG_REDIR_RAW`); the dispatcher's parse cache carries it.
