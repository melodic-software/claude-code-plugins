---
bump: patch
---

### Fixed

`block-root-delete-target` on the Bash tool now refuses a recursive delete whose operand, not fully quoted, opens with a name the command never sets and goes on past it (`rm -rf $S/x`, `${X}x`, `"$S"/x`), because a blank in the value splits it into a root operand. Narrowed to 0 false positives on a corpus replay: a name the same command assigns without a blank, escape, append or substitution, a `for` list with no quote or substitution, `$HOME`, `$TMPDIR` and `${S:?}` stay allowed. PowerShell operands are unchanged; a bash child of the PowerShell tool is judged like the Bash tool.
