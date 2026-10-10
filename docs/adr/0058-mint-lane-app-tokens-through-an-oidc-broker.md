# Mint lane App tokens through an OIDC broker

- Status: accepted
- Date: 2026-10-10
- Amends: [ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md),
  condition 3
- Closes: the App key part of the secret-set residual in
  [ADR 0055](0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md)

## Context

ADR 0049 condition 3 had each lane job mint its own `melodic-automation-lanes` token. To mint, the
job held the App private key: `pr-run-activity-write.yml` declared an `app-private-key` secret and
passed it to `actions/create-github-app-token` in the same job that later checks out and runs the
PR head. GitHub scrubs secrets per workflow run, not per job, so a key referenced anywhere in a run
must be assumed to reach every job in it. Probe P1 on pr-pipeline-sandbox (runs 37243281274,
37243281369, 37243281349, 37243281476) showed a key referenced only in a step that never ran, plus
the `secrets:` pass to the reusable, still reached that job; a sibling job and a job calling a
different reusable logged the literal canary. A clean log cannot prove absence, so the run stays
the boundary. ADR 0055 recorded the result as an accepted residual: the App key sat in the run job's
secret set, for `read` jobs too, until a token broker kept it off every runner that runs head code.

The App is installed on every organization repository, so the key can mint for all of them. Any
code that reads it from a runner's memory or environment holds that power, not a one-hour token.

## Decision

No workflow holds the App key. A write activity gets its token from a broker:

1. The broker is an Azure Function in `melodic-software/azure-iac`
   (`src/lanes-token-broker`). It holds the App key only as a non-exportable, sign-only key in a
   Key Vault dedicated to it, and signs the App JWT there.
2. `pr-run-activity-write.yml`'s run job holds `id-token: write`. After the kill switch, the trigger
   gate, the base check and `resolve-config`, and before `select-trusted-text` and any head
   checkout, it runs
   [`request-lane-token`](../../.github/actions/request-lane-token/README.md): it requests an OIDC
   token for the audience in `LANES_BROKER_AUDIENCE` and sends it once to `LANES_BROKER_URL` with
   the lane, the activity and the PR number. It never retries. Either variable empty fails red.
3. The broker verifies the token and mints only when every check passes: owner and repository
   allowlist, GitHub-hosted runner, event and ref, the job is this repository's
   `pr-run-activity-write.yml`, the caller is a lane listed in the default-branch config, both
   files are byte-equal to the default-branch tip, the lane is the caller's file stem, the actor is
   not the lanes bot, the kill switch reads `false`, the PR is open, same-repository and into
   `main`, the actor, PR author and any re-runner are trusted, and the tip config gives the
   activity a write effect. It reserves the job's `check_run_id`, so a job gets one mint, then
   mints for this repository only with exactly `contents`, `pull_requests` and `issues` from
   `effect-grants.json` at the tip. The grant never comes from the request.
4. The client masks the token and fails red, after revoking it, unless the broker's effect,
   permissions, lane, activity and repository equal what the job resolved (`effect-mismatch`).
5. A final `if: always()` step, `actions/github-script` pinned by SHA, revokes the token with
   `DELETE /installation/token`, then calls `GET /installation/repositories` with it, and fails red
   unless they return 204 and then 401. It is a backstop for an honest activity that did not clean
   up, not a control against a hostile one: the activity holds the token and can write the
   runner's files.
6. `pr-run-activity-read.yml` is unchanged: no key, no `id-token`, no broker call. Its guarantee is
   structural, so it stays.

