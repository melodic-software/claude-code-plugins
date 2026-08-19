# pstack-why — `/discovery:trace-intent`

Lane 1 of the cursor/plugins pstack port. Upstream: `pstack/skills/why/SKILL.md` (MIT), clone
pinned at `60c641e4fad674784b30abcf9f8915dea39df38d`.

## Brief

### TLDR

Add `/discovery:trace-intent` — a fourth `discovery` skill that reconstructs **why a thing was
built the way it was**, from evidence that lives outside the repository, and reports what it could
not find as a first-class result. Reauthored from the upstream `why` skill, not forked.

### Goal

Close the one gap in this plugin's own framing. `explore` answers *what IS*, `research` answers
*what SHOULD BE*; nothing answers *what WAS, and why*. Every investigation skill in the fleet
returns state — what exists, what drifted, what will break. None returns reconstructed intent.

Success is a cited, confidence-calibrated account of the forces that produced a design, in which a
gap is reported rather than papered over with a plausible story.

### Constraints

1. **Evidence substrate is outside the repo.** This is the boundary against `explore`, whose
   dimension 2 already owns git history — *"who changed it, when, why"* — with a dedicated `git`
   mode. `trace-intent` takes tickets, review discussion, long-form design docs, and (where wired)
   incident and telemetry records. It delegates repo-local git archaeology to `/discovery:explore
   git` rather than reimplementing `git log` / `git blame`, and inherits explore's
   do-not-archaeologize-unprompted guard.

2. **The intent-evidence tier is its own axis.** *(Amended after research — the label was wrong and
   one dimension was missing.)* Five tiers — Direct / Supported / Inferred / Speculative /
   Unknown — measuring **inferential distance from an explicit statement of intent**. It is NOT
   research's Tier 0-3 source-authority ladder, and reusing that ladder is a defect:
   `artifact-shape.md:149-157` says pointing a non-external run at the research header "launders
   'I grepped a filename' into the same field a fetched primary source would occupy", which is why
   `explore` has its own `verified: read | grep | inferred`. Two further reasons: `discipline.md:222`
   accepts only HIGH-confidence claims and makes MEDIUM/LOW a Gap, which would outlaw this skill's
   own hedged deliverable; and Tier 3 is a promotable rung, which would soften an absolute exclusion
   into weak-but-admissible. **The tier is the sole output-section router.**

   Two research-driven amendments:

   - **Named "intent-evidence", never "intent-confidence".** The tier answers how far a claim sits
     from someone actually stating intent — not how sure the run is. ICD 203 forbids that
     conflation by directive, and no comparator scheme is on this axis at all: estimative
     probability measures likelihood, GRADE measures certainty in an effect estimate, ICD 203
     confidence measures source quality. The five coined names are kept precisely because none of
     those is a substitute; substituting a borrowed ladder would be the defect this constraint
     already names.
   - **A lightweight source-reliability annotation rides alongside, and does not route.** Every
     comparator — ICD 203, GRADE, Admiralty/NATO AJP-2.1 — separates how *direct* the evidence is
     from how *reliable* the source is, and forbids merging them. Without it, a code comment written
     by the change's author and a four-year-old wiki page both sit on `Direct`. So each citation
     carries a short reliability note (who wrote it, how close to the decision, how stale). It is a
     note, not a second graded ladder: only the tier routes, so the routing mechanism is unchanged.

