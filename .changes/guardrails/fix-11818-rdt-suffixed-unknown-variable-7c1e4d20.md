---
bump: patch
---

### Fixed

`block-root-delete-target` on the Bash tool now refuses a recursive delete whose operand, not fully quoted, opens with a name the command never sets and goes on past it (`rm -rf $S/x`, `${X}x`, `"$S"/x`), because a blank in the value splits it into a root operand. Narrowed to 0 false positives on a corpus replay: a name the same command assigns without a blank or substitution, a `for` list, `$HOME`, `$TMPDIR` and `${S:?}` stay allowed. The PowerShell tool is unchanged.
