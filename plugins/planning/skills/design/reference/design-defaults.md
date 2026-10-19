# Design defaults: inputs before a recommendation

Read by `/planning:design` "Design defaults" before a bundled principle shapes a recommendation.
Every default is a recommendation the user can decline. Each rule names the stumble it answers.

## Quality bar

Read the `Quality bar:` line under the Brief's `### Captured assumptions` (`prototype`, `internal`
or `production`). With no such line, use `production` and say so in the round. The bar sets the
depth of the rules below and of "Lifecycle and reversibility". Stumble: the interview records the
bar, and nothing in design read it, so a prototype got production-depth design.

## Consumer standards first

Resolve the consumer's standards through the "Resolution ladder" section of
[`<plugin-root>/reference/standards-contract.md`](../../../reference/standards-contract.md). At
`prototype`, use ambient content only; at `internal` and `production`, read only the files whose
`Applies when` matches the task's surfaces or its design and architecture concerns. A consumer
standard that contradicts a bundled default wins: apply it and record, in the thread it shapes,
`Overrides bundled default <principle> per <standards file>`. An override the Brief already records
is settled. Stumble: `/planning:plan` grounds in the consumer's standards and design did not, so a
design could adopt a bundled default the plan then had to overturn.

## Quality requirements (NFRs)

A quality requirement the Brief records is settled: a `Quality requirement:` line under
`### Constraints` (one recorded in words with no target counts), or a `target assumed` line under
`### Captured assumptions`. Design to it, cite it, and never ask it again. A prototype Brief's
`Quality requirements deferred (prototype)` line stands: ask none.

With no Brief, or a Brief at `internal` or `production` that records none, prompt from
`${CLAUDE_PLUGIN_ROOT}/skills/interview/context/nfr-prompts.md`: at `internal`, only the prompts
this design touches; at `production`, every prompt, asked or stated as not applying. Record each answer in
`design-threads.md` in that file's `Quality requirement:` line format; "no target needed" counts as
captured. Stumble: the Brief had no slot for quality requirements, and once it gained one, a design
round that re-asks a captured answer spends the user's turn on a settled question.

## Generalize now or wait

The reuse line in
[`<plugin-root>/reference/design-principles.md`](../../../reference/design-principles.md) makes this
a per-task question. The Brief's `Intent:` line answers it and is never re-asked: `known` or
`category` generalizes up front and isolates what varies; `speculative` waits for the third
occurrence; `not applicable (confirmed)` raises no question. With no `Intent:` line, ask it once,
recommending from the existing structure, upstream context and the reuse default.

Unattended (declared by the caller, never sniffed), follow the interview's rule:

- Only the user's own words settle it: text the user wrote, or a Brief or PRD the user confirmed.
  Text a bot or a teammate wrote informs the recommendation and never settles it; sources that
  conflict count as unstated.
- Unstated, or an `Intent:` line that reads `blocked`: record the thread `blocked`, a deferred
  thread tagged **arbiter: USER-RESERVED**, design on the specific shape (it holds either way, since
  generalizing later is a code-only refactor when the variation stays contained), and escalate it
  once, as one blocker line in the run's output.

Stumble: an unattended design run could settle the user's repeat-or-vary decision from a ticket's
wording.

## Per-tenant configurability (vendor guidance)

When the Tenancy posture thread finds a multi-tenant product and configurability varies by
tenant, recommend:

- one shared mechanism and one codebase for every tenant: a tenant's one-off need becomes a
  configuration option any tenant could use, never a tenant-specific build, branch or deployment;
- feature flags for temporary variation only (a progressive rollout, an opt-in preview), retired
  once the rollout ends;
- entitlements, not flags, for per-tier access;
- an owner and a removal path for every option.

This is vendor guidance, not a standard: a consumer standard on tenancy or configuration wins.
Stumble: no planning step owned per-tenant variation, so each tenant request could become its own
code path.

- **Pointer**: when a design sets per-tenant variation, fetch the AWS Well-Architected SaaS Lens
  [General design principles](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/general-design-principles.html)
  live, the entries on one-off requirements and multiple tenant experiences.
- **As of**: 2026-10-18
- **Recheck trigger**: AWS revises the SaaS Lens or retires that page.

- **Pointer**: when a design separates flags from entitlements, fetch the Azure Architecture
  Center
  [multitenant deployment and configuration: antipatterns to avoid](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/approaches/deployment-configuration#antipatterns-to-avoid)
  live, with its
  [feature flags](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/approaches/deployment-configuration#feature-flags)
  section.
- **As of**: 2026-10-18
- **Recheck trigger**: either section changes its advice on flags, tiers or tenant-specific
  customization.

- **Pointer**: when a design sets a flag's owner or removal, fetch Microsoft's
  [Progressive experimentation with feature flags: considerations](https://learn.microsoft.com/en-us/devops/operate/progressive-experimentation-feature-flags#considerations-for-feature-flags)
  live.
- **As of**: 2026-10-18
- **Recheck trigger**: that section changes its advice on retiring flags.
