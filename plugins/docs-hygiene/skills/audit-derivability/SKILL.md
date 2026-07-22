---
name: audit-derivability
description: "Audit whether a documentation file earns its existence — could a fresh agent re-derive its conclusions by exploring the code, config, metadata, and structure itself? Read-only classifier: weighs each doc on derivability x re-derivation cost x drift risk x fact ownership and returns a verdict — delete, convert-to-pointer, keep-as-derivation-cache (drift-control required), or keep-owns-facts (rationale, decisions, constraints, external facts are non-derivable). Audience-aware: agent-facing surfaces get the full axe because exploration is cheap; human-facing docs weigh human derivation cost and clear a higher deletion bar. Use when: 'is this doc worth keeping', 'audit doc value', 'derivability', 'could an agent figure this out itself', 'should this doc exist', 'this doc just restates the code', 'prune redundant docs', 'does this doc earn its maintenance', before deleting a doc or before writing one that restates the codebase — not line-level noise inside a doc worth keeping (use /docs-hygiene:audit-noise), cross-file duplication (/docs-hygiene:extract-ssot), prose flavor (/docs-hygiene:compress), or code-mismatch staleness (a doc-drift detector)."
argument-hint: "[audit] [target] | sweep <dir>"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted .md files: !`git status --porcelain 2>/dev/null | grep '\.md$' | sed 's/^...//' | head -20 || echo "none"`

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
| `convert-to-pointer` | The document exists to route readers to a truth that lives elsewhere (code, another doc, an external source). Replace the body with a one-line pointer to the source of truth. | Derivable OR duplicative, but the routing/orientation value is real. Point, don't copy. |
| `keep-as-derivation-cache` | The content is derivable but re-derivation is expensive enough that a cached rendering earns its keep — IF the cache cannot silently rot. | Derivable + high re-derivation cost + **a drift-control condition is present**: a regeneration/verification path, or a recorded recheck trigger. Absent that condition, this verdict **demotes** to `convert-to-pointer` or `delete`. |
| `keep-owns-facts` | The document owns at least one non-derivable fact (rationale, decision, constraint, external fact, cross-cutting invariant). | Any owned non-derivable fact. Route the derivable remainder to the trimming siblings. |

A cache verdict with no regeneration path and no recheck trigger is an unmaintained copy that drifts silently from its source — demote it (the standing rule below; the why is in `context/rubric.md`).

## Audience-awareness

Re-derivation cost is paid by the reader, and agent-facing and human-facing readers pay differently — the same content can score differently by audience. Classify each document's primary audience and name it in the verdict; a document serving both is classified for each, taking the more conservative (keep-leaning) verdict. Agent-facing surfaces (`CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, skill and agent bodies) get the full axe — exploration is cheap and redundant context is a standing token tax. Human-facing docs (onboarding, READMEs, tutorials, architecture explainers) clear a higher bar — human re-derivation cost is real. Cost model and examples: `context/rubric.md`.

## Establishing derivability

Do NOT guess derivability from a skim. Two passes, escalating only where the stakes justify it:

1. **Heuristic claim-source classification (every document).** Classify each load-bearing claim by where its truth lives — *code/config/structure* (derivable), *another tracked doc* (duplication → `/docs-hygiene:extract-ssot`), or *nowhere else* (owned, non-derivable) — and let the mix drive a provisional verdict.
2. **Empirical spot-test (load-bearing or contested deletions only).** Once this context has read the document it knows the answers and will overestimate how derivable they were — a self-grade. Confirm a `delete`/`convert-to-pointer` by delegating to a **fresh-context, non-fork subagent** (e.g. `Explore`) that has NOT seen the document: it reproduces the document's conclusions from native exploration only, then compare. Prefer a cross-vendor advisor for that spot-test when one is installed — e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs — with the fresh-context same-vendor subagent as the fallback, never a route to a command that may not resolve. Convergence confirms derivable; divergence means the document owns something exploration could not recover — keep it. Never a `context: fork` — a fork inherits this context's contamination. Full protocol: `context/rubric.md`.

Gate the spot-test by stakes: skip it for an obviously trivial derivable file (an auto-generated index, a verbatim config restatement); run it whenever being wrong about the deletion costs a reader something real.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` files; file path → single doc; dir path → each `.md` directly in it | Run the rubric per document: heuristic pass, spot-test where gated, emit the verdict ledger |
| `audit [target]` | same target rules | Explicit form of the default; identical behavior |
| `sweep <dir>` | a directory to walk recursively | Corpus audit. Throttled **doc-by-doc** fan-out: dispatch a fresh read-only subagent per document (bounded concurrency, e.g. 3-5 at a time), each returning one document's verdict; aggregate into one ledger. Never load the whole corpus into one context. |

One action per response; actions do not chain implicitly. `sweep` is the only recursive mode — the bare/`audit` default never walks subdirectories, so a large tree is never audited by accident.

## Auto-detect default

1. Empty arg AND clean tree → friendly no-op exit 0 ("No uncommitted .md files. Pass a file/dir target, or `sweep <dir>` for a corpus.")
2. Empty arg AND uncommitted `.md` files → audit those files
3. Single file path → single-document audit
4. Directory path (bare/`audit`) → audit each `.md` directly in the directory (non-recursive; filenames sorted lexically)
5. First positional == `sweep` → recursive throttled corpus audit on the rest

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
Audited <N> document(s): <d> delete, <p> convert-to-pointer, <c> keep-as-cache, <k> keep-owns-facts.
```

After the ledger, OFFER to route actionable verdicts (delete / convert-to-pointer) to the consumer's work-item tracker — one item per document — and stop. Never auto-file, never auto-edit.

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash`. The author applies every deletion and rewrite. Deletion is the highest-stakes doc edit; the classifier only recommends.
- **Never derivability alone.** A `delete` verdict requires all of: derivable, low re-derivation cost, no owned facts. Any owned non-derivable fact forces `keep-owns-facts`.
- **Cache verdicts carry a drift-control condition or they demote.** No regeneration path and no recheck trigger → not a cache, demote to pointer/delete.
- **Load-bearing or contested deletions are spot-tested by a fresh, non-fork subagent** — never confirmed from this (contaminated) context, never by a fork.
- **Audience named in every verdict.** Agent-facing and human-facing docs clear different deletion bars.
- **Owned facts are salvaged before anything is deleted.** When a doc is mostly derivable but owns a fact, the verdict is keep + route-the-remainder, never delete-and-lose.
- **Output deterministic.** Filenames sort lexically; no timestamps in output.

## Gotchas

- **Derivable is not a verdict.** "An agent could re-derive this" alone never justifies `delete` — check re-derivation cost, drift risk, and fact ownership first. The most common misfire is deleting a mostly-derivable doc that owned one buried rationale line.
- **The self-grade trap.** After reading a doc you know its answers, so it always *looks* re-derivable. Never confirm a load-bearing deletion from this context — delegate to a fresh, non-fork subagent that has not seen the doc.
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