3. **Code shape is never intent evidence.** It leaves the ladder entirely — recorded as a Gap, never
   as a low rung. "Handles the null case because it checks for null" is mechanics, not motivation.

   **This is a deliberate departure from upstream, not a restatement of it** *(research finding)*.
   Upstream permits *labeled* code-shape inference at the `Inferred` tier in two places — its
   failure-mode entry ("or is labeled as inference") and the `Inferred` tier's own worked example, a
   function name plus a literal `3`. The exclusion is argued **operationally, not epistemically**:
   code shape is the only always-available zero-cost evidence source, so a weak-but-admissible rung
   for it gets filled exactly when the record is thin and the temptation to fill it is highest.
   The departure is recorded in the provenance file (AC10).

   **Version-control BEHAVIOR is not code shape, and is admissible at `Inferred`.** Tornhill:
   "the history of our system provides us with data we cannot derive from a single snapshot of the
   source code." But behavioral signal *locates rather than explains* — with hotspots "we lack the
   original context… there could be multiple reasons why the code is as it is" — so change coupling,
   churn and hotspot data may reach `Inferred` and never `Direct`.

4. **Three live evidence categories, none guaranteed.** Source control, long-form docs, issue
   tracker — each presence-gated, because every `discovery` skill guards its git precompute
   (`2>/dev/null || echo "unknown"`) and `topic-docs/README.md:415` states the no-project-root path
   "is not a rare path". Beyond those three, a documented provider-adapter extension seam. The four
   upstream categories with no representation in this marketplace (team chat, infra observability,
   error tracking, product analytics) are not shipped as permanent constant-gap investigators.

5. **Provider-neutral by review discipline, not by gate.** The tracker and forge token classes in
   `scripts/skill-portability-tokens.txt:137,154` are commented out pending issue #416, so a green
   `check-skill-portability.sh` run is NOT evidence of neutrality. Category names are surface
   classes; vendors appear only as illustrative examples. Upstream's vendor-named playbooks
   (`linear.md`, `notion.md`, `datadog.md`, `sentry.md`, `slack.md`, `databricks.md`) invert to
   category-named files.

6. **The tracker seam is invoked, never imported.** `PLUGIN-PHILOSOPHY.md:22` forbids importing a
   sibling plugin's files; `grep -rln "work-item-tracker.sh" plugins/` returns only `work-items/**`.
   Use a namespaced skill invocation with gate-plus-fallback — precedent
   `code-tidying:batch-simplify/SKILL.md:176`.

7. **One purpose-built agent, not a seven-way fan-out.** `explore` runs six dimensions inside one
   `discovery:explorer`; `research` runs its phases inside one `discovery:researcher` — both behind
   a preload-liveness sentinel and a parent-side acceptance gate
   (`discovery/scripts/check-dispatch-artifact.sh`). Follow that architecture.

8. **Fresh-eyes declaration required.** Confidence-calibrated synthesis is the self-grade class
   `PLUGIN-PHILOSOPHY.md:657` names verbatim ("a synthesis step grading its own lock"). Siblings
   answer it by dispatching a verifier and returning `verification: pending`. Check 21 WARNs
   without a Form-1 declaration in the skill's own files.

9. **The findings artifact is private, not a public lifecycle kind.** Registering a third artifact
   in `docs/PLUGIN-ARTIFACT-PROTOCOL.md` triggers byte-identical copies across five plugins plus a
   protocol version bump, for an artifact with no downstream consumer today. Declare it explicitly
   private so it is not mistaken for sanctioned scratch. Return a bounded summary plus a pointer —
   never full inline synthesis, which inverts the stated purpose of both siblings.

10. **The edit to `discipline:reason-dont-recite` is additive only.** It carries the literal quoted
    trigger `'why is it this way'`. Removing or rephrasing it hard-FAILs `skill-quality` check 3 —
    the trigger-MOVE carve-out iterates same-plugin siblings only (`check-skill.sh:377`), so a
    cross-plugin move reads as a dropped trigger. Append a disambiguating clause; change nothing
    existing. A clause that merely narrows its own trigger surface needs no gate; one that *routes*
    to `trace-intent` is a cross-plugin reference and takes the guarded gate-plus-fallback form.

11. **Do not pre-register the leaf name.** `check-skill-leaf-names.sh:186` FAILs a registered leaf
    carried by fewer than two plugins. `trace-intent` is unique; no registry entry.

