# Plugin-acceptance security review

Reviewed 2026-07-16 against the repository migration playbook and current official Claude Code plugin,
skills, Git, GitHub CLI, and GitHub REST documentation.

## Decision

**ACCEPT** — the plugin is read-only, has no automatic execution surface, and its only network access
is explicit authenticated GitHub metadata lookup initiated by the user-invoked audit.

## Review surfaces

1. **Code execution:** one user-invoked Bash script. Required binaries: Bash, Git, and optional `gh`.
   It uses quoted argv arrays, no `eval`, no `source`, no dynamic shell execution, no downloads, and no
   write/mutation commands. Consumer config is parsed as data by `git config --file`.
2. **MCP:** none.
3. **Consumer config:** no `userConfig`, credentials, or secrets. Optional tracked/explicit config
   contains local discovery roots and canonical checkout paths only.
4. **Cache isolation:** bundled assets are addressed through `${CLAUDE_PLUGIN_ROOT}`. The plugin writes
   no cache or persistent state and has no sibling-plugin reach-outs.
5. **Data egress:** `git` reads local metadata. `gh api` and `gh pr list` contact only `github.com` and
   transmit repository/branch identifiers already represented by the configured GitHub remote. No
   file content, report, commit content, diff, environment value, or absolute local path is sent.
   Non-GitHub hosts are not contacted, and every `gh` call has a 30-second deadline. **Accepted** as
   necessary first-party metadata lookup. The collector disables GitHub CLI prompting, update checks,
   and telemetry for every invocation.
6. **Provenance/trust:** Melodic Software authors and distributes the plugin under the repository's MIT
   license. Runtime trust is limited to locally installed Git and the official GitHub CLI; there is no
   third-party SaaS delegation beyond the repository's declared GitHub host. **Accepted.**

## Adversarial checks

- A malicious config file cannot execute because it is never sourced.
- A malicious remote URL cannot redirect API calls to an arbitrary host; only `github.com` is queried.
- Credentials embedded in a remote URL are stripped before reporting and never passed to `gh`.
- Branch/path strings are passed as individual quoted arguments, not interpolated into commands.
- Filesystem discovery is bounded and does not follow symbolic links.
- A 404 cannot be used to claim deletion/transfer because GitHub intentionally uses 404 for
  access-sensitive cases; it remains `UNKNOWN`.
- A same-named branch in another repository cannot inherit PR status because every PR query includes
  the resolved repository identity.
- A canonical override cannot contribute local evidence until its GitHub remote is present and proven
  identical to the discovered repository (direct normalized identity or matching canonical API result).
- A failed worktree porcelain query cannot be mistaken for an empty attachment set; the repository's
  branch/worktree classification stops at `UNKNOWN`.
- Repository/config/worktree-derived report values containing newlines or control/ANSI bytes are
  rendered as a single `%q`-encoded field, so they cannot forge report labels or terminal controls.
- A worktree-looking directory cannot become a finding without Git porcelain membership.
- A high-confidence finding still cannot mutate because the script has no apply mode.

## Deferred verification

- An interactive `claude --plugin-dir ...` invocation should be smoke-tested manually after install;
  automated manifest validation and deterministic script tests cover the shipped structure/collector.
