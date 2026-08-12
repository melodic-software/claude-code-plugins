---
description: "Audit locally-owned instruction components — skill bodies, agent definitions, hook instruction text, output styles, CLAUDE.md, rules — for MISSING posture guidance the official prompting guide says their purpose needs: delegation criteria/caps in orchestration components, minimal-scope and anti-test-gaming guardrails in code-changing components, investigate-before-answering grounding, progress-claim grounding on long runs, autonomy vs checkpoint posture, destructive-action confirmation, context-budget reassurance, multi-window state guidance, parallel-tool-call steering. The additive complement to audit-instructions (which finds text that is present and wrong; this finds text that is absent and needed). Report-only: emits proposed additions sourced from a live fetch of the guide, gated to the human, never auto-applied. Use when: 'posture audit', 'audit prompting postures', 'is my skill missing guardrails', 'missing delegation criteria', 'should this component confirm destructive actions', 'align my components with the prompting guide', after authoring a new skill or agent, or as the additive lane of a prompting-guide alignment pass. Not for removing or rewriting existing instructions (audit-instructions), structural skill lint (skill-quality:check), or brevity (docs-hygiene:compress)."
argument-hint: "[scope] — scope: skills|agents|hooks|output-styles|claude-md|rules|all (default: all)"
disallowed-tools: Edit, NotebookEdit
user-invocable: true
disable-model-invocation: false
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

**Instruction-held, not tool-enforced — never tell an operator this skill *cannot* edit their files.**
`disallowed-tools: Edit, NotebookEdit` narrows the surface, nothing more: `Write` stays for Phase D's
persist and Phase B has already read every audited component, so it can overwrite one; `Bash` stays
for the state key, and a shell mutates files too. That closes the likeliest accidental path, not the
capability — and a skill auditing assurance must not overstate its own.
(<https://code.claude.com/docs/en/skills>, fetched 2026-08-12; the restriction clears on the human's
next message, so whoever accepts a proposal can apply it.)

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
It deliberately carries no copied sample text, so no proposal is written before the page it cites is
in hand. It names two kinds of page; they are fetched at different times and fail differently.

**The best-practices page: fetched here, every run, before any judging.** It is this skill's one
non-negotiable input — every posture points at it, so losing it degrades all ten at once. If it
cannot be fetched, **ABORT the run**, naming the URL and the failure; continuing would emit ten
`wording-unverified` postures, a report shaped like an audit that audited nothing. Same posture the
sibling takes on its own single input (`audit-instructions/SKILL.md`, "Fail loud on ambiguity").

**Model-specific subpages: fetched lazily, in Phase C, per applicable row** — when a posture whose
predicate actually matched points at one, not once per catalog row, since a row names its subpage
statically whether or not anything in scope matches. A failed subpage fetch degrades only the
postures citing it: mark those `wording-unverified`, carry the pointer instead of wording, never
invent text. One page is fatal; the rest are local, and "before judging anything" is not a
requirement to hold every page at once.

## Phase B — Inventory and classify

Parse `$ARGUMENTS` for an optional scope filter (`skills`, `agents`, `hooks`, `output-styles`,
`claude-md`, `rules`, or `all`, the default). It narrows which surfaces may produce findings, never
which pages Phase A fetches.

Enumerate locally-owned instruction components in scope. **This skill names its own surface set**;
what it shares with `audit-instructions` Phase A is the *resolution* procedure, not the list — resolve
`${CLAUDE_CONFIG_DIR:-~/.claude}` and project `.claude/`, and apply the same liveness and
upstream-ownership exclusions. The set, one entry per scope token above: skill bodies (and the
context/reference files a skill instructs the model to read), agent definition markdown, hook
instruction text of both kinds, output-style markdown, CLAUDE.md / CLAUDE.local.md, `.claude/rules/`.
Inheriting it by reference from a sibling that versions independently is how `output-styles` came to
be inventoried here and unnameable by this skill's own filter. **The inventory bounds what may produce
a finding, not what counts as evidence** — Phase C's mechanical-gate rule reads outside it to establish
PRESENCE, which can only turn a MISSING into a PRESENT, never add a finding on an excluded surface.

For each component, classify its purpose from its own description and body — the classification
vocabulary and its tie to each posture's predicate live in the catalog. A component can match several
purposes or none; none is the common case, and unclassified components go in the coverage line rather
than being force-fitted.

## Phase C — Judge postures

For each component × applicable posture: does the component (or a file it instructs the model to
read) already carry the posture, in any wording? Judge substance, not phrasing — a numeric
concurrency cap satisfies the delegation-criteria posture without quoting the guide. Only a genuine
absence on a component whose purpose clearly needs it becomes a finding. Three standing fences:

- **Do not manufacture.** The predicate must match the component's actual purpose, not a
  conceivable use. When in doubt, NOT-APPLICABLE.
