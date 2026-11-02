# Pre-compute blocks

- **Name in the label what an empty result means**, so nobody mistakes a clean tree for a probe
  that printed nothing.

Write a pre-compute block that calls `git` without any `$`. The isolation guard refuses a shell
command whenever the command's text alone does not prove that every git call in it stays inside
the workspace: a command name built at runtime, syntax the guard cannot parse, or an expansion
such as `${!name}` or `${ command; }` able to run something the text never names. Tern 4.2.7
dropped its refusals of loops, `$VAR` reads, `"$(…)"` and heredocs that leave git alone, and 4.2.9
dropped them for ordinary loops, xargs pipelines and launcher-wrapped commands with no path to the
main checkout. It is still open whether a bare `$VAR` read passes now: on 2026-09-30 a session saw
`sed -n ... $F` refused, which may conflict with the 4.2.7 change, and no probe has settled it.

**Record.** Claim: every refusal case in the paragraph above, the two release fixes included.
Basis: <https://example.invalid/tern/docs/workspaces#how-tern-enforces-isolation> and the Tern
release notes for 4.2.7 and 4.2.9. As of: 2026-09-28. Recheck trigger: the section changes what
the guard refuses, or a release note changes the guard's command checks.
