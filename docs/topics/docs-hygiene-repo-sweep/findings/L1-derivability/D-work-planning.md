# L1-derivability — `D-work-planning`

109 files. `implementation`, `planning`, `prototype`, `work-items`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 95 |
| `out-of-scope: functional artifact` | 11 |
| `keep-as-derivation-cache` | 3 |

No deletions, no pointer conversions.

Roll-up for the 95 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs, CHANGELOGs
and plugin READMEs. The group's characteristic content is process doctrine and seam contracts
(tracker seam, topic-docs bindings, plan/PRD shapes) that no code in this repo implements, plus the
`work-items` tracker adapter READMEs, which own provider-specific external behavior for GitHub,
Gitea, Jira, Linear, and local-markdown. Eleven files are functional artifacts
(`**/evals/fixtures/**`, `plugins/planning/skills/questionnaire/templates/questionnaire.md`,
`plugins/knowledge`-style checklist templates under `**/templates/**`) and take no verdict.

## `keep-as-derivation-cache` (3)

```text
plugins/implementation/reference/artifact-protocol.md
plugins/planning/reference/artifact-protocol.md
plugins/planning/reference/standards-contract.md
```

| Factor | Reading |
|--------|---------|
| Derivable? | partial — each is a byte-identical member of a registered cross-plugin cluster |
| Re-derivation cost | moderate |
| Drift risk | low, mechanically controlled |
| Fact ownership | the cluster owns the contract; each copy is a synchronized rendering |

Cache drift-control, from `scripts/cross-plugin-source-registry.txt`:

> Dedicated check: scripts/validate-plugin-contracts.mjs (lifecycleProtocolCopies)
> reference/artifact-protocol.md

> Dedicated check: scripts/sync-standards-contract.sh --check (CI: standards-contract-sync)
> reference/standards-contract.md

Each cluster has a named CI job that fails on drift, so neither copy can silently rot. The
registry's own header states the enforcement in both directions: an unregistered identical cluster
fails as "unregistered", a registered cluster that stops matching fails as "drifted".

Do not route these to a pointer. The byte-identical duplication is deliberate: a plugin must be
installable standalone, so it carries its own copy rather than reaching into a sibling plugin's
tree. That is also why `extract-ssot` already registered this cluster as keep-as-synced-copies
(`plugins/docs-hygiene/context/derivability-route-followups.md:19`).

## Cross-lane observations

- L2-progressive-disclosure: `plugins/implementation/skills/implement/context/gotchas.md` is
  unreachable from its own skill. `plugins/implementation/skills/implement/SKILL.md:43-45` is a
  three-row routing table citing `context/feature.md`, `context/bugfix.md`, and
  `context/refactor.md`; `context/gotchas.md` is the fourth file in that directory and appears in no
  row. The content is unique authored doctrine (failure patterns with rationale), so the fix is to
  wire it, not to delete it. This is the same file named at
  `docs/topics/context-engineering-claude-5/design/article-sections.md:25` as "dead within its skill
  — its `SKILL.md` has a `## Gotchas` heading but never cites the file".
