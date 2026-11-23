# Reference first-party actions at main and vendor actions by major tag

- Status: accepted
- Date: 2026-11-23
- Related: architecture `docs/owner-decisions.md`, row "Action pinning (D3)"
  ([melodic-software/architecture#198](https://github.com/melodic-software/architecture/pull/198));
  [standards#1098](https://github.com/melodic-software/standards/pull/1098) (the zizmor `ref-pin`
  policy); supersedes Decision 4 of
  [ADR 0085](0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md)

## Context

This repository pinned every `uses:` ref by commit SHA: about 750 ci-workflows refs held at one
release by a daily repin workflow (`maintenance-repin-ci-workflows.yml` running
`scripts/repin-ci-workflows.sh`, because Dependabot ignores `melodic-software/ci-workflows/*`), and
about 550 official vendor refs (`actions/*`) moved by Dependabot. ADR 0085 Decision 4 planned to
build on those pins: the broker would accept a ci-workflows lane reusable only at a commit the
central grant file lists (`ci-workflows-commits` in
`.github/actions/resolve-config/lane-grants.json`). That broker change never shipped: today's
broker requires `job_workflow_ref` to be a workflow in the caller's own repository
(azure-iac `src/lanes-token-broker/src/claims.mjs`, the `job_workflow_ref is not this repository's`
denial) and reads no `lane-grants.json`, and every row's `ci-workflows-commits` list is empty.

On 2026-11-23 the owner decided which refs stay pinned (architecture `docs/owner-decisions.md`,
"Action pinning (D3)"): "If it's owned by us, it should not be pinned. If it involves an untrusted
third-party library ... it should be pinned, as long as those still flow automatically through
Dependabot and cooldowns ... official vendor like Microsoft or Anthropic or OpenAI ... those I
don't want pinned".

## Decision

1. **First-party refs track main.** Every `melodic-software/*` ref in this repository's workflows
   and composite actions, ci-workflows actions and reusables included, is `@main`, with no version
   comment.
2. **Official vendor refs take the vendor's moving major tag.** `actions/*`, `github/*`,
   `dependabot/*`, `microsoft/*`, `azure/*`, `anthropics/*` and `openai/*` refs use the major tag the
   vendor publishes (`actions/checkout@v7`), or the exact version tag where no major tag exists.
   Dependabot's `github-actions` ecosystem keeps moving them.
3. **Third-party refs stay SHA-pinned**, enforced by zizmor `unpinned-uses` under the standards
   policy and moved by Dependabot with cooldowns.
4. **ci-workflows keeps today's rulesets** (pull request, `CI Status`, signed commits) and gains no
   CODEOWNERS gate now that callers track its main (owner decision, 2026-11-23).
5. **ci-workflows itself stays SHA-pinned internally** (owner decision recorded in
   [architecture#198](https://github.com/melodic-software/architecture/pull/198)); this record
   covers its callers only.
6. **No allowed-SHA list for ci-workflows.** ADR 0085 Decision 4 is withdrawn: when lanes move to
   ci-workflows reusables, the broker cannot bind them to a listed commit that callers no longer
   name. The `ci-workflows-commits` field leaves the central grant file, which keeps the rest of
   ADR 0085 Decision 2.

## Alternatives considered

- **Keep SHA pins and the daily repin** (ADR 0085 Decision 4's basis). Rejected by the owner: a pin
  on code this organization owns adds a repin workflow, a release App token and a daily pull request
  without stopping anything a merge to ci-workflows main could not already do through its reusables,
  which already ran at `@main`.
- **Pin official vendors by SHA and only unpin first-party refs.** Rejected by the owner ("those I
  don't want pinned").
- **Exact version tags for vendors.** Rejected: Dependabot would open a pull request per patch
  release where the major tag already carries it; used only when a vendor publishes no major tag.

## Consequences

- A merge to ci-workflows main reaches every lane and check here on its next run, with no repin
  pull request between them. ci-workflows' own pull request and `CI Status` rules are the gate.
- A vendor's moving major tag can move under this repository between runs. The owner accepted that
  for official vendors.
- Retired with this record: `maintenance-repin-ci-workflows.yml`, `scripts/repin-ci-workflows.sh`
  and its test, the tests that required every ci-workflows ref to name one commit, and
  `ci-workflows-commits` in `lane-grants.json`.
- Tests that read a ci-workflows file at the ref the workflows name read it at main's current tip.
- ADR 0085 Migration step 4 and Decision 7, when built, bind a ci-workflows lane reusable by
  `job_workflow_ref` at `refs/heads/main` instead of by an allowed commit list.
