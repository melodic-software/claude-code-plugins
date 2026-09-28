# Shell test helpers: per-plugin duplication and exit-code divergence are deliberate

Owner doc for one fork this marketplace has already decided: a plugin's shell `*.test.sh` assertion
primitives and a plugin script's exit-code taxonomy are **not** consolidated into a shared,
cross-plugin mechanism. Both stay duplicated or divergent per plugin, on purpose. The
[plugin philosophy](../../plugin-philosophy.md) owns the portability boundary this rests on: a plugin
never imports files from a sibling plugin, and cooperation crosses that boundary only through a
documented public seam. A shared shell assertion library is neither.

## Why not the existing vendoring mechanism

This repo already has one sanctioned way to share source across plugins: a canonical file under
[`lib/`](../../../lib/), copied (not imported) into each carrying plugin by a dedicated
`scripts/sync-*.sh`, and tracked in
[`scripts/cross-plugin-source-registry.txt`](../../../scripts/cross-plugin-source-registry.txt) so
`check-cross-plugin-source-drift.sh --check` fails if a copy drifts. `lib/hook-utils.sh` is the
worked example.

That mechanism exists for clusters that are meant to stay **byte-identical**. The assert-helper copies
below are not that: they are three genuinely different *assertion-primitive* shapes (`ok`/`bad`,
`pass`/`fail`, vendored-seam), not one library that drifted. The telemetry-sink pair
`make_sink` / `wait_for_sink` is a different fact: one helper family that drifted, recorded
below as sanctioned copy. Do not hoist it unpaid.

