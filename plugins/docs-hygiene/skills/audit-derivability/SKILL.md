---
description: "Audit whether a documentation file earns its existence — could a fresh agent re-derive its conclusions by exploring the code, config, and structure itself? Read-only classifier: weighs derivability x re-derivation cost x drift risk x fact ownership into a verdict — delete, convert-to-pointer, keep-as-derivation-cache, or keep-owns-facts. Audience-aware: agent-facing surfaces get the full axe; human-facing docs clear a higher deletion bar. Use when: 'is this doc worth keeping', 'audit doc value', 'derivability', 'could an agent figure this out itself', 'should this doc exist', 'this doc just restates the code', 'prune redundant docs', 'does this doc earn its maintenance', or before deleting a doc — not line-level noise (/docs-hygiene:audit-noise), cross-file duplication (/docs-hygiene:extract-ssot), prose flavor (/docs-hygiene:compress), or code-mismatch staleness."
argument-hint: "[audit] [target] | sweep <dir>"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Judge whether a doc earns its existence or should become a pointer
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted .md files (first 20; empty = none): !`git status --porcelain 2>/dev/null | awk '/\.md$/{p=substr($0,4); sub(/^.* -> /,"",p); print p}' | head -20 || echo "(status unavailable)"`

## Purpose

Docs carry a standing tax: every tracked document must be kept true as the code it describes moves, and every low-signal document a reader (human or agent) wades through costs attention. A document earns that tax only when it holds something a reader could NOT cheaply reconstruct for themselves. This skill audits one axis the siblings do not: **document-level worth** — should this whole document exist at all?

The test is **derivability**: could a fresh agent reach this document's conclusions by natively exploring the repository — reading the code, config, metadata, and structure — without being handed the document? A document that only restates what the code already says is a derivation cache at best and dead weight at worst; a document that records *why* a decision was made, a constraint that is not visible in any single file, or a fact that lives outside the repo owns something exploration can never recover.

Read-only classifier: it surfaces a verdict per document with the reasoning; the author owns every deletion and rewrite. Deletion is the highest-stakes doc edit, so — like the sibling `/docs-hygiene:audit-noise` — this skill never applies it.

## The rubric — four factors, never derivability alone

A verdict is never "derivable, therefore delete." Derivability is one factor of four; weigh all four together. `context/rubric.md` holds the scoring detail this file only summarizes: factor definitions, the Diataxis fact-ownership mapping, the audience cost model, the spot-test protocol, and worked examples. Load it when a verdict is close.

| Factor | Question | Pushes toward |
|---|---|---|
| **Derivable?** | Could a fresh agent reconstruct these conclusions from native exploration alone? | derivable → delete/pointer; not derivable → keep |
| **Re-derivation cost** | If deleted, how expensive is it for the next reader to rebuild — a 2-second grep, or a multi-file investigation? | cheap → delete; expensive → keep-as-cache |
| **Drift risk** | How fast does the source move underneath this document, and how silently does the doc rot when it does? | high drift → delete/pointer; low drift → cache is safer |
| **Fact ownership** | Does the document OWN non-derivable facts — rationale, decisions, constraints, external facts, cross-cutting invariants no single file states? | owns facts → keep, regardless of derivability of the rest |

Fact ownership is the trump card: a document that owns even one non-derivable fact is kept (verdict `keep-owns-facts`), and the derivable remainder is routed to trimming (`/docs-hygiene:audit-noise`, `/docs-hygiene:extract-ssot`), not deletion.

## Verdict classes

| Verdict | Meaning | Condition |
|---|---|---|
| `delete` | The document is derivable, cheap to re-derive, and owns no non-derivable fact. It is dead weight. | All of: derivable, low re-derivation cost, no owned facts. Load-bearing or contested candidates require the empirical spot-test below before a confident `delete`. |
| `convert-to-pointer` | The document exists to route readers to a truth that lives elsewhere (code, another doc, an external source). Replace the body with a one-line pointer to the source of truth. | Derivable OR duplicative, but the routing/orientation value is real. Point, don't copy. The verdict MUST name its pointer target as a repo path verified to exist (or an external URL) — the verification is part of the rationale; a pointer at a nonexistent anchor is worse than the doc it replaces. |
| `keep-as-derivation-cache` | The content is derivable but re-derivation is expensive enough that a cached rendering earns its keep — IF the cache cannot silently rot. | Derivable + high re-derivation cost + **a drift-control condition is present**: a regeneration/verification path, or a recorded recheck trigger. Absent that condition, this verdict **demotes** to `convert-to-pointer` or `delete`. |
| `keep-owns-facts` | The document owns at least one non-derivable fact (rationale, decision, constraint, external fact, cross-cutting invariant). | Any owned non-derivable fact. Route the derivable remainder to the trimming siblings. |

