---
bump: patch
---

### Fixed

- Every work-unblock refusal that holds for a person now names its owner reason. The admission
  comment carries the `<!-- stop-reason lane=work-unblock reason=<code> -->` marker and a
  `Reason:` line after the refusal: `security` for a deferred issue that gained `area: security`,
  and admission's own reason (`security`, `cost` or `intent`) for an issue a person marked or one
  in no queue. A refusal that parks at `status: confirmed` carries neither.
- A person's mark that admission refuses for no person's reason, such as a split of done-when
  items a lane run cannot perform, unset fields or a body edited after the mark, parks at
  `status: confirmed`, as intake's admission does, instead of `status: needs-decision`.
- Intake triage's re-entry rules no longer re-flag `intent` for a question a recorded decision
  answered, called no owner question, deferred or left to the issue lane. Only an outcome,
  done-when or primary-design question the decision leaves open, or one later text raises, still
  holds; cost and security flags hold as before.
