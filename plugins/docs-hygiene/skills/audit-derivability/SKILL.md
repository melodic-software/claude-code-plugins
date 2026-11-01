---
description: "Read-only audit of whether a doc earns its existence: could a fresh agent re-derive it from code, config, and structure? One verdict per file: delete, convert-to-pointer, keep-as-derivation-cache, or keep-owns-facts. Use when: 'is this doc worth keeping', 'audit doc value', 'derivability', 'could an agent figure this out itself', 'should this doc exist', 'this doc just restates the code', 'prune redundant docs', 'does this doc earn its maintenance'. Line-level noise is /docs-hygiene:audit-noise."
argument-hint: "[target|audit [target]|sweep <dir>]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/uncommitted-md.sh:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/uncommitted-md.sh\":*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Judge whether a doc earns its existence or should become a pointer
---

## Repository context. Gather first

Collect with **individual** Bash calls, one command per call, never combined:

- Current branch, `git branch --show-current`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
body Bash calls, not pre-compute lines: the harness runs a skill's whole pre-compute block as one
shell invocation, and a worktree-isolated session refuses a compound command containing git. The dated record for that composition claim is the
[gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation),
"The pre-compute block runs as one shell invocation".

## Pre-computed context

Uncommitted .md files (first 20; empty = none matched or the probe returned nothing): !`"${CLAUDE_SKILL_DIR}/scripts/uncommitted-md.sh" 20 2>/dev/null || echo "(status unavailable)"`

Every command in this line matches an `allowed-tools` grant, so a dontAsk lane can run this skill.

- **Pointer**: when changing this line or its grants, fetch <https://code.claude.com/docs/en/skills#permission-checks-on-injected-commands> live; the probe that found a zero-turn run under dontAsk is in <https://github.com/melodic-software/claude-code-plugins/pull/6732>. **As of**: 2026-10-11. **Recheck trigger**: a Claude Code release note that changes how pre-compute commands are permission-checked.

## Purpose

Every tracked document must be kept true as its code moves, and every low-signal document costs its readers (human or agent) attention. A document earns that only when it holds something a reader could NOT cheaply reconstruct. This skill audits **document-level worth**: should this whole document exist at all?

The test is **derivability**: could a fresh agent reach the document's conclusions by natively exploring the repository (code, config, metadata, structure) without being handed it? A document that only restates the code is a derivation cache at best and dead weight at worst; one that records *why* a decision was made, a constraint no single file shows, or a fact outside the repo owns something exploration can never recover.

Read-only classifier: it reports a verdict per document with the reasoning; the author owns every deletion and rewrite. Deletion is the highest-stakes doc edit, so, like `/docs-hygiene:audit-noise`, this skill never applies it.

## The rubric. Four factors, never derivability alone

A verdict is never "derivable, therefore delete." Weigh all four factors together. `context/rubric.md` holds the scoring detail: factor definitions, the Diataxis fact-ownership mapping, the audience cost model, the spot-test protocol, and worked examples. Load it when a verdict is close.

| Factor | Question | Pushes toward |
|---|---|---|
| **Derivable?** | Could a fresh agent reconstruct these conclusions from native exploration alone? | derivable → delete/pointer; not derivable → keep |
| **Re-derivation cost** | If deleted, what does the next reader pay to rebuild it: a 2-second grep, or a multi-file investigation? | cheap → delete; expensive → keep-as-cache |
| **Drift risk** | How fast does the source move, and how silently does the doc rot when it does? | high drift → delete/pointer; low drift → cache is safer |
| **Fact ownership** | Does the document OWN non-derivable facts: rationale, decisions, constraints, external facts, cross-cutting invariants no single file states? | owns facts → keep, regardless of derivability of the rest |

Fact ownership is the trump card: a document owning even one non-derivable fact is kept (`keep-owns-facts`), and the derivable remainder routes to trimming (`/docs-hygiene:audit-noise`, `/docs-hygiene:extract-ssot`), not deletion.

## Verdict classes