A cache verdict with no regeneration path and no recheck trigger is an unmaintained copy that drifts silently from its source — demote it (the standing rule below; the why is in `context/rubric.md`).

### Out of scope — functional artifacts

A file a component CONSUMES or copies at runtime — a checklist template a skill instructs agents to copy and tick, an eval fixture, a scaffold — is machinery, not documentation, and receives NO verdict here. The one-line test: is this file an INPUT a tool or skill consumes, rather than prose a reader learns from? If yes, record it as `out-of-scope: functional artifact` in the ledger and move on — the four factors presuppose a document read for its claims, and a scaffold has none to derive.

## Audience-awareness

Re-derivation cost is paid by the reader, and agent-facing and human-facing readers pay differently — the same content can score differently by audience. Classify each document's primary audience and name it in the verdict; a document serving both is classified for each, taking the more conservative (keep-leaning) verdict. Agent-facing surfaces (`CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, skill and agent bodies) get the full axe — exploration is cheap and redundant context is a standing token tax. Human-facing docs (onboarding, READMEs, tutorials, architecture explainers) clear a higher bar — human re-derivation cost is real. Cost model and examples: `context/rubric.md`.

## Establishing derivability

Do NOT guess derivability from a skim. Two passes, escalating only where the stakes justify it:

1. **Heuristic claim-source classification (every document).** Classify each load-bearing claim by where its truth lives — *code/config/structure* (derivable), *another tracked doc* (duplication → `/docs-hygiene:extract-ssot`), or *nowhere else* (owned, non-derivable) — and let the mix drive a provisional verdict. Before an actionable verdict on an empty or near-empty file, check `git log` for evidence the state is deliberate: a deliberately emptied or reset file is a recorded decision (Factor 4) → `keep-owns-facts`.
2. **Empirical spot-test (load-bearing or contested deletions only).** Once this context has read the document it knows the answers and will overestimate how derivable they were — a self-grade. Confirm a `delete`/`convert-to-pointer` by delegating to a **fresh-context, non-fork subagent** (e.g. `Explore`) that has NOT seen the document: it reproduces the document's conclusions from native exploration only, then compare. Prefer a cross-vendor advisor for that spot-test when one is installed and set up — e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs — with the fresh-context same-vendor subagent as the fallback, never a route to a command that may not resolve. Convergence confirms derivable; divergence means the document owns something exploration could not recover — keep it. Never the Agent tool's `fork` subagent type for spot-tests that must stay uncontaminated — official docs contrast it (inherits the parent conversation) with a skill's own `context: fork` frontmatter (starts blank); an internal melodic-software tracker issue (#1258 there) contests whether the Agent-tool fork actually inherits at runtime, so treat the contrast as documented guidance for routing spot-tests, not as a settled probe result. Full protocol: `context/rubric.md`.