### Acceptance criteria

Binary, checkable.

1. `plugins/discovery/skills/trace-intent/SKILL.md` exists, declares no frontmatter `name`, carries
   `metadata.workflow-stage` from the `scripts/cheatsheet-config.mjs` enum and a
   `metadata.summary` of <= 100 codepoints.
2. Its `description` carries single-quoted `Use when:` trigger phrases and a `Skip when:` clause
   naming `/discipline:reason-dont-recite` and `/discovery:explore`.
3. The five intent-evidence tiers appear under that name — never "intent-confidence" — with a stated
   mapping to output sections, and the skill states that code-shape inference is recorded as a Gap
   rather than placed on the ladder, while version-control behavior (change coupling, churn,
   hotspots) is admissible at `Inferred` and never at `Direct`.
3a. Each citation carries a short source-reliability note (author proximity to the decision,
   staleness), stated as a note that does not route — only the tier routes to an output section.
4. A Sources Consulted coverage map is specified, one line per category including those that
   returned nothing, in the form
   `- <category>: <what was searched>. <found | no relevant results | skipped, reason>.`
5. Exactly two skip reasons are permitted, and "probably irrelevant" is explicitly rejected.
6. No vendor name appears as a category identifier; any vendor named is an illustrative example.
7. `plugins/discovery/skills/trace-intent/evals/evals.json` exists, validates against
   `plugins/skill-quality/reference/evals.schema.json`, and covers trigger/routing, happy path,
   one refusal/guardrail, and one anti-pattern.
8. A Form-1 fresh-eyes declaration is present in the skill's own files.
9. `plugins/discipline/skills/reason-dont-recite/SKILL.md` retains every existing single-quoted
   trigger verbatim; the only change is an appended clause.
10. `docs/upstream/cursor-pstack.md` exists in the shape of `docs/upstream/mattpocock-skills.md`,
    and its `trace-intent` row records the code-shape exclusion as a **deliberate departure** —
    naming that upstream permits labeled code-shape inference at `Inferred` and that this port
    forbids it, with the operational reason.
11. Both `discovery` and `discipline` carry manifest version bumps with matching CHANGELOG entries.
12. `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` regenerated, not hand-edited.
13. These pass: `scripts/check-changed-skills.sh origin/main`, `scripts/validate-plugins.sh`,
    `scripts/check-changelog-parity.sh --check-bump origin/main`,
    `scripts/check-skill-leaf-names.sh --check`, `scripts/check-skill-portability.sh origin/main`.

### Captured assumptions

- **A1.** Users will reach this with phrasings like "why was this built this way", "what were they
  thinking", "design rationale", "why did we pick X over Y". Untested against real usage; the evals
  are where it gets checked.
- **A2.** The four unshipped categories are worth an extension seam rather than omission. If nobody
  ever wires an adapter, the seam is dead weight and should be removed at the next audit.
- **A3.** The private-artifact call assumes no near-term consumer. If the `teach` lane or `planning`
  later needs to read it, that decision reopens and pays the five-plugin protocol cost then.

### Known evidence gaps

Recorded rather than papered over, per the user's explicit decision to proceed.

- **The research stage's coverage gate FAILED** — `check-coverage-complete.sh` exit 1, 16 of 21
  ledger rows unmarked (`.work/pstack-why/research-checklist.md`). Cause is environmental, not
  discipline: this session's egress proxy answers 403 to CONNECT for every non-GitHub host, verified
  independently by `curl` and by `WebFetch`. Every non-GitHub primary — Pragmatic Bookshelf,
  cognitect.com, dni.gov, codescene.com — was unreachable after the full escalation ladder.
- **What that does and does not undermine.** The three load-bearing answers (method provenance;
  keep-the-five-tiers; the behavioral-signal boundary) each rest on Tier-0 reads of the upstream
  artifact at the pinned SHA `60c641e4` in the local clone, plus Tier-1 reads of the authors' own
  GitHub-hosted repositories — all of which came back clean. Twelve *secondary* claims are MEDIUM
  and carried as named Gaps G1-G8 in `RESEARCH.md`.