| Verdict | Meaning | Condition |
|---|---|---|
| `delete` | Derivable, cheap to re-derive, owns no non-derivable fact: dead weight. | All of: derivable, low re-derivation cost, no owned facts. Load-bearing or contested candidates require the empirical spot-test below before a confident `delete`. |
| `convert-to-pointer` | Exists to route readers to a truth that lives elsewhere (code, another doc, an external source). Replace the body with a one-line pointer to the source of truth. | Derivable OR duplicative, but the routing/orientation value is real. The verdict MUST name its pointer target as a repo path verified to exist (or an external URL), with the verification in the rationale; a pointer at a nonexistent anchor is worse than the doc it replaces. |
| `keep-as-derivation-cache` | Derivable, but re-derivation is expensive enough that a cached rendering earns its keep, IF the cache cannot silently rot. | Derivable + high re-derivation cost + **a drift-control condition is present**: a regeneration/verification path, or a recorded recheck trigger. Absent that condition, this verdict **demotes** to `convert-to-pointer` or `delete`. |
| `keep-owns-facts` | Owns at least one non-derivable fact (rationale, decision, constraint, external fact, cross-cutting invariant). | Any owned non-derivable fact. Route the derivable remainder to the trimming siblings. |

### Out of scope. Functional artifacts

A file a component CONSUMES or copies at runtime (a checklist template a skill instructs agents to copy and tick, an eval fixture, a scaffold) is machinery, not documentation, and gets NO verdict. Test: is this file an INPUT a tool or skill consumes, rather than prose a reader learns from? If yes, record it as `out-of-scope: functional artifact` in the ledger and move on: the four factors presuppose a document read for its claims, and a scaffold has none.

## Audience-awareness

Re-derivation cost is paid by the reader, and agent and human readers pay differently, so the same content can score differently by audience. Classify each document's primary audience and name it in the verdict; a document serving both is classified for each, taking the more conservative (keep-leaning) verdict. Agent-facing surfaces (`CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, skill and agent bodies) get the full axe: exploration is cheap and redundant context is a standing token tax. Human-facing docs (onboarding, READMEs, tutorials, architecture explainers) clear a higher bar: human re-derivation cost is real. Cost model and examples: `context/rubric.md`.

## Establishing derivability

Do NOT guess derivability from a skim. Two passes, escalating only where the stakes justify it:

1. **Heuristic claim-source classification (every document).** Classify each load-bearing claim by where its truth lives: *code/config/structure* (derivable), *another tracked doc* (duplication → `/docs-hygiene:extract-ssot`), or *nowhere else* (owned, non-derivable); the mix drives a provisional verdict. Before EVERY `delete` or `convert-to-pointer` verdict that recommends a change (not `convert-to-pointer (already satisfied)`), check `git log` for the file: a commit recording a decision about the doc (a deliberate creation, or a deliberate empty or reset state) is an owned fact (Factor 4). Mechanical history is derivable; a decision or rationale in a commit message is not. Where the decision IS the file's state (a deliberately emptied file) the verdict is `keep-owns-facts`; otherwise it ships **provisional** with the text `reverses a recorded decision`, never as confirmed-actionable.
2. **Empirical spot-test (load-bearing or contested deletions only).** Having read the document, this context knows the answers and will overestimate how derivable they were: a self-grade. Confirm a `delete`/`convert-to-pointer` by delegating to a **fresh-context, non-fork subagent** that has NOT seen the document. When the audited file loads at launch (root `CLAUDE.md`, `AGENTS.md`, an unscoped `.claude/rules` file), the subagent MUST be `Explore` or `Plan`: every other built-in type, and a custom one unless its definition sets `omitClaudeMd`, loads those files before it starts (see Sources). Keeping to `Explore` or `Plan` is this skill's choice. The subagent reproduces the document's conclusions from native exploration only; then compare. Prefer a cross-vendor advisor for the spot-test **when one is installed and set up**, e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs, with the fresh-context same-vendor subagent as the stated fallback, never a route to a command that may not resolve (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository). Convergence confirms derivable; divergence means the document owns something exploration could not recover: keep it. Never the Agent tool's `fork` subagent type: a fork inherits the parent conversation, carrying the contamination the spot-test exists to avoid. A skill's own `context: fork` frontmatter is different and starts blank. Full protocol: `context/rubric.md`.

