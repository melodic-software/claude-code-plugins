# Fleet-wide claude-config doc fetcher

Recorded park for
[#4658](https://github.com/melodic-software/claude-code-plugins/issues/4658),
the child of #4655 that would hoist one upstream-doc fetcher into `lib/` and
adopt it across plugins.

## Decision

**Park. Structural. Do not hoist.**

- **Option A (taken):** wait. There is no claude-config fetcher to hoist yet
  (#4655 recorded Option A: no persistent cache; the in-plugin extraction is
  remaining scoped work). Fleet adoption, publisher profiles, and a
  `scripts/sync-<name>.sh` cluster are a cross-plugin migration, not a settle.
- **Option B (declined):** move a fetcher to `lib/` from this change and convert
  `claude-ops` changelog status (or another caller) in the same PR.

**Claim:** fleet-wide adoption of a shared upstream-doc fetcher is parked until
claude-config owns one script that both of its callers use; even then, hoist
and adopt-on-touch stay a structural migration, not an opportunistic sweep.
**Basis:** #4658 is `work-class: structural` and names `lib/` plus
`scripts/sync-cluster.sh` plus publisher profiles plus at least one
non-claude-config caller. #4655's two callers still fetch independently
(`audit-engine.sh` `fetch_verbatim` vs `check-doc-citations.sh` direct `curl`).
`docs/conventions/upstream-drift/README.md` Adopters table is adopt-on-touch.
This shipper skips cross-repo fleet and structural giants.
**As of:** 2026-09-28.
**Recheck:** #4655's in-plugin fetcher lands (both claude-config callers through
one script, no persistent cache), and a maintainer names one non-claude-config
caller to convert on touch.

## Rationale

- Hoisting from claude-config before that plugin has one fetcher copies the
  split, not the cure.
- Cross-plugin reuse must follow `lib/` and presence-gated references. That is
  a cluster, not a docs patch.
- Non-Anthropic publisher profiles are a second design. The parent issue left
  them to this child; they stay here, still unbuilt.

## Revisit when

- The parent fetcher exists in claude-config, or
- an operator go names a single caller and a `lib/` sync cluster in the same
  brief.

## Prior requests

- #4658 (2026-09-28): child of #4655; parked as structural.
