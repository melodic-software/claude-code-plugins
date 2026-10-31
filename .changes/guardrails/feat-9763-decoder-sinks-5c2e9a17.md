---
bump: minor
---

### Added

- `block-root-delete-target` refuses a decoder feeding an execution sink outright, whatever the decoded text targets, and denies it in an attended session too, because the decoded text never appears in the command. On the Bash tool that is `base64 -d`, `base32 -d`, `basenc -d` or `xxd -r` whose output a shell reading stdin, `source /dev/stdin`, `eval`, a `-c` operand or a substitution in command position runs, so `echo <b64> | base64 -d | sh`, `eval "$(echo <b64> | base64 -d)"` and `bash <(xxd -r -p dump.hex)` are refused. On the PowerShell tool it is `[Convert]::FromBase64String` reaching `Invoke-Expression` or `iex`. Decoded output written to a file or shown in a pager (`base64 -d x > out.bin`, `base64 -d x | less`) passes, and so does a decoder named inside quoted prose, such as a `git commit -m` message.
