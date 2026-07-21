# Shell test helpers — per-plugin duplication and exit-code divergence are deliberate

Owner doc for one fork this marketplace has already decided: a plugin's shell `*.test.sh` assertion
primitives and a plugin script's exit-code taxonomy are **not** consolidated into a shared,
cross-plugin mechanism. Both stay duplicated or divergent per plugin, on purpose. The
[plugin philosophy](../../PLUGIN-PHILOSOPHY.md) owns the portability boundary this rests on: a plugin
never imports files from a sibling plugin, and cooperation crosses that boundary only through a
documented public seam — a shared shell assertion library is neither.

## Why not the existing vendoring mechanism

This repo already has one sanctioned way to share source across plugins: a canonical file under
[`lib/`](../../../lib/), copied (not imported) into each carrying plugin by a dedicated
`scripts/sync-*.sh`, and tracked in
[`scripts/cross-plugin-source-registry.txt`](../../../scripts/cross-plugin-source-registry.txt) so
`check-cross-plugin-source-drift.sh --check` fails if a copy drifts. `lib/hook-utils.sh` is the
worked example.

That mechanism exists for clusters that are meant to stay **byte-identical**. The assert-helper copies
below are not that: they are already three genuinely different shapes, not one library that drifted —

- **Hook-contract shape** (`ok`/`bad`, `PASS`/`FAIL` counters, plus `make_sink`/`wait_for_sink` for
  hook telemetry): [`guardrails/hooks/guardrails-test-helpers.sh`](../../../plugins/guardrails/hooks/guardrails-test-helpers.sh),
  [`claude-ops/hooks/claude-ops-test-helpers.sh`](../../../plugins/claude-ops/hooks/claude-ops-test-helpers.sh).
- **Skill-script shape** (`pass`/`fail`, `FAILED`/`CASE_NUM` counters, file-existence assertions):
  [`source-control/scripts/test-helpers.sh`](../../../plugins/source-control/scripts/test-helpers.sh),
  [`repo-hygiene/skills/clean/scripts/lib/test-helpers.sh`](../../../plugins/repo-hygiene/skills/clean/scripts/lib/test-helpers.sh).
- **Vendored-seam shape** (same `pass`/`fail` primitives, but owned by the seam itself so it stays
  correct wherever the seam is resolved from — bundled or consumer-vendored — independent of this
  repo's tooling): [`work-items/tools/work-item-tracker/tests/lib.sh`](../../../plugins/work-items/tools/work-item-tracker/tests/lib.sh).

Forcing these into one shared, synced library would mean designing a fourth, unified assertion API
and rewriting every existing `*.test.sh` onto it — a bigger, riskier change than the coupling it would
remove, for a mechanism (`check-cross-plugin-source-drift.sh`) that already classifies these files as
outside its scope: they live at different paths per plugin and are not byte-identical, so `discover`
never flags them as an unregistered cluster.

`scripts/check-skill-portability.test.sh` follows the same reasoning at the repo-tooling layer: it is
not a plugin, so no plugin assertion library is available to source, and it carries its own minimal
`PASS`/`FAIL` counters rather than reaching into a plugin's copy.

## Exit-code taxonomies also diverge, deliberately

Plugin scripts document their own `Exit:` codes rather than sharing one enum, because each taxonomy
encodes a different per-script contract, not an arbitrary numbering:

- [`repo-hygiene/skills/clean/scripts/remove-path.sh`](../../../plugins/repo-hygiene/skills/clean/scripts/remove-path.sh) —
  `0/1/2/3/4`: usage and existence checks plus two named blocking conditions (`blocked`, `unpushed`).
- [`repo-hygiene/skills/clean/scripts/git-tree-reset-batch.sh`](../../../plugins/repo-hygiene/skills/clean/scripts/git-tree-reset-batch.sh) —
  `0/1/2` for the batch runner itself, forwarding a child's `5`/`7` (from
  [`git-tree-reset.sh`](../../../plugins/repo-hygiene/skills/clean/scripts/git-tree-reset.sh)'s own
  `0`–`7` taxonomy) into its own `1`.
- [`scripts/check-skill-portability.sh`](../../../scripts/check-skill-portability.sh) — `0/1/2`: gate
  pass/fail plus usage error.

A shared usage/exit helper would need to either flatten these distinct contracts into a lowest common
denominator or grow branching per caller — neither is simpler than each script documenting its own
`Exit:` line, which every script here already does at its own usage banner.

## Deferred, not rejected

`guardrails-test-helpers.sh` and `claude-ops-test-helpers.sh` are the one pair above that already
share a shape closely (both hook-contract helpers with near-identical `ok`/`bad`/`make_sink` bodies).
If they converge to byte-identical, vendoring just that pair through the existing `lib/`,
`sync-*.sh`, and registry mechanism — the same pattern `hook-utils.sh` already uses — is the smaller,
precedented move, revisited then rather than spread across all five plugins now.

## Conformance

Each copy site above carries a one-line pointer back to this doc. A new plugin adding its own
`*.test.sh` assertion helper is not required to register anything here — duplication of this shape is
the accepted default, not an opt-in.
