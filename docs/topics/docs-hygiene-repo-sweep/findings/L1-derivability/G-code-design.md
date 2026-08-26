# L1-derivability — `G-code-design`

94 files. `architecture`, `code-tidying`, `coupling`, `domain-driven-design`, `event-storming`,
`improvement`, `naming`, `overengineering`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 83 |
| `out-of-scope: functional artifact` | 10 |
| `keep-as-derivation-cache` | 1 |

No deletions, no pointer conversions.

Roll-up for the 83 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
CHANGELOGs and plugin READMEs. The characteristic content is distilled design theory with
attribution (Ousterhout deep modules, EventStorming notation, DDD stewardship) plus scope boundaries
between sibling plugins. `plugins/domain-driven-design/README.md` is a useful example of why a
plugin README is not derivable from its manifest: at 1452 bytes it still owns a deferred-scope
decision ("Deferred: `context-mapping` and `aggregate-design` join this plugin when those practices
materialize as skills"), an explicit out-of-scope boundary against `event-storming`, and a
dependency fact ("The `planning` plugin declares a dependency on this plugin"). None of that is in
`plugin.json`.

## `keep-as-derivation-cache` (1)

```text
plugins/overengineering/reference/artifact-protocol.md
```

Registered byte-identical cluster member. Drift-control:
`scripts/validate-plugin-contracts.mjs (lifecycleProtocolCopies)`, named in
`scripts/cross-plugin-source-registry.txt` and run as a required CI job. No demotion; the
duplication is deliberate standalone installability. Full reasoning in `D-work-planning.md`.