Gate the spot-test by stakes: skip it for an obviously trivial derivable file (an auto-generated index, a verbatim config restatement); run it whenever being wrong about the deletion costs a reader something real.

Keep verdicts get a sampled spot-test too, so false-keeps are bounded. A **diverged** keep-sample confirms the keep. A **converged** one sends the doc back through the four factors; any `delete`/`convert-to-pointer` result ships provisional (never confirmed-actionable) and counts as overturned. Sizing, selection, and recording: `context/rubric.md`, "Keep-sample protocol".

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` files; file path → single doc; dir path → each `.md` directly in it | Run the rubric per document: heuristic pass, spot-test where gated, emit the verdict ledger |
| `audit [target]` | same target rules | Explicit form of the default; identical behavior |
| `sweep <dir>` | a directory to walk recursively | Corpus audit of the directory's tracked markdown. Enumerate via `git ls-files -- '<dir>/*.md'`, one combined pathspec: two pathspecs (`'*.md' -- <dir>`) OR together and silently escalate the sweep to the whole repo. Gitignored and untracked files are out of scope, and so are `/docs-hygiene:extract-ssot`'s codified survey exclusions (vendored trees, eval fixtures, test data, run logs; `${CLAUDE_PLUGIN_ROOT}/skills/extract-ssot/actions/identify.md` owns that list; read it there, don't paraphrase it). Report the scope root and enumerated file count before fan-out. Fan out fresh read-only subagents (no concurrency ceiling of the skill's own; the runtime may cap, which is fine; an actual rate-limit error is the only reason to back off). Small corpus: one document per subagent. Large corpus: batch ~15-25 documents per subagent, grouped by directory affinity so siblings share one exploration context, and route same-basename or near-identical files into ONE batch; where they still split, reconcile divergent verdicts on near-identical documents before the aggregate. Each subagent writes its per-document verdict blocks to a batch ledger file (session scratchpad or similar) and returns compact verdicts and counts; the reply carries the aggregate, the actionable subset, and pointers to the batch ledgers. Corpus-scale per-document detail never streams through one context or one reply. Spot-test a sample of `keep-owns-facts` verdicts too, so false-keeps are bounded, not only false-deletes: every tenth keep in lexical filename order, at least one per batch ledger (the ten is judgment). Record the sampled file list beside the batch ledger when it is drawn; never reconstruct it later. Outcomes: `context/rubric.md`, "Keep-sample protocol". |

One action per response; actions do not chain implicitly. `sweep` is the only recursive mode; the bare/`audit` default never walks subdirectories, so a large tree is never audited by accident.

**Sweep subagent model and effort.** Every `sweep` fan-out, explicit or reached through the repo-wide escalation, sets these per subagent; a tier the user pins wins. When `/multi-agent:route` resolves in this session, run `/multi-agent:route worker session=<this session's model alias>` and pass its `fanout` variant: the model unless `omit_model` is true, and the effort always. When it does not resolve, omit the model so subagents inherit the session's, except when the session model is frontier or unknown, where pass `opus`; pass effort `medium`. That fallback is this skill's stand-in for the role map `/multi-agent:route` applies, not an upstream default; say once in the reply that enabling the multi-agent plugin makes this routing configurable.

## Auto-detect default

Shared clean-tree / no-scope shape: [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md). Read it when the bare invocation is unattended or non-interactive, the case the rules below leave unstated, or when editing those rules.

1. Empty arg AND clean tree → no default target exists. Report that, then OFFER escalation to a repo-wide corpus sweep; never start it unprompted. Confirm with the user first (via `AskUserQuestion` where available, a plain prose question otherwise), with the prescribed defaults below pre-filled so a bare "yes" suffices; the interview may adjust any knob. Declining, or no answer, ends as the friendly no-op exit 0 ("No uncommitted .md files. Pass a file/dir target, or `sweep <dir>` for a corpus.")
2. Empty arg AND uncommitted `.md` files → audit those files
3. Single file path → single-document audit
4. Directory path (bare/`audit`) → audit each `.md` directly in the directory (non-recursive; filenames sorted lexically)
5. First positional == `sweep` → recursive corpus audit on the rest

