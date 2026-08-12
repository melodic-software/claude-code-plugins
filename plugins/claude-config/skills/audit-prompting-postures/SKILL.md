---
description: "Audit locally-owned instruction components — skill bodies, agent definitions, hook instruction text, CLAUDE.md, rules — for MISSING posture guidance the official prompting guide says their purpose needs: delegation criteria/caps in orchestration components, minimal-scope and anti-test-gaming guardrails in code-changing components, investigate-before-answering grounding, progress-claim grounding on long runs, autonomy vs checkpoint posture, destructive-action confirmation, context-budget reassurance, multi-window state guidance, parallel-tool-call steering. The additive complement to audit-instructions (which finds text that is present and wrong; this finds text that is absent and needed). Report-only: emits proposed additions sourced from a live fetch of the guide, gated to the human, never auto-applied. Use when: 'posture audit', 'audit prompting postures', 'is my skill missing guardrails', 'missing delegation criteria', 'should this component confirm destructive actions', 'align my components with the prompting guide', after authoring a new skill or agent, or as the additive lane of a prompting-guide alignment pass. Not for removing or rewriting existing instructions (audit-instructions), structural skill lint (skill-quality:check), or brevity (docs-hygiene:compress)."
argument-hint: "[scope] — scope: skills|agents|hooks|claude-md|rules|all (default: all)"
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
It deliberately carries no copied sample text. Before judging anything, WebFetch the pages the
catalog names (the best-practices page always; a model-specific subpage only when a posture row
names it) and hold the current wording. If a fetch fails, mark that posture's findings
`wording-unverified` and cite the pointer rather than inventing text.

## Phase B — Inventory and classify

Parse `$ARGUMENTS` for an optional scope filter (`skills`, `agents`, `hooks`, `claude-md`,
`rules`, or `all`, the default). The filter narrows which surfaces may produce findings, never
which pages Phase A fetches.

Enumerate locally-owned instruction components in scope (same surface set and liveness rules as
`audit-instructions` Phase A — resolve `${CLAUDE_CONFIG_DIR:-~/.claude}`, project `.claude/`,
CLAUDE.md files, hook instruction text of both kinds). For each component, classify its purpose
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

Persist the report to
`${CLAUDE_PLUGIN_DATA}/audit-prompting-postures/<state-key>/last-audit.md`.

**Derive `<state-key>` by running the commands below.** `${CLAUDE_PLUGIN_DATA}` is machine-global, not
per-project, so a fixed `last-audit.md` is silently overwritten by the next run from any other root —
this skill's only durable deliverable, destroyed by ordinary use of it. The scheme is `audit-pass`'s,
reused rather than reinvented: `<repo-identity>/<worktree-discriminator>`, per
[audit-pass's run-state reference](../audit-pass/reference/run-state-and-resumability.md) §3.

```bash
# sha256sum is absent on stock macOS; shasum -a 256 is the portable partner.
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }

# "the FIRST configured remote" — not necessarily one named `origin`. A repo whose only
# remote is `upstream` still has a remote, and must not fall through to the local rung.
remote_name=$(git remote 2>/dev/null | head -1)
remote=$(git config --get "remote.${remote_name}.url" 2>/dev/null || true)
# tr -d '\r': Git on Windows can return a CRLF-terminated path.
root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r' || true)

# repo-identity
if [ -n "$remote" ]; then
  identity=$(printf '%s' "$remote" \
    | sed -e 's#^[a-z+]*://##' -e 's#^[^@/]*@##' -e 's#:#/#' -e 's#\.git$##' \
    | tr '[:upper:]' '[:lower:]')
  # A remote URL is arbitrary text and becomes DIRECTORY COMPONENTS here, so accept it
  # only in the shape the scheme means — segments of [a-z0-9._-] each starting
  # alphanumeric. That rejects `../central` (a relative filesystem remote, which would
  # otherwise write outside this skill's namespace), absolute local paths, and
  # backslashes. Anything rejected still keys deterministically, by hash.
  if ! printf '%s' "$identity" | grep -qE '^[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)*$'; then
    identity="remote/$(printf '%s' "$remote" | sha256 | cut -c1-12)"
  fi
elif [ -n "$root" ]; then
  identity="local/$(printf '%s' "$root" | sha256 | cut -c1-12)"
else
  # Non-repo root. audit-pass's ladder stops at the two git rungs because it refuses
  # non-git targets; this skill is report-only and audits them, so it needs a third.
  identity="nonrepo/$(printf '%s' "$PWD" | sha256 | cut -c1-12)"
fi

# worktree-discriminator — two worktrees of one repo legitimately hold different content
discriminator=$(printf '%s' "${root:-$PWD}" | sha256 | cut -c1-8)

state_key="$identity/$discriminator"
```

Executed, not merely written: an https remote and its scp-style ssh equivalent normalize to the same
`github.com/<owner>/<repo>`; a repo whose only remote is `upstream` keys by that remote rather than
dropping to the local rung; a repo with no remote gives `local/<12>`; a non-repo root gives
`nonrepo/<12>`; and relative (`../central.git`), absolute-local, and Windows-path remotes all key by
hash and stay inside this skill's directory. Two worktrees of one repository differ in the
discriminator, which is the property it exists for.

Run those and use the result. Do **not** express the path as a condition over `${CLAUDE_PROJECT_DIR}`
"when set": that placeholder is substituted inline before this file reaches you, so the literal token
is never visible and the condition is not yours to evaluate. Derive the key from commands you actually
run.

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
`NOT-APPLICABLE` (with the failed predicate). End with a coverage line — components inventoried,
classified, unclassified — and a Sources line citing the pages fetched this run with dates.

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
