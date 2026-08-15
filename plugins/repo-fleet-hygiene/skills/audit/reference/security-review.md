# Plugin-acceptance security review

Reviewed 2026-07-16 against the repository migration playbook and current official Claude Code plugin,
skills, Git, GitHub CLI, and GitHub REST documentation. Re-checked 2026-07-31 for #1795 (merged-PR
batch limit raised to the shared `MERGED_PR_BATCH_LIMIT` / `MERGED_PR_HEAD_LIMIT` constants; probe
allowlist still admits only the fixed `pr list` argv shapes, now keyed to those constants rather than
hardcoded 200/100 literals; truncation at the cap emits `UNKNOWN` and does not widen network egress).
Re-checked 2026-08-11 for the `allowed-tools` pairing fix: the grant is now a narrow, skill-anchored
`Bash(${CLAUDE_SKILL_DIR}/scripts/audit-fleet.sh:*)` matching the body's direct invocation. No new
execution, network, or config surface — the previous rule never matched, so this makes an already
user-invoked script prompt-free rather than admitting anything new.
Re-checked 2026-08-14 for #2604: merge evidence moves from REST `gh pr list` (window + privacy-gated
`--head` fallback) to one aliased `gh api graphql` query per page of local branches. The allowlist
admits only `query` documents with exact `headRefName` / `first:1` / `states:[MERGED]` shape and a
fixed `--jq` flatten; `mutation`/`subscription` and REST `pr list` are rejected. Branch names
transmitted are exactly the non-default local branches under audit for the operator's own resolved
repository identity — not a silent gate that leaves branches unverdicted.
Re-checked 2026-08-15 for #2607 (`merged-remote-branch`): reuses the same aliased GraphQL
merged-PR evidence, also querying remote-only head names from the local remote-tracking inventory.
Live HIGH confidence additionally requires allowlisted `git ls-remote --heads <remote>
refs/heads/<branch>` (read-only; empty result suppresses the finding; probe failure demotes to
MEDIUM). No new API endpoints, no mutation allowlist entries (`git push` remains rejected), and no
org-admin repository-settings writes — `delete_branch_on_merge` is named in evidence/handoff prose
only.

## Decision

**ACCEPT** — the plugin is read-only, has no automatic execution surface, and its only network access
is explicit authenticated GitHub metadata lookup initiated by the user-invoked audit.

## Review surfaces

1. **Code execution:** one user-invoked Bash script. Required binaries: Bash, Git, and optional `gh`. `--apply-plan` additionally requires `python3` to parse the plan JSON.
   It uses quoted argv arrays, no `eval`, no `source`, no dynamic shell execution, no downloads, and no
   write/mutation commands. Consumer config is parsed as data by `git config --file`. A positive
   command gate admits only the collector's exact Git/gh argv shapes; arbitrary global options,
   aliases, subcommands, API methods, and extra flags fail before process execution.
2. **MCP:** none.
3. **Consumer config:** no `userConfig`, credentials, or secrets. Optional tracked/explicit config
   contains local discovery roots and canonical checkout paths only.
4. **Cache isolation:** bundled assets are addressed through `${CLAUDE_SKILL_DIR}`, the token Claude
   Code substitutes both in skill content and in `allowed-tools` Bash rules, so the grant and the
   documented invocation resolve to the same install-local path. The plugin writes no cache or
   persistent state and has no sibling-plugin reach-outs.
5. **Data egress:** `git` reads local metadata. `gh api` (REST identity GET and aliased GraphQL
   merged-PR queries) contacts only `github.com` and transmits repository identity plus the
   non-default local branch names under audit for that repository. No file content, report, commit
   content, diff, environment value, or absolute local path is sent. Non-GitHub hosts are not
   contacted, and every `gh` call has a 30-second deadline plus a five-second KILL grace. Compatible
   coreutils is feature-detected; a finite Bash watchdog covers other supported platforms and has a
   TERM-ignoring regression test. **Accepted** as necessary first-party metadata lookup. The
   collector pins `GH_HOST=github.com` and disables GitHub CLI prompting, update checks, extension
   update checks, spinners, color, and telemetry for every invocation. Rate cost for the aliased
   GraphQL page is documented as bounded (measured cost 1 per call; ≤100 aliases / ≤100 nodes per
   page).
6. **Provenance/trust:** Melodic Software authors and distributes the plugin under the repository's MIT
   license. Runtime trust is limited to locally installed Git and the official GitHub CLI; there is no
   third-party SaaS delegation beyond the repository's declared GitHub host. **Accepted.**

## Adversarial checks

- A malicious config file cannot execute because it is never sourced.
- A malicious remote URL cannot redirect API calls to an arbitrary host; only `github.com` is queried.
- Credentials embedded in a remote URL are stripped before reporting and never passed to `gh`.
- Branch/path strings are passed as individual quoted arguments, not interpolated into commands.
- Every Git probe runs with `GIT_NO_LAZY_FETCH=1`, `GIT_OPTIONAL_LOCKS=0`, prompting disabled, and
  inherited repository/config injection selectors neutralized. The regression harness verifies those
  values at the fake-executable boundary.
- The positive Git/gh allowlists reject representative fetch, branch deletion, remote mutation,
  alias/config injection, PR merge, GraphQL `mutation`, REST `pr list`, and non-GET API vectors
  without invoking either fake executable.
- Branch refs and tips are buffered as NUL-delimited records with the `for-each-ref` exit status. A
  partial producer failure discards every record, emits `UNKNOWN`, and does not increment the audited
  repository count.
- Filesystem discovery is bounded and does not follow symbolic links.
- A 404 cannot be used to claim deletion/transfer because GitHub intentionally uses 404 for
  access-sensitive cases; it remains `UNKNOWN`.
- A same-named branch in another repository cannot inherit PR status because every PR query includes
  the resolved repository identity.
- GraphQL `headRefName` is exact; a merged `feature/auth-v2` cannot satisfy `feature/auth`.
- A canonical override cannot contribute local evidence until its GitHub remote is present and proven
  identical to the discovered repository (direct normalized identity or matching canonical API result).
- A failed worktree porcelain query cannot be mistaken for an empty attachment set; the repository's
  branch/worktree classification stops at `UNKNOWN`.
- Repository/config/worktree-derived report values containing newlines or control/ANSI bytes are
  rendered as a single `%q`-encoded field, so they cannot forge report labels or terminal controls.
- A worktree-looking directory cannot become a finding without Git porcelain membership.
- `git status --porcelain` at a registered work-tree root is read-only local metadata; it never
  transmits content and cannot mutate. A failed status probe cannot be mistaken for a clean tree.
- A high-confidence finding still cannot mutate because the script has no mutation mode;
  `--apply-plan` only re-renders a prior plan as a dry-run approval artifact.

## Deferred verification

- An interactive `claude --plugin-dir ...` invocation should be smoke-tested manually after install;
  automated manifest validation and deterministic script tests cover the shipped structure/collector.