### Repo-wide escalation. Prescribed defaults

The interview knobs for the confirmation in rule 1, each with its default. A confirmed escalation runs as a `sweep` over the resolved scope; every hard rule (read-only above all) still applies.

- **Scope**. All tracked `.md` files (`git ls-files '*.md'`); the user may narrow to a directory.
- **Execution**, the `sweep` contract: fresh read-only subagents, batched for a large corpus.
- **Concurrency**, no ceiling of the skill's own; the runtime's cap applies. Back off on an actual rate-limit error, never on guessed usage headroom.
- **Subagent model and effort**, per **Sweep subagent model and effort** under Action router; the user may pin a tier.
- **Spot-tests**. Run for load-bearing `delete`/`convert-to-pointer` verdicts up to a stated cap per pass. A flagged verdict past the cap is emitted as **provisional**: pending its spot-test, excluded from the actionable-routing offer, never presented as a confirmed delete. The cap *defers* the hard rule's spot-test to a follow-up pass; it never waives it.

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
Spot-test: <not run (trivial) | run — converged/diverged, subagent reproduced X of Y conclusions | keep-sample: converged/diverged>.
Provisional (if any): <reverses a recorded decision | spot-test deferred | keep-sample converged, verdict overturned>.
Owned-fact salvage (if keep-owns-facts): <the non-derivable facts to preserve; route the rest to /docs-hygiene:audit-noise or extract-ssot>.
Cache drift-control (if keep-as-derivation-cache): <the regeneration path or recheck trigger that keeps it honest>.
```

Batch / sweep aggregate at the end:

```text
Audited <N> document(s): <d> delete, <p> convert-to-pointer, <c> keep-as-cache, <k> keep-owns-facts, <f> out-of-scope functional artifacts; <r> of the verdicts also carry a route-to-sibling annotation; keep-sample: <s> sampled, <o> overturned.
```

Route-to-sibling is an ANNOTATION on a verdict, never a fifth verdict class: the verdict stands (usually a keep) but its rationale routes material to a sibling (doc-to-doc duplication to `/docs-hygiene:extract-ssot`, line-level noise to `/docs-hygiene:audit-noise`). Record the route in the rationale; `<r>` counts the documents carrying one, so routed work shows in the aggregate instead of vanishing into the keep bucket. `<s>` counts sampled keep verdicts and `<o>` those a converged sample overturned into a provisional `delete`/`convert-to-pointer`, so a false-keep rate is readable from the aggregate. In-tree follow-up status for the 2026-08-15 repo-wide routed set: [`../../context/derivability-route-followups.md`](../../context/derivability-route-followups.md).

Corpus-scale sweeps (more documents than one reply can carry): the per-document blocks live in the batch ledger files; the reply carries the aggregate line, the confirmed-actionable (`delete` / `convert-to-pointer`) subset, the provisional (cap-deferred) verdicts listed separately, never in the actionable subset, and the ledger file locations.

After the ledger, OFFER to route actionable verdicts (delete / convert-to-pointer) to the consumer's work-item tracker, one item per document, and stop. Never auto-file, never auto-edit.

## Hard rules

- **Read-only with respect to the repository.** No `Edit` or `Write` inside the repo, no `Bash` that mutates it; session-scratchpad ledgers and artifacts are the one sanctioned write surface. The author applies every deletion and rewrite. Deletion is the highest-stakes doc edit; the classifier only recommends.
- **Never derivability alone.** A `delete` verdict requires all of: derivable, low re-derivation cost, no owned facts. Any owned non-derivable fact forces `keep-owns-facts`.
- **Cache verdicts carry a drift-control condition or they demote.** No regeneration path and no recheck trigger → not a cache, demote to pointer/delete.
- **Load-bearing or contested deletions are spot-tested by a fresh, non-fork subagent**, never confirmed from this (contaminated) context, never by the Agent tool's `fork` subagent type, which inherits the parent conversation. A launch-loaded audited file is spot-tested only by `Explore` or `Plan` (this skill's choice; see Sources for which agents load those files). A verdict whose spot-test is deferred (e.g. past a sweep's cap) stays provisional and is never routed as actionable.
- **Audience named in every verdict.** Agent-facing and human-facing docs clear different deletion bars.
- **The empty-target escalation is offer-only.** A repo-wide sweep from the no-op path runs only after explicit user confirmation; decline or silence ends as the no-op.
- **Owned facts are salvaged before anything is deleted.** When a doc is mostly derivable but owns a fact, the verdict is keep + route-the-remainder, never delete-and-lose.
- **Output deterministic.** Filenames sort lexically; no timestamps in output.

## Gotchas

- **Derivable is not a verdict.** Check re-derivation cost, drift risk, and fact ownership first. The most common misfire is deleting a mostly-derivable doc that owned one buried rationale line.
- **The self-grade trap.** After reading a doc it always *looks* re-derivable; never confirm a load-bearing deletion from this context.
- **Launch-loaded files reach most subagents already.** A general-purpose subagent, or a custom one whose definition does not set `omitClaudeMd`, starts with `CLAUDE.md`, `AGENTS.md`, and project rules loaded, so its spot-test of those files is graded by an agent that has read them. Use `Explore` or `Plan`.
- **Cache without drift control is not a cache.** It is an unmaintained copy; demote it.
- **Code-derivable ≠ duplicates-another-doc.** A doc restating *another doc* is `/docs-hygiene:extract-ssot`, not a `delete` here.
- **Audience changes the verdict.** The same restatement can be dead weight on an agent surface and worth keeping for humans; do not carry one surface's verdict to the other.

## What this skill is NOT

- **Not `/docs-hygiene:audit-noise`.** That classifies line-level noise *inside* a document worth keeping; this decides whether the whole document is. A `keep-owns-facts` doc can still have noise lines for audit-noise to trim.
- **Not `/docs-hygiene:extract-ssot`.** That deduplicates a unit repeated across files into one home, at any multiplicity (a new home is created only at 3+). Derivability is re-derivation from CODE/config/structure, not from another markdown file: a doc that duplicates *another doc* is extract-ssot's; a doc that restates *the code* is this skill's.
- **Not `/docs-hygiene:compress`.** That trims prose within a doc that stays; this deletes or repoints whole docs.
- **Not a doc-drift / staleness detector.** Those ask "does this doc still match the code?" This asks "should this doc exist even when it is perfectly accurate?": a currently-correct doc can still be dead weight because it is trivially re-derivable and carries drift risk.
- **Not a doc generator or an Edit operation.** It recommends; the author acts.

## Sources

- [Diátaxis](https://diataxis.fr), the four documentation modes; the fact-ownership factor leans on its separation of derivable reference material from explanation, which owns the non-derivable *why*.
- Which subagents skip launch-loaded files. Claim: `Explore` and `Plan` skip the `CLAUDE.md` hierarchy (including project rules and `AGENTS.md` loaded as project instructions) and the git status snapshot; every other built-in and custom subagent loads them, except a custom subagent whose definition sets `omitClaudeMd`, which skips the user, project, and local files but still loads managed policy files, unless the definition itself comes from managed settings. Basis: [Create custom subagents](https://code.claude.com/docs/en/sub-agents.md), "Built-in subagents", "Frontmatter reference" and "What loads at startup" (fetched raw: "Explore and Plan start without your CLAUDE.md files and the git status snapshot"). As of 2026-11-01. Recheck trigger: the Recheck triggers table below.

## Recheck triggers

| Condition | Action |
|---|---|
| The rubric is proven over real audits | Route it upstream to `melodic-software/standards` as shared doc-value policy (deferred; ledger E-a) |
| Demand surfaces for applying verdicts, not just classifying | Revisit the deferred remediation/apply action (deferred; ledger E-b) |
| The sub-agents page's "What loads at startup" lists a different set of subagents that skip `CLAUDE.md` or project rules | Re-read the page by the [fetch-route rungs](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/upstream-drift/README.md#the-rungs) (rung 1, fresh bytes), re-derive the `Explore`/`Plan` requirement in the spot-test protocol and the Sources record, refresh the as-of date |
| A native "regenerate this doc from source" mechanism ships | Strengthen the `keep-as-derivation-cache` drift-control test to prefer regeneration over a recorded recheck trigger |
