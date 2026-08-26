# L1-derivability — `F-quality-verify`

121 files. `bugs`, `codebase-health`, `debugging`, `evals`, `mutation-testing`, `review`, `tdd`,
`testing`, `verification`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 114 |
| `out-of-scope: functional artifact` | 5 |
| `keep-as-derivation-cache` | 2 |

No deletions, no pointer conversions.

Roll-up for the 114 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
CHANGELOGs and plugin READMEs. The `tdd` and `mutation-testing` reference trees are distilled
external material (Khorikov, classical-vs-London, observable behavior) carrying attribution and
source provenance the repository holds nowhere else; the `review` and `codebase-health` trees own
finding schemas and gate contracts that other plugins conform to.

## `keep-as-derivation-cache` (2)

```text
plugins/review/reference/standards-contract.md
plugins/verification/reference/artifact-protocol.md
```

Both are members of registered byte-identical cross-plugin clusters. Drift-control, from
`scripts/cross-plugin-source-registry.txt`, is a dedicated CI job per cluster:
`scripts/sync-standards-contract.sh --check` (CI job `standards-contract-sync`) and
`scripts/validate-plugin-contracts.mjs (lifecycleProtocolCopies)` respectively. Neither can drift
silently, so the cache verdict holds without demotion. The duplication is deliberate standalone
installability, not an SSOT defect. See `D-work-planning.md` for the full reasoning.

## A near-miss recorded

`plugins/instruction-placement/evals/adherence-results.md` is `keep-owns-facts`, not a spent
measurement artifact. It records measured adherence outcomes, which are empirical facts about model
behavior at a point in time. Nothing in the repository re-derives a measurement; re-running the eval
produces a new measurement, not this one.
