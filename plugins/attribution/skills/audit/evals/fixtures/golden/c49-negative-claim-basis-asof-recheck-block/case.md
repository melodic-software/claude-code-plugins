# Required permissions

## Block rules on secret files

Blocking a secret file slows a session down; it does not stop one. What protects the secret is
keeping it out of any file the session's account can open. Leave the block rules in place, and
never cite them as evidence the file is safe.

**Redirections are covered. The 5.3.9 argument widening is not.** Read and Write block rules also cover the shell's known file commands, among them `cat`, `head`,
`tail`, `sed` and `tee`, along with the files named by redirections like `> file` and `< file`;
input redirections are checked from v5.3.7. A command that reaches files without naming them,
like `grep -r pattern .` run from the
folder that holds the file, is not covered, and neither is an arbitrary subprocess. Quarry 5.3.9
for a short time extended `Read()` block rules to shell arguments (option values, `git` file
operands, `cd && cat`), and 5.3.10 took that back. Do not reintroduce the widening.
**Claim, basis, as of, recheck:** the sentence from the page plus the revert,
[access rules: Read and Write](https://example.invalid/quarry/docs/access-rules#read-and-write) and
[changelog](https://example.invalid/quarry/docs/changelog) 5.3.10 ("Undid the 5.3.9 extension of
`Read()` block rules to shell arguments"), checked 2026-09-28; recheck if either page states the
widening again.
