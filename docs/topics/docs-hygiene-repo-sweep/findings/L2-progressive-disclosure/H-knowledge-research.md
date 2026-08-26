# L2 progressive disclosure: `H-knowledge-research`

133 files, 32 `T2`. Plugins: `ai-briefing`, `context7`, `discovery`, `dometrain`, `education`,
`firecrawl`, `knowledge`, `miro`, `visualization`, `x`.

Totals: T1=5, T2=9, T3=2.

## Split lane

Every finding here is driven by **word density**, not line count. Four `T2` bodies sit well under
the 500-line ceiling while exceeding the recommended 5k-token body size, which is the case the
tier model warns about: invocation-loaded content is cheap to have and not cheap to use, and every
line recurs for the rest of the session once the skill triggers.

### `oversize`: `plugins/discovery/skills/research/SKILL.md` (Tier 2)

234 lines, **5,058 words** (21.6 words per line), 5 `context/` spokes.

`plugins/discovery/skills/research/SKILL.md:22`:

> `## Routing. Dispatch by default`

Lines 22 to 71, 50 lines, 21% of the file, and the densest block. It is a pre-work routing
decision that resolves once per invocation and is never revisited, held resident for the whole
session alongside the four research phases it routes into.

**Split spec.** New spoke: `plugins/discovery/skills/research/context/routing.md` holding lines 23
to 71, promoted to H1 `# Routing: dispatch by default`. The skill already uses `context/` for
`dispatch.md`, so the neighbour is the natural home; keep the two separate (`dispatch.md` owns the
parent-side contract, this owns the tier decision).

Replaces lines 22 to 71 with:

```markdown
## Routing. Dispatch by default

This skill dispatches by default rather than researching in the main thread. Read
[context/routing.md](context/routing.md) at the top of every invocation, before Phase 0: it owns
the tier ladder, the preload token contract, and the fallback that is the accepted recovery. The
phases below assume a tier has already been resolved; running them without that decision is the
failure this file prevents.
```

Resulting `SKILL.md`: 234 - 49 + 8 = **193 lines**, roughly 4,100 words.

### `oversize`: `plugins/education/skills/teach/SKILL.md` (Tier 2)

265 lines, **4,538 words**, 6 `context/` spokes.

`plugins/education/skills/teach/SKILL.md:133`:

> `## Pedagogy. Three Layers`

Lines 133 to 182, 50 lines (`### Fluency vs storage strength`, `### Knowledge`,
`### Research grounding`, `### Skills`, `### Wisdom`), plus `## Zone of Proximal Development`
(183 to 196, 14 lines). 64 lines of pedagogical theory that shapes how every action behaves but is
not itself an action, in a body that is 21% over the recommended size.

**Split spec.** New spoke: `plugins/education/skills/teach/context/pedagogy.md` holding lines 134
to 196, promoted to H1 `# Pedagogy: three layers and the ZPD`, with the six H3s raised to H2 and a
`## Contents` list on top.

Replaces lines 133 to 196 with:

```markdown
## Pedagogy. Three Layers

Teaching moves through knowledge (what is it), skills (how to do it), and wisdom (when and why),
paced inside the learner's zone of proximal development. Read
[context/pedagogy.md](context/pedagogy.md) the first time a session composes a lesson or an
assessment: it owns the fluency-versus-storage-strength distinction, what each layer looks like in
a dialog turn, the research grounding, and the ZPD pacing rule. Every action below assumes it; the
action rows do not restate it.
```

Resulting `SKILL.md`: 265 - 63 + 9 = **211 lines**.

### `oversize`: `plugins/discovery/skills/explore/SKILL.md` (Tier 2)

224 lines, **4,045 words** (18 words per line), 2 `reference/` spokes.

`plugins/discovery/skills/explore/SKILL.md:20`:

> `## Routing. Dispatch by default`

Lines 20 to 72, 53 lines, 24% of the file. Same shape as its `research` sibling above, and the
same treatment.

**Split spec.** New spoke: `plugins/discovery/skills/explore/context/routing.md` holding lines 21
to 72. Replacement pointer mirrors the `research` one, naming this skill's own tiers.

### `oversize`: `plugins/discovery/agents/intent-tracer.md` (Tier 2)

