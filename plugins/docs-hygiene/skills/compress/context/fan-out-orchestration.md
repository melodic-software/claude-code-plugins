# Compress fan-out orchestration

Read this when batch-compressing N markdown files via parallel subagents. Codifies the multi-phase split that keeps the mandatory semantic-diff in a SEPARATE fresh-context auditor. Before Claude Code v2.1.172 a subagent could not spawn the verifier at all (no nested Agent tool); as of v2.1.172 a foreground subagent can, but nested spawning is version-dependent and a fresh-context verifier beats self-critique regardless — so the auditor phase stays a main-session dispatch.

**Why this exists:** `/compress` "Hard rules" mandate semantic-diff dispatch. A subagent that invokes `/compress` must NOT run that dispatch as a self-audit in its own context — self-audit by the same model that produced the edits drifts toward EXPANSION ("preserve clarity" re-adds words just removed). Empirically observed: 4/4 reverse-direction edits in a compression wave (see ## History). Fix: move the semantic-diff into a separate fresh-context subagent dispatched by the main session.

## Architecture (three phases per wave)

### Phase A — compressor subagents (parallel, 3-5 per wave)

Each subagent compresses exactly ONE file via the Edit tool. **NO `/compress` slash invocation, NO self-audit, NO re-review.** Returns a diff stat. Latitude follows this skill's flavor-vs-content taxonomy (`context/flavor-vs-content-matrix.md`) — full mechanical drops plus prose-quality moves (passive → active, nominalization collapse).

Canonical Phase A prompt template (compose verbatim, substitute `<ABSOLUTE-PATH>`):

```text
Compress exactly ONE file: <ABSOLUTE-PATH>

LATITUDE:
- Mechanical drops: articles (the/a/an) before clear nouns, filler (just/really/basically/actually/simply), hedging (perhaps/somewhat/might in factually-direct statements), pleasantries, verbose verb phrases (in order to → to, due to the fact that → because, make use of → use)
- Prose playbook: passive → active voice, nominalization collapse ("performs analysis of" → "analyzes", "is responsible for" → "owns")

HARD RULES:
- NEVER add words. EVER.
- NEVER swap word X for synonym X' unless X' is strictly shorter AND same meaning
- NEVER touch code blocks (fenced ``` or inline `...`), URLs, file paths, identifiers, env vars, slash commands, hook names
- NEVER touch directive force ("must" vs "should" vs "may")
- NEVER touch qualifiers narrowing scope (ONLY, NEVER, every, all, only, exact)
- NEVER touch thresholds, version pins, SHAs (3+, 5+, ≥30s, 0.11.0)
- NEVER touch examples, counter-examples, "X not Y" pairs
- NEVER touch error messages, quoted text, citations
- NEVER self-audit. NEVER re-read your own edits. NEVER "preserve clarity".
- Touch ONLY <ABSOLUTE-PATH>. FORBIDDEN: any other file, any git operation, any other repo path.

DELIVERABLE: apply Edit ops; return exactly one line:
<basename>: edited (changes=N, bytes_saved=B)

If nothing safely droppable after one read-through: <basename>: no-op (reason)
```

### Phase B — auditor subagents (parallel, one per Phase-A modified file)

Main session dispatches via the Agent tool. Each subagent applies `/compress`'s semantic-diff prompt template against ONE file's diff. The main session has the Agent tool; this dispatch succeeds.

Main session preparation per subagent:

- ORIGINAL content via `git show HEAD:<file>` (free, no disk overhead; requires the user pre-staged the baseline)
- CONDENSED content via the current file body
- Prompt body: the semantic-diff prompt owned by this skill (`context/semantic-diff-prompt.md` — substitutes `{ORIG}` / `{COND}` placeholders into a FINDING-block + TOTAL-summary contract)

Subagent returns FINDING blocks + a TOTAL summary line per the semantic-diff-prompt contract. Forbidden citation tokens (training-recall markers) invalidate the dispatch — revert that file's candidate.

### Phase C — main-session reconciliation

Per FINDING block returned in Phase B:

- `SEMANTIC LOSS` / `AMBIGUITY` / `UNCERTAIN` → main session reverts that specific CONDENSED line back to ORIGINAL (per-finding revert via the Edit tool, not whole-file revert)
- `FALSE POSITIVE` → keep the compression
- Markdownlint each file post-reconcile; non-zero exit → whole-file revert (per-finding revert produced malformed state)
- Update any batch-tracking artifact your workflow maintains — main session only; subagents never write shared state

## Request budget

8 requests per wave (4 compress + 4 audit). For 71 files at 4-per-wave: 18 waves × 8 = 144 requests total. Comparable to the in-skill dispatch path; quality is dramatically better because the auditor cannot self-modify the file.

## Orchestration rules

- **Phase A scope fence** — each compressor subagent's prompt names exactly ONE allowed file; any other file, git operation, or path is forbidden (the template above encodes this)
- **Phase A does NOT invoke `/compress`** as a slash command from subagents — self-audit in the compressor context caused reverse-direction edits (see ## History)
- **Refuse-fast threshold** — 5 consecutive Phase A or Phase B ERROR returns aborts the batch
- **Phase B returns are unverified synthesis** — the main session reverts per finding rather than verifying each by hand; a forbidden citation token invalidates the whole dispatch

## History

- 2026-05-23 — authoring-repo batch compression wave, empirical: 4/4 reverse-direction edits from self-audit (led to this architecture)