- **Mechanical gates are presence evidence and do not live in the inventory.** P7 — and only P7 —
  blesses a deny-by-default hook **or script** gate "without any prose", while Phase B inventories
  instruction *text*, so those gates sit outside that set by construction. Before judging a
  `destructive-capable` component MISSING on P7, look in all three: settings scopes Phase B resolved
  (`permissions.deny` / `ask`), hook config registering a PreToolUse matcher over the action, and
  **the script the component delegates the action to** — follow the invocation and read it, since a
  component whose destructive step runs through a script that performs the approval check is gated.
  Any one of the three is PRESENT, cited by file and rule, or by script and line.
- **Repo conventions win on wording.** The proposal adapts the guide's substance to the
  component's own voice and the repo's terseness conventions; it never pastes a guide block
  verbatim into a proposal without trimming to what the component needs.

## Phase D — Verify and report

Dispatch one fresh-context, non-fork verifier per surface batch, prompted to refute each proposed
addition: "argue this component's purpose does not need this posture, or that it already carries
it." A refuted finding is **demoted to `info` and kept, never dropped** — it stays a row carrying its
refutation, because deleting it erases the evidence that Phase D ran and disagreed.

### When dispatch is unavailable

Phase D **requires** fresh-context, non-fork verifier dispatch. When the Agent tool is blocked,
unavailable, or the session cannot spawn subagents:

1. **Disclose in the report header** that Phase D did not run and why.
2. **Mark unverified proposals.** Every proposed addition that did not receive an independent
   verifier MUST carry an `(unverified)` marker and MUST NOT be presented as a confident finding.
3. **Add a verifier attestation line** to the report tail — components verified, verified inline,
   or skipped — alongside the existing coverage and Sources lines.

Persist the report to `${CLAUDE_PLUGIN_DATA}/audit-prompting-postures/<state-key>/last-audit.md`.

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
when the report should say which rung produced the key. **The key stops overwrites, not reaping** —
"By default, uninstalling from the last remaining scope also deletes the plugin's
`${CLAUDE_PLUGIN_DATA}` directory. Use `--keep-data` to preserve it."
(<https://code.claude.com/docs/en/plugins-reference>, `plugin uninstall`, fetched 2026-08-12), so when
a report must outlive the plugin the closing line says to copy it out of the data directory.

What that suite pins, so this file does not have to restate the derivation to be trusted: an https
remote and its scp-style ssh equivalent normalize to the same `github.com/<owner>/<repo>`; a repo whose
only remote is `upstream` keys by that remote rather than dropping to the local rung; a repo with no
remote gives `local/<12>`; a non-repo root gives `nonrepo/<12>`; and relative (`../central.git`),
absolute-local, and Windows-path remotes all key by hash, with no `..` and no backslash surviving into
a path segment — the identity becomes directory components, so that is a security property, not a
cosmetic one. Two worktrees of one repository differ in the discriminator, which is what it exists for.

Run it and use the result. Do **not** express the path as a condition over `${CLAUDE_PROJECT_DIR}`
"when set": that placeholder is substituted inline before this file reaches you, so the literal token
is never visible and the condition is not yours to evaluate. Derive the key from a command you run.

**Open the report with a three-line header**, so a file that does survive is self-describing rather
than merely un-overwritten:

```
Resolved root: <absolute path audited>
Scope filter:  <the scope argument this run used, or "all">
Run (UTC):     <ISO-8601 timestamp>
```

Then summarize in chat:

| # | Posture | Component | Verdict | Proposed addition or pointer |
|---|---------|-----------|---------|------------------------------|

Verdicts — the closed set, four tokens: `MISSING` (finding, with proposed addition as a fenced diff),
`PRESENT` (where it is), `NOT-APPLICABLE` (with the failed predicate), `info` (a Phase D verifier
refuted it — always kept as a row, never dropped, never a proposal to apply). Two markers are
orthogonal and ride **alongside** a verdict, never in place of one: `wording-unverified` (a subpage
fetch failed in Phase C — the fifth column then carries the guide POINTER, which is what that column
is named for, and a pointer is never dressed up as guide wording) and `(unverified)` (Phase D could
not verify this proposal — see "When dispatch is unavailable"). End with a coverage line — components
inventoried, classified, unclassified — and a Sources line citing the pages fetched this run with
dates. When Phase D ran, end with a verifier attestation line — surface batches verified, verified
inline, or skipped.

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

- Never edits a component and never auto-applies a proposal — held by instruction, since
  `disallowed-tools` narrows the surface but `Write` and `Bash` remain and both can mutate a file.
- Never copies guide text into its own catalog — wording comes from the run's live fetch.
- Does not judge existing text (that is `audit-instructions`), lint structure
  (`skill-quality:check`), or compress prose (`docs-hygiene:compress`).
