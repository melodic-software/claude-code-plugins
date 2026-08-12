---
description: "Audit locally-owned instruction components — skill bodies, agent definitions, hook instruction text, CLAUDE.md, rules — for MISSING posture guidance the official prompting guide says their purpose needs: delegation criteria/caps in orchestration components, minimal-scope and anti-test-gaming guardrails in code-changing components, investigate-before-answering grounding, progress-claim grounding on long runs, autonomy vs checkpoint posture, destructive-action confirmation, context-budget reassurance, multi-window state guidance, parallel-tool-call steering. The additive complement to audit-instructions (which finds text that is present and wrong; this finds text that is absent and needed). Report-only: emits proposed additions sourced from a live fetch of the guide, gated to the human, never auto-applied. Use when: 'posture audit', 'audit prompting postures', 'is my skill missing guardrails', 'missing delegation criteria', 'should this component confirm destructive actions', 'align my components with the prompting guide', after authoring a new skill or agent, or as the additive lane of a prompting-guide alignment pass. Not for removing or rewriting existing instructions (audit-instructions), structural skill lint (skill-quality:check), or brevity (docs-hygiene:compress)."
argument-hint: "[scope] — scope: skills|agents|hooks|claude-md|rules|all (default: all; output-styles are out of scope — use audit-instructions)"
user-invocable: true
disable-model-invocation: false
disallowed-tools: Edit, NotebookEdit
metadata:
  workflow-stage: anytime
  summary: Find posture guidance the prompting guide says a component needs but does not carry
---

## Purpose

The official prompting guide prescribes posture guidance that agentic components should CARRY —
delegation criteria, scope guardrails, grounding instructions, autonomy postures, confirmation
gates. `audit-instructions` detects instruction text that is present and wrong; nothing detects
text that is absent and needed. This skill is that additive lane: it classifies each component by
purpose, checks the postures that purpose calls for, and proposes additions with wording taken
from a live fetch of the guide — never from this file.

## Read-only contract

Report-only. No `--fix`: every proposed addition is applied by the human (or explicitly delegated
afterward). A clean audit is a valid outcome, and with well-authored components it is the expected
one — the default verdict per posture is NOT-APPLICABLE, not MISSING.

## Scope boundary (route out)

- Text that is present and wrong — over-prescription, stale claims, emphasis language, retired
  parameters — is `audit-instructions`. When one sweep wants both lanes, run both skills; a
  coordinated pass (`audit-pass`, when installed) composes them.
- Structural skill lint is `skill-quality:check`; token brevity is `docs-hygiene:compress`.
- Upstream-owned surfaces (installed plugin cache, managed materializations) produce routing
  recommendations to the owning repository, never in-place proposals — same exclusion
  `audit-instructions` applies.

## Phase A — Fetch the guide

The posture catalog in [reference/postures.md](reference/postures.md) carries, per posture, an
applicability predicate and a POINTER to the guide section that states the recommended wording.
It deliberately carries no copied sample text. Fetch the best-practices page before Phase C.
Fetch a model-specific subpage only when Phase C finds an applicable posture row that names it —
do not prefetch every subpage named anywhere in the catalog up front. Hold the current wording
from each page you fetch. If the best-practices page is unreachable, **abort the run** with an
error naming the URL — do not emit posture findings from memory. If a named subpage fetch fails,
mark that posture's findings `wording-unverified` and cite the pointer rather than inventing text.

## Phase B — Inventory and classify

Parse `$ARGUMENTS` for an optional scope filter (`skills`, `agents`, `hooks`, `claude-md`,
`rules`, or `all`, the default). The filter narrows which surfaces may produce findings, never
which pages Phase A fetches. **`output-styles` is intentionally out of scope** — that surface
belongs to `audit-instructions`; this skill does not inherit it.

Enumerate locally-owned instruction components in scope (same surface set and liveness rules as
`audit-instructions` Phase A — resolve `${CLAUDE_CONFIG_DIR:-~/.claude}`, project `.claude/`,
CLAUDE.md files, hook instruction text of both kinds). For **P7 (destructive-action confirmation)**,
also inspect hook scripts registered in `hooks.json` and `permissions.deny` / `permissions.ask`
entries in settings files — a deny-by-default hook or script gate counts as presence even when
no prose says so. For each component, classify its purpose
from its own description and body — the classification vocabulary and its tie to each posture's
predicate live in the catalog. A component can match several purposes or none; none is the common
case, and unclassified components are reported in the coverage line, not force-fitted.

## Phase C — Judge postures

For each component × applicable posture: does the component (or a file it instructs the model to
read) already carry the posture, in any wording? Judge substance, not phrasing — a numeric
concurrency cap satisfies the delegation-criteria posture without quoting the guide. Only a
genuine absence on a component whose purpose clearly needs it becomes a finding. Two standing
fences:

- **Do not manufacture.** The predicate must match the component's actual purpose, not a
  conceivable use. When in doubt, NOT-APPLICABLE.
- **Repo conventions win on wording.** The proposal adapts the guide's substance to the
  component's own voice and the repo's terseness conventions; it never pastes a guide block
  verbatim into a proposal without trimming to what the component needs.

## Phase D — Verify and report

Dispatch one fresh-context, non-fork verifier per surface batch, prompted to refute each proposed
addition: "argue this component's purpose does not need this posture, or that it already carries
it." Findings a verifier refutes are dropped or demoted to `info`.

### When dispatch is unavailable

Phase D **requires** fresh-context, non-fork verifier dispatch. When the Agent tool is blocked,
unavailable, or the session cannot spawn subagents:

1. **Disclose in the report header** that Phase D did not run and why.
2. **Mark unverified proposals.** Every proposed addition that did not receive an independent
   verifier MUST carry an `(unverified)` marker and MUST NOT be presented as a confident finding.
3. **Add a verifier attestation line** to the report tail — components verified, verified inline,
   or skipped — alongside the existing coverage and Sources lines.

Persist the report to
`${CLAUDE_PLUGIN_DATA}/audit-prompting-postures/<state-key>/last-audit.md`.

**Derive `<state-key>` by running this:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"
```

`${CLAUDE_PLUGIN_DATA}` is machine-global, not per-project, so a fixed `last-audit.md` is silently
overwritten by the next run from any other root — this skill's only durable deliverable, destroyed by
ordinary use of it. The scheme is `audit-pass`'s, reused rather than reinvented:
`<repo-identity>/<worktree-discriminator>`, per
[audit-pass's run-state reference](../audit-pass/reference/run-state-and-resumability.md) §3, and it
lives in one executable rather than being restated per skill —
[`lib/state-key.sh`](../../lib/state-key.sh), with `lib/state-key.test.sh` beside it. Pass `--explain`
when the report should say which rung produced the key.

What that suite pins, so this file does not have to restate the derivation to be trusted: an https
remote and its scp-style ssh equivalent normalize to the same `github.com/<owner>/<repo>`; a repo whose
only remote is `upstream` keys by that remote rather than dropping to the local rung; a repo with no
remote gives `local/<12>`; a non-repo root gives `nonrepo/<12>`; and relative (`../central.git`),
absolute-local, and Windows-path remotes all key by hash, with no `..` and no backslash surviving into
a path segment — the identity becomes directory components, so that is a security property, not a
cosmetic one. Two worktrees of one repository differ in the discriminator, which is what it exists for.

Run it and use the result. Do **not** express the path as a condition over `${CLAUDE_PROJECT_DIR}`
"when set": that placeholder is substituted inline before this file reaches you, so the literal token
is never visible and the condition is not yours to evaluate. Derive the key from a command you
actually run.

**Open the report with a three-line header**, so a file that does survive is self-describing rather
than merely un-overwritten:

```
Resolved root: <absolute path audited>
Scope filter:  <the scope argument this run used, or "all">
Run (UTC):     <ISO-8601 timestamp>
```

Then summarize in chat:

| # | Posture | Component | Verdict | Proposed addition |
|---|---------|-----------|---------|-------------------|

Verdicts: `MISSING` (finding, with proposed addition as a fenced diff), `PRESENT` (where it is),
`NOT-APPLICABLE` (with the failed predicate), `wording-unverified` (guide fetch failed for this
posture — cite the pointer, do not invent text), and `info` (verifier-demoted or informational,
not a finding). The Proposed addition column may carry a URL when the verdict is
`wording-unverified`. End with a coverage line — components inventoried,
classified, unclassified — and a Sources line citing the pages fetched this run with dates. When
Phase D ran, end with a verifier attestation line — surface batches verified, verified inline, or
skipped.

## Gotchas

- **Presence can live one file away.** A SKILL.md that routes to a context file the model must
  read counts as carrying whatever that file carries — follow the component's own read
  instructions before judging absence.
- **Human-gated designs are not missing autonomy postures.** A report-only skill that ends at a
  human gate needs no autonomous-pipeline branch; the autonomy posture applies to components that
  claim unattended operation.
- **Model-conditional postures stay conditional.** Where the guide ties a posture to specific
  models, the proposal must be model-neutral or carry the same condition — components here run on
  any consumer model.

## What this skill does NOT do

- Never edits a component and never auto-applies a proposal.
- Never copies guide text into its own catalog — wording comes from the run's live fetch.
- Does not judge existing text (that is `audit-instructions`), lint structure
  (`skill-quality:check`), or compress prose (`docs-hygiene:compress`).
