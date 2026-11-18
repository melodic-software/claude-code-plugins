# Admit own-agent filings sized small or medium under a per-producer cap

- Status: accepted
- Date: 2026-11-17
- Refs: owner decision of 2026-11-17

## Context

Intake admission (`.github/scripts/intake-triage/admit.mjs`) adds `agent-ready` only to an issue a
listed human filed, a size-split sub-issue the lanes App filed from one, or a trusted upstream-drift
issue. Every other issue the lanes App files holds at `needs-owner-decision` until a listed human
files the work again as their own (the owner decision on #10735). Our own agents file a steady
stream of issues (improvement finds, tidy lanes, audits), so each one waits for a person who
re-types work an agent already specified, and the unattended build stalls on that step.

Two risks bound any change. A filing must not carry outside text into a spec: a body or comment that
someone outside the listed humans wrote and that the lane would treat as instructions. And one
producer must not flood the issue lane: an agent that files fifty issues in a run would otherwise
take the whole queue.

## Decision

1. **Own-agent identities are configured.** `own-agents.identities` in
   [`admission-rules.json`](../../.github/actions/resolve-config/admission-rules.json) lists them,
   `lanes-app` standing for the lanes App whatever its id. The default is the lanes App alone.
   github-actions[bot] is not listed: any workflow running on `GITHUB_TOKEN` acts as it, so a
   workflow that copies a public comment or issue text into a filing would put outside text into a
   spec. It stays trusted only for upstream-drift issues, whose spec is a fixed template and never
   their body. An identity belongs on the list only when its filings never carry outside text.
2. **Size small or medium only.** Admission takes an own-agent filing only when intake sizes it
   small or medium. A large filing, or one whose run's patch went over the scan cap, holds for a
   listed human; it is never split automatically. A listed human's issue keeps today's size split.
3. **Per-producer cap.** An own-agent filing carries exactly one `source: <producer>` label. It waits
   at `status: ready` while `own-agents.source-cap` (default 5) or more older open issues carry the
   same label, in any status; work-unblock's sweep decides it again until one closes. A filing with
   no `source:` label, or more than one, holds for a listed human.
4. **Only the agent's own body is spec.** The body counts as spec only while no account but the
   identity that wrote it has edited it, the edit rule `driftIssueId` applies to drift issues. A
   body anyone else edited holds the filing for a listed human. Comments count only when a listed
   human wrote them, as on any issue. pr-verify reads the same body as the lane pull request's spec.

This supersedes the owner decision on #10735 for own-agent filings that meet these rules. A lanes App
issue opening with the size-split child marker is judged as a sub-issue, never as an own-agent
filing, and one that fails that rule still holds as before.

## Considered options

- **Keep every agent filing waiting for a person.** Rejected: the person re-files work an agent
  already specified, which is a recurring manual step on every filing and stops the unattended
  build at intake, while the risks it guards against are handled by the edit rule and the cap.
- **Self-admit every producer, outside text included.** Rejected: github-actions[bot] and any other
  shared identity can file text an outside account wrote, which the lane would then build from and
  pr-verify would judge against. That moves the trust boundary from who wrote the spec to which
  workflow filed it.
- **Admit own-agent filings at any size with the automatic split.** Rejected: a split copies the
  parent's lines into sub-issues the lane then runs without a person, so a large agent-written
  scope would fan out unreviewed. A person decides those.

## Consequences

- An agent's small or medium filing with a `source:` label reaches the issue lane without a person,
  through the same triage, criteria, charge, hold and room checks as any other issue.
- A producer past its cap queues behind its own open issues; raising the cap is one edit to
  `admission-rules.json`.
- Admitting another identity takes more than a list entry: the author gates in apply-verdict,
  check-blockers and write-issue (`authorTrust`, `authorAdmitted`) admit only listed humans, the
  lanes App and drift issues, so a new identity's filings stop there until those gates read the
  list too.
- The merge gate (`babysit_verify_evidence.py`) trusts an own-agent filing under the same rule, read
  from the same `own-agents` list, so a pull request built from one merges with no person. A filing
  that no longer meets the rule reads `verify:untrusted-spec`.

## Revisit triggers

- An own-agent filing reaches the lane with text an outside account wrote.
- A producer's open issues sit at its cap for days, so the cap throttles work nobody reviews.
