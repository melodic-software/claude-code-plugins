# Guarded-mutation preamble stays triplicated

Recorded park for
[#3449](https://github.com/melodic-software/claude-code-plugins/issues/3449),
a batch-simplify leftover that would hoist the apply-gated lease check and
the pin preamble shared by three babysit mutation CLIs.

## Decision

**Park. Do not hoist.** Each CLI keeps its own copy. A shared helper is a
guard-contract shape change and is unpaid.

- **Option A (taken):** no unpaid hoist. `refresh_pr_branch.py`,
  `request_review.py`, and `manage_feedback_ledger.py` keep their own
  `require_worker_lease` and the `run_locked` pin preamble (parse, key,
  lease, load, require PR state, resolve expected head). Behavior stays
  what the existing suites already assert.
- **Option B (declined):** one helper that owns the apply-gated lease check
  and the pin preamble, with the guard contract documented at the helper,
  and all three call sites routed through it.

**Claim:** the three babysit mutation CLIs that write queue state under
`--apply` each keep their own guarded-mutation preamble. `babysit_lease.py`
owns `require_owned_lease` and `heartbeat`; it does not own the `--apply`
gate or the pin sequence. A hoist is unpaid.
**Basis:** origin/main as of this record.
`refresh_pr_branch.py::require_worker_lease` and
`request_review.py::require_worker_lease` are byte-identical (the `renew=`
heartbeat path). `manage_feedback_ledger.py::require_worker_lease` is the
apply-only subset (no `renew`). All three `run_locked` functions then share
`parse_repo_number`, the `{repo}#{number}` key, `require_worker_lease`,
`load_state`, `require_pr_state`, and `resolve_expected_head_sha`.
`request_review.py::run_locked` inserts trigger-config and a recognizer
check between the key and the lease call. The generated
`reference/guard-contract.md` tables do not cover this preamble; they
cover argument-shape refusals and GitHub mutations. #3449 is
`work-class: structural` and `needs-human`.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds one helper that owns the apply-gated lease
check and the pin preamble, the three CLIs call it with no local copy left,
and the existing suites still pass their refusal assertions, including a
test that covers the refusal path through the helper.

## Rationale

- The preamble decides whether a mutation may proceed. Moving that decision
  into shared code is a guard-contract change, not a sweep edit. That is
  why the batch-simplify closeout deferred it.
- The third caller is not a drop-in: `request_review.py` sets up the
  trigger recognizer before the lease check. Folding that into a generic
  helper is the unpaid design.
- Ledger's copy is already a subset of the other two. Making the three
  byte-identical first would still leave the pin preamble triplicated.

## Revisit when

- A maintainer funds the helper and names the first CLI to migrate, or
- a guard change has to be patched in more than one of these three files
  at once.

## Prior requests

- #3449 (2026-09-28): batch-simplify leftover; Option A recorded here.