341 lines, **3,728 words**, **zero spokes**. An agent definition carries the same invocation-loaded
cost as a skill body and has the same 500-line ceiling.

`plugins/discovery/agents/intent-tracer.md:92`:

> `## Tool honesty`

Lines 92 to 163, 72 lines, 21% of the file, and

`plugins/discovery/agents/intent-tracer.md:284`:

```text
### `persistence:` — when the work finished but the write did not
```

Lines 284 to 332, 49 lines, one failure-class handler nested under the return contract.

Agent definitions in this repo have no bundled-file convention, and the plugin already owns
`plugins/discovery/reference/` shared by its skills.

**Split spec.** New spoke: `plugins/discovery/reference/tool-honesty.md` holding lines 93 to 163,
promoted to H1 `# Tool honesty for discovery agents`. The three sibling agents
(`researcher.md` 305 lines, `explorer.md` 275 lines, `intent-tracer.md`) all carry a variant of
this rule, so a plugin-scope spoke is the right level and the split also sets up L3's dedup.

Replaces lines 92 to 163 with:

```markdown
## Tool honesty

Report what you actually ran and what it actually returned. Read
[`${CLAUDE_PLUGIN_ROOT}/reference/tool-honesty.md`](../reference/tool-honesty.md) before your
first tool call: it owns the claim-versus-evidence rule, the unavailable-tool disposition, and the
exact wording for a probe you could not run. Reporting a result you did not observe is the failure
this file exists to prevent.
```

### `oversize`: `plugins/knowledge/skills/docpage-digest/SKILL.md` (Tier 2)

321 lines, 3,312 words, 1 `context/` spoke.

`plugins/knowledge/skills/docpage-digest/SKILL.md:162`:

> `## Phase 4. Dual verification`

Lines **162 to 251, 90 lines, 28% of the file**, the single largest block, and a terminal phase
that runs after the digest exists.

**Split spec.** New spoke: `plugins/knowledge/skills/docpage-digest/context/dual-verification.md`
holding lines 163 to 251. Replaces lines 162 to 251 with:

```markdown
## Phase 4. Dual verification

Read [context/dual-verification.md](context/dual-verification.md) once Phase 3's digest exists and
before presenting it: it owns both verification passes, what each one reads, the disagreement
disposition, and what a failed pass does to the artifact. A digest presented without it is
unverified, which is the state this phase exists to rule out.
```

### Not findings

`plugins/discovery/agents/researcher.md` (305 lines / 3,306 words) and
`plugins/discovery/agents/explorer.md` (275 / 2,922) are inside both ceilings. The tool-honesty
split above removes shared mass from all three agents; neither fires on its own.

## Structure lane

### `orphan-spoke` (Tier 2)

**`plugins/ai-briefing/skills/generate/context/execution-flow.md`** (105 lines)

```text
# AI Briefing Execution Flow

This runbook supports the active `generate` skill. The skill's source/access policy is
authoritative.
```

Verified: the string `execution-flow` appears nowhere in `plugins/**` outside the file itself. The
only occurrence in the repo is a prior audit record at
`docs/topics/context-engineering-claude-5/design/article-sections.md:25`, which independently
named this file as "genuinely dead (the string occurs nowhere in the repo)". Two independent
measurements agree.

Three-way treatment, and the third option is the right one here: the runbook duplicates the phase
sequence that `SKILL.md` already carries (`## 0. Parse and validate` against the skill's own
argument parsing), and its own second line defers to the skill as authoritative. **Delete
`plugins/ai-briefing/skills/generate/context/execution-flow.md`**, and check nothing in
`plugins/ai-briefing/CHANGELOG.md` promises it. If the deletion is contested, the fallback is a
hub pointer under a new `## Reference index. Load on demand` in
`plugins/ai-briefing/skills/generate/SKILL.md`, but a runbook that defers to the skill for every
policy question does not earn a second copy of the flow. This overlaps L1; route the decision
there and apply whichever lane owns it first.

### `orphan-spoke` (Tier 3, awareness only)

**`plugins/knowledge/skills/video-digest/extraction/liveness/LIVENESS.md`** (74 lines)

