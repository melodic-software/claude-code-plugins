# Contract spec — discovery-subagent-dispatch

The five cross-boundary contracts this design owes. Companion to
[`design-threads.md`](design-threads.md); the ratified decisions live in [`../PLAN.md`](../PLAN.md)
and are not restated.

Upstream harness facts are **pointed at, never restated** — per issue #1225's locked pointer-not-copy
rule, the link index is [`docs/OFFICIAL-DOCS.md`](../../../OFFICIAL-DOCS.md) and the canonical page
for every frontmatter field below is <https://code.claude.com/docs/en/sub-agents>.

## C1 — Agent-definition frontmatter contract

Two definitions under `plugins/discovery/agents/`. Shape follows the seven already shipped in
`plugins/review/agents/` and `plugins/plugin-quality/agents/` — quoted `tools` string, `memory: local`,
explicit `effort` and `maxTurns` — with one addition none of them use: `skills:`.

> **Amendment 2026-07-25 (adversarial stress-test, findings F1/F2 + assumption 5).** The frontmatter
> below is the corrected form. Three changes from the ratified version, each forced by a verified
> upstream fact:
>
> 1. **`memory: local` REMOVED from both.** Verified verbatim at
>    <https://code.claude.com/docs/en/sub-agents>: "Read, Write, and **Edit** tools are automatically
>    enabled so the subagent can manage its memory files." Declaring `memory` therefore re-enables
>    `Edit` regardless of `tools`, which falsified this contract's own "`Edit` is **absent by
>    design**" claim and destroyed the tool-cage argument entirely. Corroborated in-repo:
>    `plugin-quality:auditor` — the one shipped agent that carries `Write` — declares no `memory`;
>    the six `review/` agents that do declare it are all read-only. Removing it also resolves the
>    independent objection that an accumulating `MEMORY.md` is a Tier-3-recall laundering channel
>    inside a skill whose core rule is that training-data recall is inadmissible.
> 2. **`skills:` is a YAML list of bare names, not a quoted scoped string.** The only documented
>    example is a list (`skills:\n  - api-conventions`). The scoped-string form was never
>    documented, and a wrong value form fails **silently** (see 3). The exact resolvable name is an
>    empirical question closed before Phase 1, not during it.
> 3. **A missing or disabled preload is silent.** Verified verbatim: "If a listed skill is missing or
>    disabled, Claude Code skips it and logs a warning to the debug log." Nothing surfaces at
>    runtime. C2 therefore gains a mandatory preload-liveness sentinel.

```yaml
---
name: researcher
description: "…dispatched by /discovery:research; not intended for direct ad-hoc use."
tools: "Read, Grep, Glob, Bash, WebFetch, WebSearch, Write, Skill"
skills:
  - research          # exact resolvable form verified empirically before Phase 1
model: inherit
effort: high
maxTurns: 40
---
```

```yaml
---
name: explorer
description: "…dispatched by /discovery:explore; not intended for direct ad-hoc use."
tools: "Read, Grep, Glob, Bash, Write, Skill"
skills:
  - explore           # exact resolvable form verified empirically before Phase 1
model: inherit
effort: high
maxTurns: 30
---
```

Field rationale:

- **`tools`** — `Edit` is absent, and that absence is real **only because `memory` is not declared**
  (see the amendment above). What the cage actually buys: no single-call in-place mutation of an
  existing repo file. What it does **not** buy: read-only status, or mechanical enforcement of the
  memory-tier invariant — `Bash` and `Write` both write, per the doctrine's own tool-cage wording.
  State it that way in the agent body; do not call the agent read-only. `Skill` stays regardless of
  `skills:` preload, per Amendment 8.
- **`skills`** — Decision 12. `research/SKILL.md` was verified preload-suitable this session: 187
  lines, one trivial `!` precompute (`git branch --show-current`), zero `allowed-tools`, zero
  `${user_config.…}`. Amendment 9b's measured behavior applies — the SKILL.md body only, with
  `${CLAUDE_PLUGIN_ROOT}` expanded, so `context/discipline.md` stays lazy.
- **`model: inherit`** — stated explicitly rather than omitted. A research verdict is consequential,
  and the doctrine's ladder requires session tier or above; `inherit` guarantees exactly session
  tier and never below. A hard pin would fight `CLAUDE_CODE_SUBAGENT_MODEL` and the doctrine's own
  dated tier table, which carries a recheck trigger this design should not duplicate.
