# L1-derivability — `H-knowledge-research`

133 files. `ai-briefing`, `context7`, `discovery`, `dometrain`, `education`, `firecrawl`,
`knowledge`, `miro`, `visualization`, `x`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 111 |
| `out-of-scope: functional artifact` | 20 |
| `keep-as-derivation-cache` | 1 |
| `delete` | 1 |

Roll-up for the 111 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
CHANGELOGs, and plugin READMEs. The group's characteristic content is external-fact ownership that
exploration cannot recover at any price: vendor API behavior, third-party terms-of-service
constraints, upstream drift ledgers, and citation-shape contracts. Twenty files are functional
artifacts (`**/evals/fixtures/**` and the `plugins/knowledge/skills/*/templates/**` tree the digest
skills instruct agents to copy) and take no verdict.

## `plugins/ai-briefing/skills/generate/context/execution-flow.md` — verdict: `delete` (PROVISIONAL) [audience: agent]

| Factor | Reading |
|--------|---------|
| Derivable? | yes, but not from code — from `plugins/ai-briefing/skills/generate/SKILL.md`, which carries the same eight-stage flow across four sections. This is doc-to-doc subsumption on an unreachable file, which is why the verdict is `delete` rather than an SSOT route |
| Re-derivation cost | zero — nothing loads the file, so nothing pays a cost when it is gone |
| Drift risk | high, and already realized — the file is a second, unsynchronized copy of the run procedure that no gate compares against `SKILL.md` |
| Fact ownership | none that survives salvage. Two lines have no `SKILL.md` counterpart and must be moved before the delete (below) |

Verdict rationale, two independent legs.

**Leg 1: unreachable.** `plugins/ai-briefing/skills/generate/SKILL.md:140-144` is the entire
`## References` section:

> `references/audience-defaults.md`. Default ranking lens and profile overlay.
> `references/build-pipeline.md`. Deterministic HTML/PDF/PPTX generation and validation.
> `references/slide-generation.md`. Slide structure and optional build prerequisites.

`context/execution-flow.md` is the only file in `context/`, and it appears in no routing table, no
reference list, and no script in the repo. A repo-wide inbound-mention scan across all tracked
markdown, shell, Python, and JSON, CHANGELOGs excluded, returns zero hits. This reproduces a finding
already recorded independently at
`docs/topics/context-engineering-claude-5/design/article-sections.md:25`:

> `ai-briefing/skills/generate/context/execution-flow.md` (genuinely dead — the string occurs
> nowhere in the repo)

**Leg 2: subsumed.** Section-by-section, every load-bearing claim has a `SKILL.md` counterpart.
`§0 Parse and validate` and `§7 Persist and report` map to `SKILL.md` `## Default run` steps 1 and
7-9; `§1 Confirmation gate` to step 2; `§2 Collect from authorized interfaces` including the X
prohibition to `## Source and access policy`; `§3 Normalize and deduplicate` to step 5;
`§4 Categorize and rank` to step 6; `§5 Emit markdown` to `## Output contract`; `§6 Optional
presentation build` to step 8. Profile precedence, which `execution-flow.md:9-11` states, is owned
in more detail at `SKILL.md` `## Profile resolution`.

Owned-fact salvage, required before deletion. Two claims have no `SKILL.md` counterpart:

- `plugins/ai-briefing/skills/generate/context/execution-flow.md:39` — "Set explicit timeouts for
  outbound requests and make partial failures visible."
- `plugins/ai-briefing/skills/generate/context/execution-flow.md:104` — "Re-running the same window
  is idempotent: merge by canonical event identity and do not emit duplicate items."

Both belong in `SKILL.md` (`## Default run` step 3 and step 7 respectively). Deleting without
moving them loses two real invariants, which the rubric forbids.

Spot-test: **not run — no fresh-context subagent tool exists in this session** (see the README's
spot-test section). Verdict stays provisional. The unreachability leg is mechanical and does not
need a spot-test; the subsumption leg does, because "SKILL.md already says this" is exactly the
self-grade the rubric warns about.

## `plugins/discovery/reference/artifact-protocol.md` — verdict: `keep-as-derivation-cache` [audience: agent]

| Factor | Reading |
|--------|---------|
| Derivable? | partial — it is one of five byte-identical copies of a shared contract |
| Re-derivation cost | moderate |
| Drift risk | low, and mechanically controlled |
| Fact ownership | the cluster owns the protocol; this copy is a synchronized rendering of it |

Cache drift-control: `scripts/cross-plugin-source-registry.txt` registers
`reference/artifact-protocol.md` as an expected byte-identical cluster, with the dedicated check
named in that file: `scripts/validate-plugin-contracts.mjs (lifecycleProtocolCopies)`, a required CI
job. A drifted copy fails CI, so the cache cannot silently rot. This clears the drift-control gate;
no demotion. Do not "dedupe" this cluster into a pointer, the byte-identical copy is the deliberate
design (each plugin must be installable standalone).

## Cross-lane observations

- L2-progressive-disclosure: `plugins/discovery/skills/research/context/gotchas.md` and
  `plugins/discovery/skills/trace-intent/context/gotchas.md` are reachable; the unreachable-gotchas
  problem in this sweep is `implementation`'s, recorded in `D-work-planning.md`.
