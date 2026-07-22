# Derivability rubric — scoring the four factors

Reference for `/docs-hygiene:audit-derivability`. The SKILL.md carries the
verdict contract; this file is the scoring detail, the fact-ownership mapping,
and worked examples. Load it when a verdict is close or contested.

## The core question, precisely

> Could a fresh agent — one that has NOT seen this document — reconstruct its
> load-bearing conclusions by natively exploring the repository (reading code,
> config, metadata, directory structure, build files, tests), without external
> knowledge the repository does not contain?

"Derivable" is about re-derivation from **the repository's own primary
sources**, not from another prose document. A document that only restates
another *document* is duplication — the sibling `/docs-hygiene:extract-ssot`
owns that axis. A document that only restates the *code/config/structure* is
what this skill audits.

## Factor 1 — Derivable?

Classify each load-bearing claim in the document by where its truth actually
lives:

| Claim's truth lives in… | Derivable? | Example |
|---|---|---|
| Code, config, schema, build files, tests, directory layout | Yes | "The service listens on port 8080" (a config value) |
| Metadata the tooling exposes (git history, manifests, lockfiles) | Yes, with effort | "This module depends on X" (a manifest) |
| Another tracked markdown document | No — this is duplication, not derivability | route to `/docs-hygiene:extract-ssot` |
| Nowhere else — the document is the only record | No — owned fact | "We chose X over Y because Acme's rate limit…" |

A document is *fully* derivable only when every load-bearing claim sits in the
top two rows. One claim in the bottom "owned fact" row flips the whole document
to `keep-owns-facts` (Factor 4 is the trump card).

## Factor 2 — Re-derivation cost

If the document were deleted, what does the next reader pay to rebuild its
conclusions?

| Cost | Shape | Verdict pull |
|---|---|---|
| Cheap | A single grep, one file read, an obvious `--help` | `delete` — the doc saves nothing worth its tax |
| Moderate | A few files, some tracing, but a competent reader gets there | `convert-to-pointer` — a pointer to the entry point beats a copy |
| Expensive | Synthesizing many files, non-obvious relationships, a wide sweep | `keep-as-derivation-cache` — but only with drift control (Factor 3) |

Re-derivation cost is what separates "delete" from "cache". Derivable-and-cheap
is dead weight; derivable-but-expensive is a cache *candidate* — it still has to
clear the drift-control gate before it earns a keep.

## Factor 3 — Drift risk

Derivable content restates a source. Every restatement can fall out of sync with
that source, silently, the moment the source changes. Drift risk is
(how fast the source moves) x (how silently the doc rots when it does).

- **High drift**: the doc mirrors code/config that changes often and nothing
  fails when the doc goes stale. A copy like this is a liability — it will lie
  to a reader with confidence. Push toward `delete` or `convert-to-pointer`.
- **Low drift**: the source is stable (a settled architecture, a rarely-touched
  contract). A cache is safer here.

**Drift control is the gate on the cache verdict.** A `keep-as-derivation-cache`
verdict is legitimate only when the cache cannot silently rot — i.e. there is:

- a **regeneration path**: the doc is (or can be) generated from its source by a
  command, so refreshing it is mechanical and diffable; or
