---
bump: major
---

### Removed

- **Breaking:** `vendors.promotion_audits` and `vendors.promotion_days` are gone from `multi-agent.schema.json`, so a config that sets either fails validation; delete both keys. `resolve-roles.sh` now ignores them as unknown keys.
- `/multi-agent:audit-defaults registry` no longer records per-machine audit history or proposes promoting a `support-only` row to `permanent`: `skills/audit-defaults/scripts/registry-history.mjs` is deleted, and the registry judge no longer returns `error_range` or `tests_required_vendors`. A row leads only with an error range and consensus needs two clusters, so with today's rows a promotion could never change a routing decision. Demotion is unchanged.
- `reference/vendor-routing-audit.md` is deleted; nothing referenced it.