Gate the spot-test by stakes: skip it for an obviously trivial derivable file (an auto-generated index, a verbatim config restatement); run it whenever being wrong about the deletion costs a reader something real.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` files; file path → single doc; dir path → each `.md` directly in it | Run the rubric per document: heuristic pass, spot-test where gated, emit the verdict ledger |
| `audit [target]` | same target rules | Explicit form of the default; identical behavior |
| `sweep <dir>` | a directory to walk recursively | Corpus audit of the directory's tracked markdown (enumerate via `git ls-files -- '<dir>/*.md'` — one combined pathspec; two pathspecs (`'*.md' -- <dir>`) OR together and silently escalate the sweep to the whole repo. Gitignored and untracked files are out of scope, and so are `/docs-hygiene:extract-ssot`'s codified survey exclusions (vendored trees, eval fixtures, test data, run logs — `${CLAUDE_PLUGIN_ROOT}/skills/extract-ssot/actions/identify.md` owns that list; read it there, don't paraphrase it). Report the scope root and enumerated file count before fan-out. Throttled fan-out of fresh read-only subagents at a low concurrency ceiling (at most 3-4 at a time — rate-limit headroom beats wall-clock; the runtime may cap lower, which is fine). Small corpus: one document per subagent. Large corpus: batch ~15-25 documents per subagent, grouped by directory affinity so siblings share one exploration context — and route same-basename or near-identical files into ONE batch; where they still split, reconcile divergent verdicts on near-identical documents before the aggregate. Each subagent writes its per-document verdict blocks to a batch ledger file (session scratchpad or similar) and returns compact verdicts and counts; the reply carries the aggregate, the actionable subset, and pointers to the batch ledgers — corpus-scale per-document detail never streams through one context or one reply. Spot-test a small sample of keep verdicts too, so false-keeps are bounded, not only false-deletes. |

One action per response; actions do not chain implicitly. `sweep` is the only recursive mode — the bare/`audit` default never walks subdirectories, so a large tree is never audited by accident.

## Auto-detect default

1. Empty arg AND clean tree → no default target exists. Report that, then OFFER escalation to a repo-wide corpus sweep — never start it unprompted. Confirm with the user first (via `AskUserQuestion` where available, a plain prose question otherwise), presenting the prescribed defaults below pre-filled so a bare "yes" suffices; the interview may adjust any knob. Declining, or no answer, ends as the friendly no-op exit 0 ("No uncommitted .md files. Pass a file/dir target, or `sweep <dir>` for a corpus.")
2. Empty arg AND uncommitted `.md` files → audit those files
3. Single file path → single-document audit
4. Directory path (bare/`audit`) → audit each `.md` directly in the directory (non-recursive; filenames sorted lexically)
5. First positional == `sweep` → recursive throttled corpus audit on the rest

### Repo-wide escalation — prescribed defaults

The interview knobs for the confirmation in rule 1, each with its default. A confirmed escalation runs as a `sweep` over the resolved scope; every hard rule (read-only above all) still applies.

- **Scope** — all tracked `.md` files (`git ls-files '*.md'`); the user may narrow to a directory.
- **Execution** — the `sweep` contract: fresh read-only subagents, batched for a large corpus.
- **Concurrency** — a low ceiling (at most 3-4 concurrent): rate-limit headroom over wall-clock; the runtime may cap lower, which is fine. Raise only if the user asks.
- **Subagent model tier** — the session's model unless the user pins a tier.
- **Spot-tests** — run for load-bearing `delete`/`convert-to-pointer` verdicts up to a stated cap per pass. A flagged verdict past the cap is emitted as **provisional**: pending its spot-test, excluded from the actionable-routing offer, never presented as a confirmed delete. The cap *defers* the hard rule's spot-test to a follow-up pass; it never waives it.

## Output schema

Per document:

```text
<file> — verdict: <delete | convert-to-pointer | keep-as-derivation-cache | keep-owns-facts>  [audience: agent | human | both]

| Factor | Reading |
|--------|---------|
| Derivable? | <yes/partial/no> — <where the truth lives> |
| Re-derivation cost | <cheap/moderate/expensive> — <why> |
| Drift risk | <low/moderate/high> — <what moves underneath it> |
| Fact ownership | <none | owns: rationale / decision / constraint / external fact> |