- a **recorded recheck trigger**: an explicit condition ("when the OpenAPI spec
  changes, regenerate this") that a future maintainer or a `recheck-against-upstream`
  pass can act on.

With neither, a "cache" is just an unmaintained copy waiting to drift — the
exact failure the point-don't-copy discipline exists to prevent. **Demote it**
to `convert-to-pointer` (point at the live source) or `delete`.

## Factor 4 — Fact ownership (the trump card)

Some content is not derivable from the repository at any cost because the
repository does not contain it. A document that owns such a fact earns its
existence outright — verdict `keep-owns-facts` — regardless of how derivable the
rest of it is. The non-derivable fact classes:

| Class | Why exploration can't recover it | Example |
|---|---|---|
| **Rationale / the "why"** | Code shows *what*, never *why this and not the alternative* | "Retry count is 3, not 5, because a retry storm once tripped a rate limit" |
| **Decisions** | A chosen option erases the record of the options rejected and the reason | "We evaluated gRPC and REST; picked REST for browser reach" |
| **Constraints** | External limits, contracts, compliance, SLAs that no code line states | "Acme Pay rate-limits us at 10 req/s per account" |
| **External facts** | Truth that lives outside the repo entirely | vendor behavior, org policy, historical incidents |
| **Cross-cutting invariants** | A relationship no *single* file states, that only emerges across many | "This count must stay below the breaker threshold or the breaker is dead code" |

This maps onto **Diátaxis** (https://diataxis.fr): its **explanation** mode
exists precisely to hold the understanding — the *why*, the background, the
design context — that the other modes and the code itself do not carry.
**Reference** material, by contrast, describes the machinery and is the most
derivable mode (in the limit, generatable from the code it describes).
**Tutorials** and **how-to guides** are human-facing and carry authored value in
their curation and sequencing (Factor 2 re-derivation cost for a human is high),
even when each individual step is technically derivable.

When a document owns a fact but is *mostly* derivable, the verdict is still
`keep-owns-facts` — then **salvage the owned fact and route the derivable
remainder** to the trimming siblings (`/docs-hygiene:audit-noise`,
`/docs-hygiene:extract-ssot`). Never delete-and-lose.

## Audience: agent-facing vs human-facing

Factor 2 (re-derivation cost) is paid by the reader, and the two reader classes
pay very differently — so the same content can score differently by audience.

- **Agent-facing** (`CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, skill bodies,
  agent prompts): an agent re-derives by exploring on demand — retrieval is
  cheap and just-in-time, which is the core lesson of agent context-engineering:
  a finite context budget means low-signal, derivable context is a standing tax
  paid on every session that loads it, not a convenience. The deletion bar is
  low; "an agent could just look" is usually decisive.
- **Human-facing** (onboarding, READMEs, tutorials, architecture explainers): a
  human cannot grep the whole codebase in a second; a good explainer or curated
  path saves every future reader real cost. The deletion bar is higher; weigh
  human derivation cost, not agent cost.

A document serving both audiences is classified for each; take the more
conservative (keep-leaning) verdict, and name the audience in the output.

## The empirical spot-test — protocol

For a load-bearing or contested `delete` / `convert-to-pointer`, do not trust
this context's judgment of derivability: having read the document, it knows the
answers and will overestimate how re-derivable they were. That is a self-grade,
and the fix is a fresh set of eyes — a context that never saw the document.

1. Spawn a **fresh-context, non-fork subagent** (e.g. an `Explore` agent). It
   must NOT be shown the document and must NOT be spawned as the Agent tool's
   `fork` subagent type — that fork inherits this context's contaminated
   history. (A skill's own `context: fork` frontmatter is the opposite: it
   starts blank, with no access to the conversation.)
2. Give it the questions the document answers — or ask it to produce the
   document's key conclusions — using **only** native repository exploration.
3. Compare its output to the document:
   - **Converged** (it reproduced the conclusions from the code): derivable —
     the `delete`/`pointer` verdict holds.
   - **Diverged or failed** (it could not get there, or got it wrong): the
     document owns something exploration could not recover — **keep it**, and
     record what it owns.

Gate the spot-test by stakes: skip it for an obviously trivial derivable file
(a verbatim config restatement, an auto-generated index); run it whenever being
wrong about the deletion would cost a reader something real.

## Worked examples

| Document | Factors | Verdict |
|---|---|---|
| A `.claude/rules/` file listing the public methods of a well-named class | Derivable (code); cheap; high drift (methods change); owns nothing | `delete` (agent-facing, full axe) |
| A hand-kept table restating a large generated OpenAPI spec, no regen script, no recheck trigger | Derivable; expensive; high drift; owns nothing; **no drift control** | `keep-as-derivation-cache` **demotes** → `convert-to-pointer` (point at the spec) |
| A doc explaining *why* the retry count is 3 (rate limit, past incident, breaker invariant) | Bare value derivable, but owns rationale + constraint + cross-cutting invariant | `keep-owns-facts` |
| An onboarding tutorial whose individual steps are each derivable but whose curated ordering teaches a newcomer the system | Steps derivable; human re-derivation cost high (curation is the value) | keep / `convert-to-pointer` (human-facing, higher bar) |
| A doc that repeats, near-verbatim, a section already living in another markdown doc | Not code-derivable — doc-to-doc duplication | route to `/docs-hygiene:extract-ssot`, not a `delete` here |