The contract, including every deny reason, is in
[`pr-run-activity.md`](../conventions/pr-pipeline/pr-run-activity.md#the-lane-token-broker).
github-iac
[ADR 0015](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0015-oidc-token-broker-for-pr-pipeline-lane-app-tokens.md)
records the GitHub-side trust and declares the variables.

### What this changes in ADR 0049 and ADR 0055

ADR 0049 condition 3 now reads: each job gets its App token from the lanes token broker, which
mints it after the checks above, valid for at most one hour, scoped to this repository and the
permissions the job's effect grants, and revoked when the job ends. The job holds no key. The rest
of the condition stands: no long-lived write token reaches a model step, and no model step holds
`checks: write` or `workflows`.

ADR 0055's residual that the App key and the OAuth token are in the run job's secret set is closed
for the App key. The Claude OAuth token stays in every skill job's secret set; the broker does not
address it.

### Write mints for the lanes bot are denied

The broker denies `bot-actor` when the OIDC `actor_id`, or on a re-run the attempt's triggering
actor, is the lanes bot, on every allowed event. `check-trusted-trigger` stops the same actor in the
write file first. A bot write therefore cannot start the next write run: one write never chains
into another.

## Alternatives considered

- **A JavaScript action with a `post:` revoke, like `create-github-app-token`.** Rejected: it needs
  a committed bundle or an install step. A composite action plus an explicit final revoke step does
  the same with no bundle to keep fresh.
- **A separate mint job with no model, handing the token to the model job.** Rejected in the design
  research: a masked job output is dropped, and every other channel between jobs leaks the token.
- **A native GitHub OIDC-to-installation-token exchange.** None was found in the GitHub changelog
  from 2026-09-01 to 2026-10-04; recheck before replacing the broker.
- **Keep the key, but only in write runs.** Rejected: a write job still runs a model with tools, and
  the key reaches every repository the App is installed on.

## Consequences

- Revocation: probe P5 (sandbox run 37243281591) revoked a stateless installation token and every
  API call and `git ls-remote` with it was refused from the first poll at 3 ms through 319 s. The
  final revoke step therefore ends a lane token as soon as the activity is done.
- A 200 lost in transit leaves a token nobody revokes; it expires within the hour. The client never
  retries, because a retry could only be denied `already-minted` or issue a second token.
- Broker outage, a GitHub or JWKS failure, a main change to either workflow file mid-run, or an
  empty broker variable fails write activities red. `LANES_BROKER_URL` is declared in github-iac
  only once the Function's hostname exists (ADR 0015, Decision 6); until then every write activity
  fails at the token step.
- Accepted residual, `id-token: write` in the write job: any step of the job can request an OIDC
  token for any audience, so anything the claude-code-action process runs, its MCP servers
  included, can reach a relying party that trusts this organization's tokens. github-iac ADR 0015
  lists them: Anthropic's Claude App exchange, Pulumi Cloud (only github-iac's protected
  environment) and Azure (only azure-iac's protected environment). The broker refuses a second mint
  for the job. Re-check this list when an OIDC trust is added anywhere in the organization. Probe
  P7 (sandbox run 38034916662) found that the skill's Bash subprocess under
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` sees neither `ACTIONS_ID_TOKEN_REQUEST_URL` nor
  `ACTIONS_ID_TOKEN_REQUEST_TOKEN`, while `GH_TOKEN` and `GITHUB_TOKEN` stay present because the
  scrub keeps them by design. The model therefore cannot request its own OIDC token to mint from
  the broker. The same run showed the minted token scoped to the sandbox repository only, and
  after revoke `DELETE /installation/token` returned 204 and `GET /installation/repositories`
  returned 401.
- Accepted residual, effect skew: the job runs trusted actions, the skill and the script from the
  PR's base SHA, while the broker's grant comes from the default-branch tip. The client's effect
  check fails a skewed job red. Follow-up, decided and not built: run the job's trusted actions
  from a tip checkout separate from the base-SHA config checkout, so the code that runs and the
  grant it gets come from the same revision. It changes the config-reader contract.
- Whoever can sign with the broker's key or change the code the Function runs can mint for every
  repository the App is installed on. azure-iac ADR 0001 (`docs/adr/0001-lanes-token-broker-stack.md`
  in that private repository) lists the identities and roles on the broker's vault and storage.
- Re-derive this record when GitHub ships a native OIDC exchange for installation tokens, when
  `create-github-app-token` or the installation-token API changes how revocation works, or when an
  OIDC trust is added in the organization.
