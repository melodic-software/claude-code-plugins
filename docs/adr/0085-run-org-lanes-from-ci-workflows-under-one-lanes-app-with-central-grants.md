# Run organization lanes from ci-workflows under one lanes App with central grants

- Status: accepted
- Date: 2026-10-26

## Context

The lanes (the jobs that run Claude Code with a `melodic-automation-lanes` token) live as workflow
files in this repository, with a copy in pr-pipeline-sandbox. Another organization repository can
adopt a lane only by copying the files and getting broker code changed.
[#7656](https://github.com/melodic-software/claude-code-plugins/issues/7656) asks for each lane to
become a reusable workflow in `melodic-software/ci-workflows` that a consumer calls and configures
through its own convention config, one lane at a time.

The owner decided the trust model on #7656
([decision](https://github.com/melodic-software/claude-code-plugins/issues/7656#issuecomment-6418743610)):
one lanes App across the organization, rejecting one App per repository; an organization repository
is admitted by one broker allowlist row plus one central grant entry in this repository; grants are
read from this repository's main, so a consumer cannot grant itself more than its row; public
consumers outside the organization bring their own App or `GITHUB_TOKEN`. Decisions 3 to 6 settle
the questions that decision left open; they were decided on the evidence below under the owner's
standing rule to decide on facts and loosen no security boundary.

Sources read 2026-10-26: azure-iac `bee922b`, github-iac `33433fb`, ci-workflows `b26e355`. A
citation prefixed `repo@sha:` names that repository; a bare file name after it continues the last
prefixed repository; a `.github/` or `docs/` path with no prefix is this repository at
`a6ba1c4c18244dcebc9811485df996819073848d`.

### Current state

- **The App is already organization-wide.** One installation with `repository_selection: all`
  (`gh api orgs/melodic-software/installations`), which the broker uses for every mint
  (azure-iac@bee922b:`src/lanes-token-broker/src/github.mjs:205-210,227-230`). No App or
  installation change is needed.
- **Admission is three places today.** The broker allowlist is a code constant naming this
  repository and pr-pipeline-sandbox (azure-iac@bee922b:`BrokerConstants.cs:79`), deployed as
  `BROKER_ALLOWED_REPOSITORY_IDS` (`BrokerStack.cs:186`). github-iac lists the same two as
  `LanesBrokerClientRepositories` (github-iac@33433fb:`OrgCiRouting.cs:33`) and gives each its
  `CLAUDE_LANES_REPO_DISABLED` kill-switch variable (`OrgCiRouting.cs:91-98`); the broker denies a
  repository whose switch is unset (azure-iac@bee922b:`kill-switch.mjs:1-3,51-54`). Both
  repositories also sit in the `trust-root` ruleset (github-iac@33433fb:`OrgRulesets.cs:73`), which
  [github-iac ADR 0015](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0015-oidc-token-broker-for-pr-pipeline-lane-app-tokens.md)
  Decision 5 makes a precondition for write lanes.
- **The broker binds the job to the caller's own repository.** `workflow_ref` must be a file
  directly under the caller's `.github/workflows/` whose stem is the lane
  (azure-iac@bee922b:`claims.mjs:193-201,240-243`); `job_workflow_ref` must name the write reusable,
  or for `pr-merge.yml`, `work-unblock.yml` and `intake-triage.yml` the caller itself, in the same
  repository (`claims.mjs:43,232-235`). `work-unblock` and `intake-triage` mint only for
  hard-coded repository ids (`claims.mjs:22-34,216-225`). Caller and reusable must be byte-equal to
  the main tip (`binding.mjs:49-58`), with the report-job exception of github-iac ADR 0015's
  2026-10-18 amendment.
- **Grants come from the caller's main, not this repository's.** Through a read token for the caller
  (`authorize.mjs:265`), the broker reads at the caller's main tip `pr-pipeline.yaml`, its schema,
  `vocabulary.json`, `lane-rules.json`, `effect-grants.json`, `activity-rules.json` and
  `trusted-actors.json` (`binding.mjs:8-35`; `authorize.mjs:260-268,298`, the latter through
  `readTipFiles`), and checks actor, PR
  author and re-runner against that `trusted-actors.json` (`authorize.mjs:181-233`). Only the
  resolve-config *code* comes from this repository's main whatever the caller
  (`resolve-config-loader.mjs:19-21`; `authorize.mjs:6-8`).
- **Code caps hold whatever the data says.** A grant is `contents`, `pull-requests` and `issues`
  read or write plus at most `actions: read` (`grant.mjs:29-31,46-62`); contents write with
  pull-requests write is merge's alone, actions read is `pr-merge`'s alone, unblock and intake write
  issues only (`authorize.mjs:310-328`). One mint per check run (`authorize.mjs:354-356`), scoped to
  the caller's id (`github.mjs:230`).
- **Lane model steps hold no write token.** Every model activity has `effect: read`
  (`docs/conventions/pr-pipeline.yaml:11,42,102,176,236,332`); every write is a scripted `apply-*`
  or `report-*` activity, and patch-carrying ones run under `patch-rules.json`, whose rows all
  refuse the `UNIVERSAL_REFUSE` classes (`.github/actions/resolve-config/patch-rules.mjs:9-18,39-43`).
  Those classes cover workflows and CODEOWNERS, not `.github/actions/**` or `.github/standards/**`.
- **Only intake calls ci-workflows today**, for its model jobs (`.github/workflows/intake-triage.yml:216`);
  its write job mints from the caller file (`intake-triage.yml:361-375`). The review lanes call
  `pr-review-cli.yml` (`.github/workflows/pr-review-hosted.yml:172`) and sit outside the broker.

### Corrected premise

The decision says the broker "keeps reading grants from this repository's main
(`authorize.mjs:6-8`)". Those lines cover the resolve-config code only; the grant data and trusted
actors are read from the caller's own main (azure-iac@bee922b:`authorize.mjs:260-268,298`), and
`claims.mjs:232-235` requires the caller's own workflow. pr-pipeline-sandbox's grants come from
pr-pipeline-sandbox's main today. Reading grants centrally is new broker behavior that this record
adds.

## Decision

1. **Each lane becomes a ci-workflows reusable.** A consumer calls it from a caller file that keeps
   the lane's name (`pr-refine.yml` and so on), since the broker matches lane to caller stem, and
   pins it by commit SHA, as this repository already pins ci-workflows. The consumer's
   `docs/conventions/pr-pipeline.yaml` sets behavior (which lanes run, models, `applies-when`) and
   can only narrow what its grant row allows. The pr-run-activity reusables, `request-lane-token`,
   `check-kill-switch`, the trusted-trigger gate and resolve-config move to ci-workflows first, with
   a token-source input.
2. **One central grant file on this repository's main.** A file under
   `.github/actions/resolve-config/` holds one row per admitted repository id: the lanes and
   activities it may run, any per-repository trusted-actor additions (Decision 3) and the allowed
   ci-workflows commits (Decision 4). `effect-grants.json`, `lane-rules.json` and each activity's
   effect are read from this repository's main, never the consumer's. A repository with no row
   gets no token, and a lane missing from its row gets no token for that lane.
3. **Trusted actors are central.** The broker and the in-workflow trusted-text gate judge every
   consumer against the trusted-actor list on this repository's main (the synced standards
   component), plus the additions in that repository's grant row. Basis: ADR 0049 requires "one
   centrally managed standards component that every lane reads"
   ([ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md),
   Decision 1) and calls the gate "the main control" (Consequences); a consumer-held list would let
   a consumer with main write admit any actor, the self-grant the owner ruled out for grants.
4. **The broker binds the reusable by an allowed-SHA list.** `job_workflow_ref` must name a lane
   reusable in `melodic-software/ci-workflows`, and the signed `job_workflow_sha` claim must be a
   commit the central grant file lists; the broker reads the reusable for byte-equality from
   ci-workflows at that commit. ci-workflows does not join
   `TrustRootRepositories`. Basis: this repository's main stays the only trust source, which
   matches the SHA pinning callers already use and adds no trust-root repository.
5. **Admission is three rows, all fail-closed:** the azure-iac `BROKER_ALLOWED_REPOSITORY_IDS`
   constant, the central grant row, and the github-iac `LanesBrokerClientRepositories` entry that
   gives the repository its kill-switch variable. The owner's decision named two; the third exists
   because the broker denies a repository whose kill switch is unset (`kill-switch.mjs:51-54`), so
   leaving it out denies rather than widens. A consumer does not join `TrustRootRepositories`.
   Basis: today `trust-root` adds no effective rule over the organization `base` ruleset, which
   already covers every repository with squash-only merges, required thread resolution, zero
   approvals, no deletion, no force push and linear history
   (github-iac@33433fb:`OrgRulesets.cs:79-105`); `trust-root` adds only dismiss-stale-reviews, which
   does nothing at zero approvals, and an organization-admin bypass (`OrgRulesets.cs:152-187`). With
   grants and trusted actors central, a consumer's main supplies the broker only its caller file.
6. **No lane can edit the central grant file or the trusted-actor list.** Both paths join a new
   class in `UNIVERSAL_REFUSE` and the `patch-rules.schema.json` enum, so `checkPatchRules` fails any
   row that omits it. This repository's change alone; per `patch-rules.mjs:1-3` it needs no broker
   pin. A person's pull request can still change them.
7. **The broker change is one-time.** azure-iac accepts the ci-workflows reusable at an allowed SHA,
   reads grants, lane rules and trusted actors from this repository's main by repository id, and
   replaces `UNBLOCK_REPOSITORY_IDS`, `INTAKE_REPOSITORY_IDS` and `SELF_JOB_CALLERS`
   (`claims.mjs:22-43`) with the central rows. The caller-file check against the consumer's main,
   the kill switch and the code caps stay as they are. After it, adopting a lane needs no azure-iac
   change, and admitting a repository needs no broker source change: only the allowlist constant,
   which is still an azure-iac pull request and an owner-run deploy (`BrokerConstants.cs:79`).
8. **Public consumers outside the organization** get no token from this App: the broker refuses
   them on owner (`claims.mjs:167-168`) and allowlist (`claims.mjs:170-171`). Each reusable takes
   the write token as an input, so an outside caller passes its own App token or `GITHUB_TOKEN`.

## Alternatives considered

- **One App per repository.** Rejected by the owner as a maintenance burden.
- **Trusted actors from the consumer's synced copy or its convention config.** Rejected: the
  consumer's main, which its own admin controls, would decide who triggers a write lane.
- **Accept any ci-workflows commit on its main.** Rejected: it adds ci-workflows to the trust root
  and needs CODEOWNERS over `.github/workflows/**` there (ci-workflows@b26e355:`.github/CODEOWNERS:10-12`
  covers scripts and action tests only); every ci-workflows merge would change what lanes run.
- **Accept release tags.** Rejected: github-iac's only tag ruleset covers ci-runner
  (github-iac@33433fb:`OrgRulesets.cs:234-260`), and `RepositoryRulesets.cs` names no ci-workflows
  tag rule, so a ci-workflows tag can move.
- **Add each consumer to `trust-root`.** Rejected for now: it adds no effective rule today
  (Decision 5). Revisit if `trust-root` regains a rule `base` lacks.
- **Generate the allowlist and the github-iac entry from the central file.** Rejected: one merge in
  this repository would then admit a repository, removing the separate azure-iac step the owner
  kept.
- **Protect the central file with a code-owner review ruleset on this repository.** Rejected: it
  reverses the 2026-10-09 amendment of
  [github-iac ADR 0007](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0007-no-required-approving-reviews.md)
  for every path, where a refusal class covers the lane path.

## Consequences

- github-iac ADR 0015 needs amending: Decision 2, whose `job_workflow_ref` "names the lanes' write
  reusable workflow in the same repository" (github-iac@33433fb:
  `docs/adr/0015-oidc-token-broker-for-pr-pipeline-lane-app-tokens.md:93-99`), and Decision 5, whose
  trust-root precondition now applies to repositories whose main supplies broker-read data.
- What a compromised consumer cannot do: get a token for another repository (`repository_ids` is
  the signed `repository_id` claim), get more than its row (the row is on this repository's main),
  hold `workflows`, `checks` or `administration` (`grant.mjs:46-62`), so no lane token rewrites its
  caller file, mint for a fork PR (`authorize.mjs:140-142`), from a self-hosted runner or twice per
  job.
- What it can do: use its own row in its own repository; with main write, change its caller file,
  which byte-equality then binds to what it controls, still behind a trusted actor except on a
  schedule (`authorize.mjs:183-187`); act as the lanes bot in its own repository; and spend the
  shared installation budget.
- One merged edit to the central file now changes every admitted repository. The residual is the
  one the owner accepted for every trust-root path
  ([`pr-pipeline/README.md`](../conventions/pr-pipeline/README.md#trust-root-paths)): a person's pull
  request, or the merge lane merging one, can still change it.
- Every lane token of every admitted repository and the broker's own read tokens draw on one
  installation rate-limit bucket, which grows little per added repository; a `GITHUB_TOKEN` caller
  has its own per-repository limit. Pointer: GitHub's
  [rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api),
  sections "Primary rate limit for GitHub App installations", "Primary rate limit for
  `GITHUB_TOKEN` in GitHub Actions" and "About secondary rate limits", as of 2026-10-26; recheck
  when the organization changes plan or GitHub changes that page. Whether the secondary limit is
  per App across repositories is unverified. The broker spends about 16 to 19 reads per mint
  (`binding.mjs:18-35,49-58`; `kill-switch.mjs:16,19-57`). Existing controls cover it: the
  broker's `github-rate-limited` denial (`authorize.mjs:88-90`), the `log-api-budget` action and the
  kill switches.
- A `GITHUB_TOKEN` push starts no workflow run, so `pr-refine`, `pr-unblock` and
  `work-resolve-issue` on that path lose re-triggered checks; their docs say so.
- A consumer's ci-workflows pin bump, Dependabot's included, is denied a mint until the new commit
  is on the allowed list. The order is: release in ci-workflows, add the SHA to the central file,
  then bump the consumer. A consumer may pin any listed SHA, so removing a SHA is how a release with
  a security fix retires the old one.
- pr-unblock's dispatcher and review workflow paths are hard-coded consumer paths
  (azure-iac@bee922b:`dispatcher.mjs:23-30`); they become a fixed caller-name contract or move into
  the row.

## Migration

1. Amend github-iac ADR 0015 Decisions 2 and 5.
2. Measure one week of `log-api-budget` output for this repository's and pr-pipeline-sandbox's
   lanes before admitting any new repository.
3. Add the central grant file with rows reproducing today's grants for this repository and
   pr-pipeline-sandbox, and the refusal class.
4. Change the broker (Decision 7), accepting both the same-repository reusable and the ci-workflows
   reusable during the move, both reading grants centrally.
5. Move the shared reusables, actions and resolve-config to ci-workflows, fixing the layout
   assumptions of [#9086](https://github.com/melodic-software/claude-code-plugins/issues/9086) and
   [#9601](https://github.com/melodic-software/claude-code-plugins/issues/9601).
6. Move the lanes one at a time, pr-pipeline-sandbox first, then this repository: `work-unblock`,
   `intake-triage`, `work-resolve-issue`, `pr-refine`, `pr-unblock`, `pr-merge`. Issue lanes come
   first and merge last, by rising grant (basis: judgment).
7. Remove the same-repository reusable path from the broker after the last lane moves.
8. Admit the first new repository by its three rows.

## Recheck triggers

- `trust-root` gains a rule `base` lacks: revisit Decision 5.
- A model activity gains a write effect: the refusal class in Decision 6 no longer covers every lane
  write path.
