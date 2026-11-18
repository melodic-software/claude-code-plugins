---
bump: minor
---

### Changed

- `/performance:protect` section 5 no longer picks a guardrail mechanism for a fragile optimization
  from its own list. It names what each of the three fragility cases must keep true and hands the
  choice of mechanism to `/corrections:codify` when that skill is available, or proposes the
  strongest mechanism that can decide the rule and says the proposal is unproven. It proposes the
  same way when codify stops with no proposal below its recurrence threshold. The ceiling and
  its hand-off to `/toolchain:ratchet` are unchanged, and the Output's "Guardrails proposed" line
  names the hand-off or the fallback proposal.