- **`hooks` / `mcpServers` / `permissionMode`** — omitted. Plugin-shipped agents ignore all three.
- **`memory`** — **omitted deliberately**, and the omission is load-bearing. See the amendment above.
- **`background`** — omitted; background is the default from v2.1.198 and is wanted here.

**Named-agent bar conformance** (PR #1096): multi-site is satisfied — the same worker dispatches
from `/discovery:research` and from the marketplace's DISPATCH-DEFAULT rows. The second conjunct is
**argued from the tool cage, not met** — the cage narrows the write surface without enforcing the
memory-tier invariant, and the F1 amendment makes clear how close that argument came to collapsing
outright. The genuinely load-bearing capability is `skills:` preload, which the bar does not
enumerate; the upstream proposal to admit it as a third qualifier rides on #304 / #1096. Do not
overstate this conjunct anywhere downstream.

## C2 — Return payload (verification request)

An instance of issue #496's return-payload contract: identifiers plus verdict plus parked payload,
never the transcript. The agent returns one fenced YAML block followed by at most one paragraph of
prose.

```yaml
preload_token: <sentinel>     # F2: echoed verbatim from the preloaded skill; absence = hard failure
status: complete              # complete | truncated — F3: written before the turn budget runs out
artifact: .work/<topic-slug>/RESEARCH.md
sidecars: 3
coverage: complete            # complete | partial — mirrors the C4 ledger's gate
verification: pending         # pending | not-required
verification_request:
  target: .work/<topic-slug>/RESEARCH.md
  criterion: "every accepted claim is HIGH confidence"   # the gate row the producer may not self-grade
  worker: fresh-context subagent
open_questions:               # the agent cannot call AskUserQuestion; the parent re-surfaces these
  - "<question>"
```

**`preload_token` — the preload-liveness sentinel (amendment 2026-07-25, finding F2).** A missing or
disabled `skills:` entry is skipped **silently**, logging only to the debug log — verified verbatim
at <https://code.claude.com/docs/en/sub-agents>. Without a liveness signal, a preload miss produces
an undisciplined run that still writes an artifact and still self-reports `coverage: complete`: the
failure mode is indistinguishable from success at every seam this design builds, which is precisely
the guarantee Decision 12 exists to provide. The preloaded skill therefore carries a sentinel string
the agent must echo verbatim into this payload. **The parent treats a missing or mismatched
`preload_token` as a hard failure and discards the run** — it does not downgrade, warn, or accept the
artifact. This is the one seam that makes "the mandate arrived" observable rather than assumed.

**`status` — the truncation contract (amendment 2026-07-25, finding F3).** `maxTurns` has no
documented partial-return semantics: the docs define it only as "Maximum number of agentic turns
before the subagent stops." Because this design writes the ledger and sidecars incrementally, a
turn-limit stop otherwise leaves a half-marked ledger, orphan sidecars, and an index naming files
that were never written — with **no payload at all**, so the parent never learns the run died. Rules:
the agent writes `status: truncated` plus a partial payload before its budget is exhausted; a
dispatch that returns **no** payload is treated as truncated-without-warning; in both cases the
parent discards the partial slice rather than resuming it, because a half-run ledger cannot be
distinguished from a complete one by the coverage script alone.

`verification: pending` is Decision 9's non-negotiable: the producing agent renders no verdict on
its own confidence criterion. The orchestrator dispatches the verifier as a **sibling**, which is
why nesting stays an optimization rather than a correctness prerequisite.

### Outcome-gate row assignment

Decision 13 splits the gate three ways but does not enumerate it. The split rule: a row the producer
can **read off an artifact** stays with the producer; a row where the producer would **judge the
quality of its own choices** goes to the sibling verifier; a row needing the consuming project's
conventions stays with the parent, which alone holds them.

| Row | Criterion (abbreviated) | Owner |
|-----|-------------------------|-------|
| 1 | Tier 0/1 source captured this turn | producer |
| 2 | No claim row is all Tier-2 | producer |
| 3 | Every Phase 2/3 query traces to a numbered gap | producer |
| 4 | ≥2 **independent** corroborators, not one upstream pool | **verifier** |
| 5 | Falsification query ran and is recorded | producer |
| 6 | Recency gate satisfied | producer |
| 7 | Every accepted claim is HIGH confidence | **verifier** |
| 8 | Project fit against the consuming project's conventions | **parent** |
| 9 | Fetch log shows the topmost existing rung *(PR #1260)* | producer |
| 10 | Every absence names checked and unchecked sets *(PR #1260)* | producer |
| — | Coverage ledger fully marked *(C4, new)* | producer, script-verdict |

Row 4 lands with the verifier rather than the producer despite looking mechanical: "independent"
is a judgment over the source set the producer itself assembled, which is the same self-grade class
as row 7.

**Amendment 2026-07-25 (finding F7) — row 4 was not gradeable as specified.** The verifier reads the
persisted artifact and has never seen the run, and the skill's own gate demands every criterion be
read off an artifact. Row 7 clears that bar: C3's header carries `claims[].confidence`. Row 4 —
"≥2 **independent** corroborators, not one upstream pool" — did not, because C3 persisted only
`tiers: [0, 1]`, which encodes neither independence nor pool provenance. C3's header is therefore
extended (below) to carry per-claim source URLs with independence attribution. Without that
extension the only honest alternative was to move row 4 back to the producer as a declared
self-grade; the extension is preferred because row 4 is the corroboration bar the whole discipline
rests on. Rows 9 and 10 are counted here because PR #1260 is changing this table's row count before
this design is implemented — the assignment is written against the post-merge table deliberately.

**Open tension this contract must resolve** — `research/SKILL.md:148` currently reads: *"Subagent
returns are Tier 3 (synthesis), not corroborators, until their cited primaries are fetched this
turn."* Read literally, dispatch-by-default demotes every research run to Tier 3, because the
orchestrator's view of the work IS a subagent return. The rule was written against an **ad-hoc
subagent summary**, not against a dispatched agent that ran the full discipline and captured every
primary URL into the artifact. The tier belongs to the **artifact and its captured sources**, not to
the transport. The rule needs a scoped exception naming the discipline-running dispatched case;
without it, Decision 1 contradicts the skill it is modifying. This is a required edit to
`research/SKILL.md` and therefore lands in PR #1260's collision surface.

## C3 — Sidecar header schema

YAML frontmatter, chosen over an HTML comment block: it parses with tooling the repo already runs
and matches the skill/agent frontmatter convention used marketplace-wide. Vocabulary is **reused,
not invented** — `HIGH | MEDIUM | LOW` and `Tier 0..3` are the research skill's own
(`SKILL.md:42`, `context/discipline.md:9-12`).

```yaml
---
topic: <topic-slug>
section: <stable kebab-case id, matches the index anchor>
abstract: <one line, mirrored verbatim into the index>
claims:
  - claim: "<one-line claim>"
    confidence: HIGH          # HIGH | MEDIUM | LOW
    tiers: [0, 1]             # source tiers backing this claim
    sources:                  # F7: row 4 is ungradeable without provenance
      - url: "<url fetched this turn>"
        tier: 1
        pool: "<publisher/org — two sources sharing a pool are NOT independent>"
produced_by: <phase id>
---
```

The index (`RESEARCH.md` / `EXPLORE.md`) carries a task restatement, the per-sidecar `abstract`
verbatim, and a section → file+anchor table. A consumer greps headers, then reads exactly one
sidecar.

Amendment 5 scopes this: index-plus-sidecars applies to artifact-producing skills, not to every
dispatched skill.

## C4 — Coverage ledger (`research-checklist.md`)

Written in Phase 0, before any query. One row per corpus item.

```markdown
| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | <item>      | <what counts as covered for THIS item> | [ ] |
```

The depth criterion is fixed at enumeration time and is per-item, not global — that is what
Decision 6 buys by giving enumeration its own phase.

**Gate is a script, not a model read.** A `check-coverage-complete.sh` returns non-zero when any
`Done` cell is unmarked; the outcome-gate row cites the script's exit status. Two consequences:
the verdict is deterministic and survives a context that wants to be done, and the row earns check
21's `deterministic-gate` exemption class honestly rather than needing a delegation declaration.

## C5 — Execution-site declaration

Decision 13 already fixed the *shapes* — an execution-site column on an action-router table, and
per-step annotation plus a handoff contract. No new frontmatter. This contract fixes only the
**enforcement**.

Extend the existing declaration contract owned by
`plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` (PR #1096, check 21)
rather than standing up a second scanner. Check 21 declares *who judges*; this adds *where a phase
executes* — an adjacent proposition over the same greppable, deterministic substrate:

- **Closed value set** for the execution-site column: `dispatch` | `inline` | `either`.
- **Exemption directive** reuses the established grammar and comment form, with its own closed class
  set and a mandatory `-- <reason>`, per the ESLint-description precedent that contract cites.
- Spec ownership stays with `skill-quality`; discovery is a consumer, not a second spec owner.

This is an upstream contribution to #304's program, sequenced after #1096 merges.
