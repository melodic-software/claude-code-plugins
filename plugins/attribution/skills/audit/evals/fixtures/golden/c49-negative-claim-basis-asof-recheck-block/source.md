# Quarry documentation: access rules

Synthetic source page for the attribution golden set. Quarry is a fictional coding assistant
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/quarry/docs/access-rules`.

## Read and Write

Read and Write block rules also cover the shell's known file commands, among them `cat`, `head`,
`tail`, `sed` and `tee`, along with the files named by redirections like `> file` and `< file`;
input redirections are checked from v5.3.7. A command that reaches files without naming them,
like `grep -r pattern .`, is not covered,
and neither is an arbitrary subprocess.