- **Promotion path.** Re-run `/discovery:research` for this topic from an open-egress session and
  mark the outstanding ledger rows. Nothing in the implementation depends on those rows; they would
  strengthen the citations in the provenance file, not change a decision.
- **One dispatch irregularity, disclosed by the worker.** The research dispatch reached a general
  agent rather than arriving through a `skills:` preload, so the preload sentinel did not travel the
  intended path. The worker took the documented fallback — reading the skill body, `discipline.md`,
  `artifact-shape.md` and the agent definition directly that turn before starting — and said so
  rather than echoing a token it had not earned. The artifact gate passed independently (exit 0).

### Out of scope

- A `how` skill. Upstream pairs `why` with `how` for runtime mechanism; we have no equivalent and
  are not building one in this lane.
- Application-telemetry integration of any kind. `claude-ops:observability` reads Claude Code's own
  telemetry and is not a substrate for this.
- Retrofitting the intent-confidence axis onto any existing skill.
- Activating the staged tracker/forge portability token classes (issue #416).

### Deferred questions

- **Q12** — should the four unshipped categories ship as documented adapter *stubs* or as prose
  describing the seam only? Arbiter: `/planning:plan`. Turns on whether a stub is discoverable
  enough to be useful without being dead code.
- **Q13** — `metadata.workflow-stage` value. No stage in the enum cleanly fits historical
  archaeology; `explore`, `research`, and `anytime` are all defensible. Arbiter: `/planning:plan`,
  after reading how the sibling discovery skills are staged.

## Plan

Design gate: `design/design-resolution.md`, Tier B, `outcome: early-exit` — every design thread was
resolved by the interview, the three-validator audit, the exploration, or the research; the one new
contract (the third sidecar header schema) carries a type sketch there.

Standards grounding: no consumer standards index resolved beyond the ambient `CLAUDE.md` (the
repo's `AGENTS.md` is deliberately blanked, commit `6763cf77`). The binding criteria for this task
are `docs/PLUGIN-PHILOSOPHY.md` (naming, two-lane posture, fresh-eyes, instruction economy) and
`docs/MIGRATION-PLAYBOOK.md` (organization, the skill-split rule), both read this session.

### Phase 1: Skeleton that passes every fleet gate [TODO]

The integration slice. Prove the skill resolves, the manifest validates and the generated docs
regenerate **before** investing in prose — a content-first order would discover a metadata or naming
defect only after the expensive writing is done.

| File | Action | Rationale |
|---|---|---|
| `plugins/discovery/skills/trace-intent/SKILL.md` | create | Frontmatter + description + section spine; body stubbed with the required headings |
| `plugins/discovery/skills/trace-intent/evals/evals.json` | create | CI runs `--require-evals` on any new SKILL.md, so this is not deferrable |
| `plugins/discovery/.claude-plugin/plugin.json` | modify | Minor version bump; description/keywords touch |
| `plugins/discovery/CHANGELOG.md` | modify | New `## [x.y.z]` entry, bolded-lead `(#issue)` form |
| `plugins/discovery/README.md` | modify | One skill row, one agent row, a new `Axis` value |
| `docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md` | regenerate | Never hand-edited |

Frontmatter carries no `name` key (AC1), `metadata.workflow-stage: explore` (Q13 — `blindspot` is
the precedent: it writes no `EXPLORE.md` and serves a different audience yet is still staged
`explore`, because staging is a position-in-lifecycle claim), and a `metadata.summary` under 100
codepoints.

**Sanity Check:**

- `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/discovery/skills" CHECK_SKILL_BASE_REF=origin/main bash plugins/skill-quality/scripts/check-skill.sh --require-evals trace-intent` exits 0
- `scripts/validate-plugins.sh` exits 0
- `node scripts/generate-catalog.mjs --check && node scripts/generate-cheatsheet.mjs --check` both exit 0
- `grep -c '^trace-intent ' scripts/skill-leaf-name-registry.txt` returns 0 — no pre-registration; a
  registered leaf carried by fewer than two plugins FAILs at `check-skill-leaf-names.sh:192`

### Phase 2: The method body and its spokes [TODO]

The substance. Reauthored from upstream, never copied.

| File | Action | Rationale |
|---|---|---|
| `.../trace-intent/SKILL.md` | modify | Full body: routing, tier axis, output format, skip rules |
| `.../trace-intent/context/evidence-categories.md` | create | Q12 — seam prose plus ONE category table, the `ecosystem-discovery.md` shape |
| `.../trace-intent/context/epistemics.md` | create | The five-tier axis, phrasing guide, the code-shape exclusion |
| `.../trace-intent/context/gotchas.md` | create | Check 11 expects a gotchas surface |

Content requirements, each traceable to an acceptance criterion:

- Five **intent-evidence** tiers under that name, never "intent-confidence" (AC3), each mapped to
  its output section — the tier is the sole router.
- Version-control behavior (change coupling, churn, hotspots) admissible at `Inferred`, never
  `Direct` (AC3). Code-shape inference off the ladder entirely, recorded as a Gap.
- A per-citation source-reliability note that does not route (AC3a).
- The Sources Consulted coverage map, one line per category including those returning nothing, in
  the exact form AC4 fixes.
- Exactly two permitted skip reasons; "probably irrelevant" explicitly rejected (AC5).
- No vendor name as a category identifier (AC6). This inverts upstream's six vendor-named playbook
  files, and **no gate catches a regression** — the tracker and forge token classes are commented
  out pending issue #416.

**Tripwires this phase must not trip** (`plugins/discovery/scripts/contract.test.sh`): no
`$ARGUMENTS`-on-preload mechanism claim (five banned strings); no monorepo-relative pointer to the
agents directory — use `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md`; **no second `mkdir -p`**, which may
appear in exactly one file repo-wide (`reference/parent-contract.md`) and which copying the sibling's
Pre-dispatch paragraph wholesale would break; no discard-instead-of-resume prescription; no
`allowed-tools:` frontmatter; no `Bash(${CLAUDE_PLUGIN_ROOT}` permission rule.

**Sanity Check:**

- `bash plugins/discovery/scripts/contract.test.sh` exits 0
- `grep -rl 'mkdir -p' plugins/discovery --include='*.md' | wc -l` returns exactly 1
- `grep -rq 'intent-confidence' plugins/discovery/skills/trace-intent/` returns non-zero
- `check-skill.sh` re-run exits 0 with the body under 500 lines

### Phase 3: The agent and the dispatch machinery [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/discovery/agents/intent-tracer.md` | create | `[EXEC-SHAPE]` on the name |
| `.../trace-intent/SKILL.md` | modify | Sentinel token, baseline filename, gate invocation |
| `plugins/discovery/scripts/contract.test.sh` | modify | Third entry in the write-boundary loop |
| `plugins/discovery/scripts/check-dispatch-artifact.test.sh` | modify | `suite INTENT.md` line |

The agent follows the **`researcher` pattern**: a `disallowedTools:` denylist and no `tools:` key.
An allowlist strips every MCP tool, fatal for an agent whose purpose is reaching tracker and forge
surfaces. `agents/tool-honesty.test.sh` grades the Tool-honesty prose against that choice in both
polarities and fails an agent declaring neither key.

Sentinel: a freshly minted `discovery-trace-intent-preload-<6 hex>`, inlined in the agent file with
a Read-fallback (the `researcher` pattern, which degrades better than `explorer`'s name-only form).
Baseline `.trace-intent-dispatch`. Index `INTENT.md`, sidecar prefix `INTENT-` — validated against
`^[A-Za-z0-9_-]+\.md$`, non-colliding with `EXPLORE`/`RESEARCH`.

`check-dispatch-artifact.sh` needs **no code change** — it is parameterized by `--index-name`.

The maxTurns parity check at `contract.test.sh:186-193` is a hardcoded pair, **not** a loop, and is
deliberately left alone: extending it would assert a budget claim this plan does not make.

**Sanity Check:**

- `bash plugins/discovery/agents/tool-honesty.test.sh` exits 0
- `bash plugins/discovery/scripts/contract.test.sh` exits 0
- `bash plugins/discovery/scripts/check-dispatch-artifact.test.sh` exits 0
- `grep -c 'single write boundary' plugins/discovery/agents/intent-tracer.md` returns >= 1

### Phase 4: The third sidecar header schema [TODO]

| File | Action | Rationale |
|---|---|---|
| `.../trace-intent/context/artifact-shape.md` | create | Third header schema, per the type sketch in `design/design-resolution.md` |
| `plugins/discovery/reference/topic-docs.md` | modify | One row in the "What this plugin writes" table |

The artifact stays **private**: a row in the plugin's own writes table and **no** entry in
`reference/artifact-protocol.md`. That is exactly what avoids the byte-identical-copy rule across
five plugins plus a protocol version bump (constraint 9).

**Sanity Check:**

- `grep -c 'INTENT.md' plugins/discovery/reference/topic-docs.md` returns >= 1
- `grep -c 'INTENT' plugins/discovery/reference/artifact-protocol.md` returns exactly 0
- `node scripts/validate-plugin-contracts.mjs` exits 0 — the five lifecycle copies stay
  byte-identical and untouched

### Phase 5: The cross-plugin seam [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/discipline/skills/reason-dont-recite/SKILL.md` | modify | Appended disambiguating clause ONLY |
| `plugins/discipline/.claude-plugin/plugin.json` | modify | Version bump |
| `plugins/discipline/CHANGELOG.md` | modify | Matching entry |

**Additive only.** That description carries the literal quoted trigger `'why is it this way'`.
Removing or rephrasing it hard-FAILs `skill-quality` check 3 — the trigger-MOVE carve-out iterates
same-plugin siblings only (`check-skill.sh:377`), so a cross-plugin move reads as a dropped trigger
and an auto-invocation regression. Every existing quoted trigger stays byte-identical.

The appended clause narrows that skill's own trigger surface rather than routing to the new skill,
so it needs no gate-plus-fallback wrapper. A clause that *routed* would be a cross-plugin reference
taking the guarded form (`PLUGIN-PHILOSOPHY.md:31-33`).

**Sanity Check:**

- Every pre-existing single-quoted trigger in that description is present byte-identically in the
  new text — verify by `git diff origin/main -- plugins/discipline/skills/reason-dont-recite/SKILL.md`
- `scripts/check-changed-skills.sh origin/main` exits 0 — check 3 is what catches a dropped trigger
- `scripts/check-changelog-parity.sh --check-bump origin/main` exits 0 for both plugins

### Phase 6: Provenance, and the deliberate-departure record [TODO]

| File | Action | Rationale |
|---|---|---|
| `docs/upstream/cursor-pstack.md` | create | Six-section shape of `docs/upstream/mattpocock-skills.md` |

Header naming `cursor/plugins` (MIT), a "Last audited upstream state" line pinning
`60c641e4fad674784b30abcf9f8915dea39df38d`, a recheck trigger, the attribution table, and a
"Not adopted (decided, with reasons)" section — the standing home for every later lane's OMIT verdict.

The `trace-intent` row **must record the code-shape exclusion as a deliberate departure** (AC10):
upstream permits labeled code-shape inference at `Inferred` in two places, and this port forbids it,
argued operationally — code shape is the only always-available zero-cost evidence source, so a
weak-but-admissible rung gets filled exactly when the record is thin.

**Sanity Check:**

- `grep -c 'deliberate departure' docs/upstream/cursor-pstack.md` returns >= 1
- `grep -c '60c641e4' docs/upstream/cursor-pstack.md` returns >= 1
- `grep -c 'Not adopted' docs/upstream/cursor-pstack.md` returns >= 1

### Phase 7: Full sweep, and the fresh-eyes verification gap [TODO]

**Sanity Check:**

- `scripts/affected-tests.sh --run` exits 0
- `scripts/check-changed-skills.sh origin/main`, `scripts/validate-plugins.sh`,
  `scripts/check-changelog-parity.sh --check-bump origin/main`,
  `scripts/check-skill-leaf-names.sh --check`, `scripts/check-skill-portability.sh origin/main`
  all exit 0 (AC13)
- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/discovery/skills/trace-intent/evals/evals.json` exits 0
- The Form-1 declaration line contains no backtick and sits within 8 lines of the outcome gate —
  verify with `grep -n 'fresh[- ]context' plugins/discovery/skills/trace-intent/SKILL.md plugins/discovery/skills/trace-intent/context/*.md`
  and confirm no backtick on the matched line

**Known verification gap, carried not hidden.** Check 21 cannot be executed in this environment: the
sandbox `awk` is mawk 1.3.4, which panics on the scanner's interval expression at
`check-skill.sh:1083`, emits no records, and lets every skill report `PASS — 0 errors` with the check
inert. CI runs `ubuntu-24.04`, which also ships mawk and installs no gawk — so this is a false-green
in CI too, not merely locally. The declaration is authored to the rule derived from reading the
detector source; its live verdict is **unverified**. A defect in shared tooling, filed separately
rather than folded into this port.

## Blast radius

**MEDIUM.** Two plugins change (`discovery`, `discipline`) plus three repo-level docs. No shared
library, no hook, no protocol version bump, no MCP server, no security surface. The two genuine
risks are mechanical and both have named gates: a dropped trigger phrase in another plugin's
description (check 3, hard FAIL) and a second `mkdir -p` in the discovery surface
(`contract.test.sh`, hard FAIL). The judgment-level risk — vendor coupling re-entering through the
category prose — has **no** mechanical gate, because the portability token classes are commented out
pending issue #416, and is therefore a stated review obligation rather than an assumed-covered one.

## Stress-test summary

Filled by the Step 3 plan-reviewer dispatch.

## Execution shape

**Fully sequential — Phase 1 gates every later phase**, and the chain is real rather than
conservative: Phase 2 writes into the file Phase 1 creates, and Phase 3's gate invocation names the
index filename Phase 4 documents. Phase 5 is the only file-disjoint phase, and is small enough that
parallelising one phase buys nothing against the orchestration cost.

Per-phase routing: **all main-session.** Every phase is judgment-heavy prose authoring against a
contract, which is the case the routing table sends to the main session; there is no mechanical
volume work to fan out.

## Open questions

None blocking. Q12 and Q13 resolved to their recommended defaults (seam prose plus one category
table; `workflow-stage: explore`). Two items are carried rather than closed: the check-21
verification gap above, and the research coverage gap recorded in the Brief.

## Handoff to implementation

### User-approval gates

- **The agent's name** is `[EXEC-SHAPE]` — flag if `intent-tracer` is wrong.
- **Any scope expansion beyond the seven phases**, in particular any temptation to fix the mawk
  false-green inside this PR rather than filing it separately.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, all main-session, one commit per phase. No scope-fencing tables — no parallel agents.

### Mechanical work

Commit at each phase boundary with that phase's Sanity Check passing. Push after each commit; the
container is ephemeral. Advance the phase tag `[TODO]` → `[DOING]` → `[DONE]` in this file as each
lands, riding the same commit as that phase's source changes.
