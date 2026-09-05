# Plugin-acceptance security review

Reviewed 2026-07-16 against the repository migration playbook and the official Claude Code plugin,
skills, Git, GitHub CLI, and GitHub REST documentation. Recheck trigger: any change to the
collector's Git/gh allowlist, to the GraphQL query shape, or to the set of values transmitted off
the machine.

## Decision

**ACCEPT** — the audit skill is read-only and has no automatic execution surface; its only network
access is explicit authenticated GitHub metadata lookup initiated by the user-invoked audit. Fleet
mutation lives in a separate `/repo-fleet-hygiene:apply` skill with its own script and
`allowed-tools` grant (`apply-plan.sh`), so widening `audit-fleet.sh` argv cannot silently expand
the auditor's Bash allowlist. Apply defaults to dry-run, requires `--apply` plus interactive
confirmation or `--yes`, re-derives OIDs before every delete, and skips fail-closed on drift.

## Review surfaces

1. **Code execution:** two user-invoked Bash scripts. Audit required binaries: Bash, Git, and
   optional `gh`. `--apply-plan` and `apply-plan.sh` additionally require `python3` to parse plan
   JSON. Apply mutates only under `--apply` after the batch confirmation gate (or `--yes`).
   Both scripts use quoted argv arrays, no `eval`, no `source`, no dynamic shell execution, and no
   downloads. Consumer config is parsed as data by `git config --file`. Audit admits only the
   collector's exact Git/gh argv shapes; apply admits only the plan-driven delete/prune/remove
   paths after live OID refresh.
2. **MCP:** none.
3. **Consumer config:** no `userConfig`, credentials, or secrets. Optional tracked/explicit config
   contains local discovery roots and canonical checkout paths only.
4. **Cache isolation:** bundled assets are addressed through `${CLAUDE_SKILL_DIR}`, the token Claude
   Code substitutes both in skill content and in `allowed-tools` Bash rules, so the grant and the
   documented invocation resolve to the same install-local path. The plugin writes no cache or
   persistent state and has no sibling-plugin reach-outs.
5. **Data egress:** `git` reads local metadata. `gh api` (REST identity GET and aliased GraphQL
   merged-PR queries) contacts only `github.com` and transmits repository identity, the non-default local branch names
   under audit for that repository, and any remote-only head names read from the local
   remote-tracking inventory. No file content, report, commit
   content, diff, environment value, or absolute local path is sent. Non-GitHub hosts are not
   contacted, and every `gh` call has a `GH_TIMEOUT_SECONDS` deadline plus a
   `GH_KILL_AFTER_SECONDS` KILL grace. Compatible coreutils is feature-detected; a finite Bash
   watchdog covers other supported platforms and has a TERM-ignoring regression test. **Accepted**
   as necessary first-party metadata lookup. The collector pins `GH_HOST=github.com` and disables
   GitHub CLI prompting, update checks, extension update checks, spinners, color, and telemetry for
   every invocation. Rate cost for the aliased GraphQL page is documented as bounded (cost measured
   live at 1 per call for at least 40 aliases; at most `MERGED_PR_GRAPHQL_ALIAS_PAGE` aliases and
   the same number of nodes per page).
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
- Filesystem discovery is bounded and does not follow symbolic links. Skipped intermediate
  symlink (or Windows junction) directories are disclosed as `UNKNOWN` `discovery-symlink-skip`
  findings and counted on the discovery-skips header line; the walk never descends through them.
- A 404 cannot be used to claim deletion/transfer because GitHub intentionally uses 404 for
  access-sensitive cases; it remains `UNKNOWN`.
- A same-named branch in another repository cannot inherit PR status because every PR query includes
  the resolved repository identity.
- GraphQL `headRefName` is exact; a merged `feature/auth-v2` cannot satisfy `feature/auth`.
- The GraphQL allowlist admits only `query` documents in the collector's exact
  `headRefName` / `first:1` / `states:[MERGED]` shape with the fixed `MERGED_PR_GRAPHQL_JQ` flatten,
  and `git ls-remote --heads <remote> refs/heads/<branch>` as the only remote probe.
- A canonical override cannot contribute local evidence until its GitHub remote is present and proven
  identical to the discovered repository (direct normalized identity or matching canonical API result).
- A failed worktree porcelain query cannot be mistaken for an empty attachment set; the repository's
  branch/worktree classification stops at `UNKNOWN`.
- Repository/config/worktree-derived report values containing newlines or control/ANSI bytes are
  rendered as a single `%q`-encoded field, so they cannot forge report labels or terminal controls.
- A worktree-looking directory cannot become a finding without Git porcelain membership.
- `git status --porcelain` at a registered work-tree root is read-only local metadata; it never
  transmits content and cannot mutate. A failed status probe cannot be mistaken for a clean tree.
- A high-confidence finding still cannot mutate from the audit script: it has no mutation mode;
  `--apply-plan` only re-renders a prior plan as a dry-run approval artifact. Mutation requires the
  separate apply skill with `--apply` and confirmation/`--yes`, plus live OID refresh.

## Deferred verification

- An interactive `claude --plugin-dir ...` invocation should be smoke-tested manually after install;
  automated manifest validation and deterministic script tests cover the shipped structure/collector.
