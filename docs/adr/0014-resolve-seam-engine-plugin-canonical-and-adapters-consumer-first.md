# Resolve the tracker-seam engine plugin-canonical and adapters consumer-first

- Status: accepted
- Date: 2026-08-17

## Context

The work-item tracker seam (`plugins/work-items/tools/work-item-tracker/`) ships bundled with
the `work-items` plugin and also runs from a consumer-vendored copy. Two kinds of code resolve
at call time: the engine (dispatcher, `lib/`, the contract itself) and the per-provider
adapters. `CONTRACT.md` ("Adapter resolution") documents the mechanics and cited an ADR for
the rationale, but the ADR was never written — the citation dangled at a number (`0022`) this
repository's sequence had not reached (seam-scrutiny finding F3.5, #2942). This ADR records
the rationale in-tree, at the next number in sequence.

## Decision

The seam resolves its two code surfaces in deliberately opposite directions, and the
directions are locked:

- **Engine — plugin-dir canonical, project-root fallback.** Callers resolve
  `work-item-tracker.sh` from `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/` when that
  exists, else `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/`. Engine fixes flow to every
  consumer through plugin updates with no re-vendoring, and the security-sensitive shell —
  credential-egress guards, the claim-race protocol, reclaim revalidation — stays under one
  expert owner. The fallback keeps a vendored copy runnable when the plugin is absent.
- **Adapters — consumer-local-first, plugin-bundled fallback; first match wins.** A consuming
  repo can add a provider the plugin does not ship, or shadow a bundled adapter with a local
  copy it owns fully, without forking the plugin. The accepted cost of this direction is
  version skew between a consumer's adapter and the plugin's engine; the mitigation is the
  manifest contract-version handshake (`CONTRACT.md` "Contract-version handshake"), not a ban
  on shadowing.

Reversing either direction silently changes which code executes for every consumer: an
engine resolved consumer-first would pin consumers to stale vendored copies of the
security-sensitive shell, and adapters resolved plugin-first would make local providers and
shadows unreachable — the two extension points the seam exists to offer. Either reversal is a
breaking change to the seam contract, never a refactor.

## Conformance note

The conformance suite runs the same abstract suite over real adapters through the core CLI
only. The GitHub conformance binding targets a throwaway sandbox repo named per run via
`WIT_CONFORMANCE_GITHUB_REPO`, and there is deliberately **no default and no standing shared
sandbox**: the suite's clean-at-start closes every open issue in its target, so a baked
default would eventually be pointed at (or drift into being) a repo someone coordinates real
work in. The GitHub binding is therefore on-demand only — never CI, never a coordination
repo.