Unreachable from `SKILL.md`, and the only repo-wide mention is
`plugins/knowledge/CHANGELOG.md:229` naming its former path
`skills/youtube-digest/extraction/liveness/LIVENESS.md`. But it sits beside
`run-source-liveness.js`, `run-source-liveness.test.js`, `probes.json`, and `fixtures/`, and its
own opening calls itself the "Owner doc" for that script lane. That makes it a co-located script
README rather than a disclosure spoke, which is why the rubric's `scripts/` exclusion does not
reach it only by directory name. No treatment; recorded so a future orphan sweep does not
re-flag it.

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-profile.md` | 420 |
| `plugins/knowledge/skills/course-digest/reference/adapters/discovery-checklist.md` | 407 |
| `plugins/knowledge/skills/course-digest/context/workflow.md` | 331 |
| `plugins/ai-briefing/skills/generate/references/build-pipeline.md` | 324 |
| `plugins/discovery/reference/parent-contract.md` | 302 |

`plugins/discovery/reference/parent-contract.md` is the sharpest: `skills/research/SKILL.md` cites
it at lines 24, 32, 44, 64, 76, and 78, each time for a different clause of the contract, with no
index at the target to reach a clause.

Remediation, all five: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For
`parent-contract.md`, name the clauses the citing skills reach for.

### `deep-nesting` (Tier 2)

**`plugins/knowledge/skills/course-digest/context/workflow.md:46`**

> `3. **Screenshots** — capture frames per [screenshot strategy](../reference/screenshot-strategy.md).`

`reference/screenshot-strategy.md` is reached only from `context/workflow.md`, itself a spoke: two
hops, for a step the workflow marks as executed in every run with visual content.

Remediation: add a hub-level pointer in `plugins/knowledge/skills/course-digest/SKILL.md` so the
file is one level deep, keeping the call site in `workflow.md`:

```markdown
Read [reference/screenshot-strategy.md](reference/screenshot-strategy.md) before capturing the
first frame of a lesson with visual content (code demos, slides, architecture diagrams): it owns
the capture points, the naming, and the `screenshots/` layout the workflow's step 3 writes into.
```

### `blind-pointer` (Tier 2)

**`plugins/ai-briefing/skills/generate/SKILL.md:140`**

```text
## References

- `references/audience-defaults.md`. Default ranking lens and profile overlay.
- `references/build-pipeline.md`. Deterministic HTML/PDF/PPTX generation and validation.
- `references/slide-generation.md`. Slide structure and optional build prerequisites.
```

Three rows, each naming what the target holds and none naming when to open it. These three are
also the skill's **only** pointers to those files, so the blind index is the sole route to them.

Remediation: replace lines 140 to 144 with:

```markdown
## Reference index. Load on demand

- [`references/audience-defaults.md`](references/audience-defaults.md). Read when the invocation
  supplies no profile, or supplies one the profile table above does not name: the default ranking
  lens and the profile overlay.
- [`references/build-pipeline.md`](references/build-pipeline.md). Read before the first build of a
  run, for any output format: the deterministic HTML/PDF/PPTX generation and its validation gates.
- [`references/slide-generation.md`](references/slide-generation.md). Read when the requested
  format is slides: the slide structure and the optional build prerequisites.
```

**`plugins/discovery/skills/research-deep/SKILL.md:120`**

> `## See also`
>
```text
- `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md`, the shared discipline file
```

No condition, no intent, and the target is a sibling skill's private `context/` file. Remediation:

```markdown
## Reference index. Load on demand

- `/discovery:research`. The canonical three-phase workflow; Tiers 2 and 3 run it, a Tier-1 engine
  supersets it.
- [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md`](../research/context/discipline.md).
  Read before dispatching a Tier-2 subagent: the source tiers, recency gates, and falsification
  recipe the dispatched worker is graded against.
```

Reaching into a sibling skill's `context/` directory is also an encapsulation question. L4.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

32 files. No treatment.

## Cross-lane observations

- `plugins/discovery/agents/intent-tracer.md`, `researcher.md`, and `explorer.md` each carry a
  variant of the tool-honesty rule and a variant of the return contract. The split above extracts
  one copy; collapsing the three is L3.
- `plugins/discovery/skills/research/SKILL.md:22-71` and
  `plugins/discovery/skills/explore/SKILL.md:20-72` are near-identical routing sections. L3.
- `plugins/discovery/skills/research-deep/SKILL.md:123` cites another skill's `context/` file
  directly. L4.