Verdict rationale: <1-2 lines>.
Spot-test: <not run (trivial) | run — converged/diverged, subagent reproduced X of Y conclusions>.
Owned-fact salvage (if keep-owns-facts): <the non-derivable facts to preserve; route the rest to /docs-hygiene:audit-noise or extract-ssot>.
Cache drift-control (if keep-as-derivation-cache): <the regeneration path or recheck trigger that keeps it honest>.
```

Batch / sweep aggregate at the end:

```text
Audited <N> document(s): <d> delete, <p> convert-to-pointer, <c> keep-as-cache, <k> keep-owns-facts, <r> routed-to-sibling, <f> out-of-scope functional artifacts.
```

Corpus-scale sweeps (more documents than one reply can carry): the per-document blocks live in the batch ledger files; the reply carries the aggregate line, the confirmed-actionable (`delete` / `convert-to-pointer`) subset, the provisional (cap-deferred) verdicts reported separately for visibility — never as part of the actionable subset — and the ledger file locations.

After the ledger, OFFER to route actionable verdicts (delete / convert-to-pointer) to the consumer's work-item tracker — one item per document — and stop. Never auto-file, never auto-edit.

## Hard rules

- **Read-only with respect to the repository.** No `Edit` or `Write` inside the repo, no `Bash` that mutates it; session-scratchpad ledgers and artifacts are the one sanctioned write surface. The author applies every deletion and rewrite. Deletion is the highest-stakes doc edit; the classifier only recommends.
- **Never derivability alone.** A `delete` verdict requires all of: derivable, low re-derivation cost, no owned facts. Any owned non-derivable fact forces `keep-owns-facts`.
- **Cache verdicts carry a drift-control condition or they demote.** No regeneration path and no recheck trigger → not a cache, demote to pointer/delete.
- **Load-bearing or contested deletions are spot-tested by a fresh, non-fork subagent** — never confirmed from this (contaminated) context, never by the Agent tool's `fork` subagent type (official docs contrast it with a skill's `context: fork`, which starts blank; an internal melodic-software tracker issue contests the Agent-tool half at runtime — documented guidance for routing, not a settled probe result). A verdict whose spot-test is deferred (e.g. past a sweep's cap) stays provisional and is never routed as actionable.
- **Audience named in every verdict.** Agent-facing and human-facing docs clear different deletion bars.
- **The empty-target escalation is offer-only.** A repo-wide sweep from the no-op path runs only after explicit user confirmation; decline or silence ends as the no-op.
- **Owned facts are salvaged before anything is deleted.** When a doc is mostly derivable but owns a fact, the verdict is keep + route-the-remainder, never delete-and-lose.
- **Output deterministic.** Filenames sort lexically; no timestamps in output.

## Gotchas

- **Derivable is not a verdict.** "An agent could re-derive this" alone never justifies `delete` — check re-derivation cost, drift risk, and fact ownership first. The most common misfire is deleting a mostly-derivable doc that owned one buried rationale line.
- **The self-grade trap.** After reading a doc you know its answers, so it always *looks* re-derivable. Never confirm a load-bearing deletion from this context — delegate to a fresh, non-fork subagent that has not seen the doc, never the Agent tool's `fork` subagent type.
- **Cache without drift control is not a cache.** `keep-as-derivation-cache` with no regeneration path and no recheck trigger is an unmaintained copy; demote it.
- **Code-derivable ≠ duplicates-another-doc.** A doc restating *another doc* is `/docs-hygiene:extract-ssot`, not a `delete` here. Derivability is re-derivation from code/config/structure.
- **Audience changes the verdict.** The same restatement can be dead weight on an agent surface and worth keeping for humans. Do not carry one surface's verdict to the other.

## What this skill is NOT

- **Not `/docs-hygiene:audit-noise`.** That classifies line-level noise *inside* a document worth keeping. This decides whether the whole document is worth keeping. A doc can pass audit-derivability (`keep-owns-facts`) and still have noise lines for audit-noise to trim.
- **Not `/docs-hygiene:extract-ssot`.** That deduplicates a unit repeated across 3+ files into one home. Derivability is re-derivation from CODE/config/structure, not from another markdown file. A doc that duplicates *another doc* is extract-ssot's; a doc that restates *the code* is this skill's.
- **Not `/docs-hygiene:compress`.** That trims prose flavor within a doc that stays. This deletes or repoints whole docs.
- **Not a doc-drift / staleness detector.** Those ask "does this doc still match the code?" This asks "should this doc exist even when it is perfectly accurate?" — a currently-correct doc can still be dead weight because it is trivially re-derivable and carries drift risk.
- **Not a doc generator or an Edit operation.** It recommends; the author acts.

## Sources

- [Diátaxis](https://diataxis.fr) — the four documentation modes; the fact-ownership factor leans on its separation of derivable reference material from explanation, which owns the non-derivable *why*.

## Recheck triggers

| Condition | Action |
|---|---|
| The rubric is proven over real audits | Route it upstream to `melodic-software/standards` as shared doc-value policy (deferred; ledger E-a) |
| Demand surfaces for applying verdicts, not just classifying | Revisit the deferred remediation/apply action (deferred; ledger E-b) |
| A native "regenerate this doc from source" mechanism ships | Strengthen the `keep-as-derivation-cache` drift-control test to prefer regeneration over a recorded recheck trigger |
