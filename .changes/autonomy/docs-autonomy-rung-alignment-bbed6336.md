---
bump: minor
---

### Changed

- The isolation ladder names the CI-lane surface on provider-hosted runners: while its five conditions hold it runs unattended without default-deny egress, and every other surface keeps the `L2` floor.
- The work-class contract states that no merge rung reaches `C4` or `C5`, and that a merge authority reading no class, such as the pr-merge lane, merges on the verifier verdict and still refuses `C5`.

### Deprecated

- `executor_class` in the security binding is optional and ignored. A binding that still carries it stays valid, and `check-signal-envelope.mjs` no longer requires it.

### Removed

- The vendor-hosted merge cap. `check-security-binding.mjs` accepts `merge_policy` `"auto"` under `executor_class: vendor-hosted`, and promotion ratification and checker unanimity now apply to every binding. The trigger contract, the runner pack and the routine leaves no longer state the cap.