- **Hook-contract shape** (`ok`/`bad`, `PASS`/`FAIL` counters, plus `make_sink`/`wait_for_sink` for
  hook telemetry): [`guardrails/hooks/guardrails-test-helpers.sh`](../../../plugins/guardrails/hooks/guardrails-test-helpers.sh),
  [`claude-ops/hooks/claude-ops-test-helpers.sh`](../../../plugins/claude-ops/hooks/claude-ops-test-helpers.sh).
  Fourteen other suites still define `make_sink` inline (formatter family, `actionlint`,
  `desktop-notification`, `context-guard`, `autonomy`, and `lib/hook-utils.test.sh`). Those
  copies are sanctioned; see [make_sink copies](#make_sink-copies-sanctioned-until-a-plugin-local-helper).
- **Skill-script shape** (`pass`/`fail`, `FAILED`/`CASE_NUM` counters, file-existence assertions):
  [`source-control/scripts/test-helpers.sh`](../../../plugins/source-control/scripts/test-helpers.sh),
  and `/repo-hygiene:clean`'s bundled test-helper copy, named rather than linked because it sits
  under that skill's private `scripts/lib/`, not on the entry surface the pointers below reach.
- **Vendored-seam shape** (same `pass`/`fail` primitives, but owned by the seam itself so it stays
  correct wherever the seam is resolved from, bundled or consumer-vendored, independent of this
  repo's tooling): [`work-items/tools/work-item-tracker/tests/lib.sh`](../../../plugins/work-items/tools/work-item-tracker/tests/lib.sh).

Forcing these into one shared, synced library would mean designing a fourth, unified assertion API
and rewriting every existing `*.test.sh` onto it. That is a bigger, riskier change than the coupling
it would remove, for a mechanism (`check-cross-plugin-source-drift.sh`) that already classifies these files as
outside its scope: they live at different paths per plugin and are not byte-identical, so `discover`
never flags them as an unregistered cluster.

Repo-tooling suites under `scripts/` are a different layer: they share
[`scripts/lib/test-harness.sh`](../../../scripts/lib/test-harness.sh)
(`ok` / `fail` / `test_harness::report`). That library is not a plugin import
and does not change the per-plugin rule above.
`scripts/check-skill-portability.test.sh` sources it rather than reaching into
a plugin's copy.

## Exit-code taxonomies also diverge, deliberately

Plugin scripts document their own `Exit:` codes rather than sharing one enum, because each taxonomy
encodes a different per-script contract, not an arbitrary numbering:

- [`repo-hygiene/skills/clean/scripts/remove-path.sh`](../../../plugins/repo-hygiene/skills/clean/scripts/remove-path.sh) exits
  `0/1/2/3/4`: usage and existence checks plus two named blocking conditions (`blocked`, `unpushed`),
  where `1` carries both meanings: the target was already absent, and an `--apply` that left the
  target present (locked, in use, or crossing a mount). The caller therefore retries or reports
  rather than treating exit 1 as "nothing to do".
- [`repo-hygiene/skills/clean/scripts/git-tree-reset-batch.sh`](../../../plugins/repo-hygiene/skills/clean/scripts/git-tree-reset-batch.sh) exits
  `0/1/2` for the batch runner itself, forwarding a child's `5`/`7` (from
  [`git-tree-reset.sh`](../../../plugins/repo-hygiene/skills/clean/scripts/git-tree-reset.sh)'s own
  `0`–`7` taxonomy) into its own `1`.
- [`scripts/check-skill-portability.sh`](../../../scripts/check-skill-portability.sh) exits `0/1/2`: gate
  pass/fail plus usage error.

A shared usage/exit helper would need to either flatten these distinct contracts into a lowest common
denominator or grow branching per caller. Neither is simpler than each script documenting its own
`Exit:` line, which every script here already does at its own usage banner.

## make_sink copies (sanctioned until a plugin-local helper)

Option A: park a repo-wide hoist. Declare the remaining inline copies sanctioned. Do not rewrite
the formatter fleet unpaid.

- **Claim:** `make_sink` / `wait_for_sink` is one helper family that drifted. A repo-wide
  hoist into `lib/` plus `sync-*.sh`, or a rewrite of the fourteen inline suites onto a new
  shared file, is unpaid and parked. The copies stay. When a plugin family grows enough pain,
  it adds a *plugin-local* `*-test-helpers.sh`, the pattern `guardrails` and `claude-ops`
  already followed. `ok` / `fail` counters stay duplicated.
- **Basis:** Issue [#3412](https://github.com/melodic-software/claude-code-plugins/issues/3412)
  and the 2026-09-05 triage comment (34 suites reference `make_sink`; 14 still define it
  inline; two plugin-local helpers already exist). Re-measured 2026-09-28: 16 `make_sink()`
  definitions (14 inline + `guardrails-test-helpers.sh` + `claude-ops-test-helpers.sh`).
  `scripts/lib/test-harness.sh` remains the repo-tooling-layer precedent and does not change
  the per-plugin rule. Fourteen suites is not a tiny rewrite.
- **As of:** 2026-09-28.
- **Recheck:** a maintainer funds a plugin-local helper for the formatter family, the
  remaining inline definitions drop to a handful that a single-plugin PR can absorb, or
  `guardrails-test-helpers.sh` and `claude-ops-test-helpers.sh` become byte-identical (the
  vendoring trigger already in [Deferred, not rejected](#deferred-not-rejected)).

## Deferred, not rejected

`guardrails-test-helpers.sh` and `claude-ops-test-helpers.sh` are the one pair above that already
share a shape closely (both hook-contract helpers with near-identical `ok`/`bad` bodies; their
`make_sink` differs in contract: guardrails' takes a stub body, claude-ops' takes a capture file).
If they converge to byte-identical, vendoring just that pair through the existing `lib/`,
`sync-*.sh`, and registry mechanism, the same pattern `hook-utils.sh` already uses, is the smaller,
precedented move, revisited then rather than spread across all five plugins now.

## Conformance

Each copy site above carries a one-line pointer back to this doc. A new plugin adding its own
`*.test.sh` assertion helper is not required to register anything here. Duplication of this shape is
the accepted default, not an opt-in.

A whole-tree `/code-metrics:audit-duplication --all` run with this repo's registry reports these
helpers, counters, and result footers as its largest surviving clone classes, because no sync
script declares them and a registry cluster line has to mirror one. Those rows are this decision
made visible, not debt to fix; [`.claude/code-metrics.yaml`](../../../.claude/code-metrics.yaml)
carries the same note beside the registry setting.
