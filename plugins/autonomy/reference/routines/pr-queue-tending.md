# PR-queue tending

Normative leaf of the [routine catalog](../routines.md): the `pr-queue-tending` v1 class
definition — a standing sweep over the open-PR queue that reports its state and nudges the
humans each stalled PR is waiting on.

## Purpose

Silently stalling PRs are the toil addressed: open PRs go stale waiting on a forgotten
review, red CI nobody noticed, or an unanswered review thread, and each one is rediscovered
only when someone trips over it. The sweep does the recurring pass over the whole queue and
turns every stall into a named nudge, so PRs wait on decisions, not on attention.

## Trigger and cadence

Trigger-taxonomy slot: **schedule**. The routine enters work as a `temporal`-class signal
through the [trigger-dispatch contract](../trigger-dispatch.md)'s temporal adapter — a
scheduled trigger behind the governed queue, never a private execution or merge path.
Suggested cadence default: **daily** — an org-bindable value set in the org's routine
binding, never contract-fixed. No vendor scheduling surface is named here; guided setup
researches scheduling surfaces live.

## Access scope

Repo-scoped, including CI and the tracker: the sweep reads the open-PR queue, its review
threads, and CI outcomes, and writes only through the governed queue and tracker. No
production, product, org, or external-web access — the connector-prerequisite branch of the
mapping rules never applies.

## Output contract

- **Advisory report** — one run report on the queue's state: stalled reviews, red or flaky
  CI, unanswered threads, PRs approaching staleness.
- **Work-item nudges** — nudge items filed through the governed queue naming the PR, the
  stall, and the human action it waits on.
- **No direct change** — the sweep never pushes commits, merges, closes, or re-targets a PR.

## Derived guardrail row

The row is derived through the catalog-to-matrix mapping rules in the
[routine catalog](../routines.md) — never hand-assigned:

1. **Judgment axis.** Deciding which PRs are genuinely stalled, what each one waits on, and
   who to nudge is semantic judgment no rule engine resolves — agent-judgment (`AGT`), which
   is what makes the class a routine at all (deterministic work needs no agent session; a bare
   age-threshold stale bot is the deterministic neighbor, not this class).
2. **Output axis.** A report plus work-item nudges are governed-queue and tracker writes
   with no repository mutation: the `AGT` + report rule and the `AGT` + work-item rule both
   derive `C1`, and the [work-classes leaf](../guardrails/work-classes.md) scopes queue and
   tracker writes as permitted `C1` output.
3. **Higher-risk axes.** No direct-change rule matches (no push, merge, or close), so
   neither the mechanically-checkable branch (`C2`/`C3`) nor the structural axis (`C4`)
   fires; the access scope is repo/tracker, not the external-watch access class the
   provenance axis (`C5`) keys on. Composition to the highest matched class leaves `C1`.
4. **Access axis → prerequisite.** Repo scope sets the `L2` unattended floor as the dispatch
   prerequisite — and `C1`'s matrix row keeps that floor because the exfiltration surface
   remains even for read-only work.

Derived row: `C1` in the [guardrail matrix](../guardrails.md).

## Admission and escalation

Admission disposition, caps, and fail-closed behavior are imported by citation from the
[admission policy](../guardrails/admission-policy.md) — the shipped-defaults row for the
derived class governs, and nothing here restates it. Escalation events and routing are the
derived row's escalation column in the [guardrail matrix](../guardrails.md), org-bound per
its routing obligation.

## Precedent

The proven manual pattern is the recurring human sweep over open PRs — re-checking CI,
chasing reviews, answering or escalating stale threads — that every maintainer of a busy
queue runs by hand. Precedents from the routine-catalog research: hosted agentic-workflow
sample packs' scheduled PR-tending and daily repo-status workflows, and coding-agent
vendors' showcased review-what-changed scheduled automations.
