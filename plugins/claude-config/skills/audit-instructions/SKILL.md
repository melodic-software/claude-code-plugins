---
description: "Audit locally-owned Claude Code instruction surfaces, including CLAUDE.md, .claude/rules, skill bodies, agent definitions, hook instruction text and output styles, for instructions current models no longer need (prior-model workarounds, over-prescriptive scaffolding, stale examples), instructions that misstate Claude Code's own behavior or cite files in forms that never load, and cross-surface conflicts where two surfaces contradict each other. Report-only: proposed diffs gated to the human, never auto-applied. Use when: 'after a model upgrade', 'are my instructions holding the model back', 'instructions the model no longer needs', 'too prescriptive', 'audit instructions', 'instruction audit', 'stale Claude Code behavior', 'outdated harness claim', 'my @path import is not loading', 'instruction re-reads CLAUDE.md', 'conflicting instructions', 'contradictory instructions', 'which instruction wins'. Not a brevity pass and not memory-layer hygiene."
argument-hint: "[scope] [--target-model <version>] [--opinion] [--no-stopping-condition] [--persist-findings]; scope: claude-md|rules|skills|agents|hooks|output-styles|conflicts|all (default: all)"
disallowed-tools: Edit, NotebookEdit
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Find instructions current models no longer need across CLAUDE.md, rules, and skill bodies
---

## Purpose

Audit whether the instructions you have written for Claude Code are still earning their context cost
against **current** model capability. As models improve, prior-model-era scar tissue accretes:
workarounds for mistakes the model no longer makes, prescriptive step lists that now constrain more
than they help, bare prohibitions, and show-your-thinking directives. This skill sweeps the
locally-owned instruction surfaces, cites each finding to current official prompting doctrine, tiers
it by how confident the evidence can be, and packages proposed removals or rewrites as a human-gated
diff, so instruction surfaces shrink as models get better instead of only ever growing.

The check catalog, covering the checks I1–I29, their evidence tier, authority tag, severity,
per-surface applicability, and the `OPINION`-tier enablement policy, lives in
[reference/criteria.md](reference/criteria.md); the deterministic pre-scan is
`${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh`.
One check has a different unit of judgment, do two surfaces contradict each other, and Phase B2
answers it against [reference/conflict-criteria.md](reference/conflict-criteria.md).

## Read-only contract

This skill is report-only. There is no `--fix`: instruction files are the operator's voice, so
every change is applied by the human (or explicitly delegated afterward), never by this skill.
Diffs are proposed artifacts. A clean audit is a valid outcome.

`disallowed-tools: Edit, NotebookEdit` narrows the surface; it does **not** make the contract
mechanical. `Write` stays for the Phase D persist and `Bash` for the pre-scans, and either can mutate
a file this skill has already read, so this is an instruction-held contract with a narrowed accident
surface, not an enforced one. Never describe it to an operator as a guarantee. The restriction clears
on their next message (<https://code.claude.com/docs/en/skills>, frontmatter reference, fetched
2026-08-12), so whoever accepts a diff can apply it. `audit-prompting-postures` carries the identical
declaration and the identical caveat, because the two state the same contract and drifting on it is
the shape of defect this pair keeps producing.

## Scope boundary (route out)

This skill owns instruction **content vs current model capability**. It does not own the adjacent
concerns its siblings already cover, so route rather than re-answer:

- Posture guidance that is **absent and needed** is `claude-config:audit-prompting-postures` (same
  plugin), the additive lane to this one. This skill judges instruction text that is present and
  wrong; that one proposes text the official prompting guide says a component's purpose needs and
  the component does not carry. Neither finds the other's defects, so a sweep that wants both runs
  both, and a request phrased as "what guardrails is this skill missing" belongs there, not here.
- Structural skill lint (frontmatter, line caps, broken refs) is `skill-quality:check`.
- Token brevity for its own sake is `docs-hygiene:compress`.
- Config-file mechanics (settings.json, .mcp.json, hooks wiring) is `claude-config:audit`; grant
  portability is `claude-config:audit-permission-grants`.
- The empirical bare-baseline experiment, stripping the surfaces, observing the bare model, and
  re-adding on repeated stumble evidence, is `unhobble` (same plugin): this skill judges instruction
  *text* against doctrine; unhobble measures the *model*.

On **memory-layer surfaces** (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, and `rules/` under the
user root Phase A resolves),
this skill runs only the model-era checks I6–I29. It never runs or reports the hygiene checks
I1–I5 (line-necessity, length, placement, inferable content, rule-to-hook) on these surfaces;
that instruction-memory hygiene layer belongs to the `claude-memory` plugin. When that plugin is
installed, route memory-layer hygiene to its `audit` skill; when it is not installed, emit a single
one-line pointer to the official CLAUDE.md include/exclude guidance (recorded with I1–I5 in
[reference/criteria.md](reference/criteria.md)) so the operator knows where that audit lives, though this
skill still does not perform it. Either way, no I1–I5 hygiene finding is ever produced here. On
**non-memory surfaces** (skill bodies, agent definitions, hook instruction text, output styles) the
catalog applies, since no incumbent auditor covers instruction content there, **bounded by each row's
own surface declaration**, which is narrower than the partition for some checks. I13 and I14 name
their own surface sets and are not run outside them; this partition never widens a row.

I15 (cross-surface conflict) carries its own narrower routing on the same convention, drawn from the
population `claude-memory:audit`'s C6 actually enumerates via `discover-instruction-surfaces`
(project **and** user root-level CLAUDE.md / rules) rather than from the name of the layer.
[reference/conflict-criteria.md](reference/conflict-criteria.md) states that boundary and owns it.

**Upstream-owned surfaces are excluded from the editable set.** Installed plugin-cache content is
owned by the publishing repository, and a managed materialization by whatever upstream the consuming
repo's distribution seam names (a `managed` versus `locally-owned` split in the sync manifest that
repo documents, when it does). Findings on these become routing recommendations to the owning
repository's tracker, never in-place edits; absent such a declaration, no exclusion applies.

## Arguments

Parse `$ARGUMENTS` for an optional scope filter. It narrows which surfaces may **produce** findings,
never which surfaces are read. Phase A always inventories the full comparison set, because I15 is a
relation between two surfaces and a scoped run still needs the counterpart:

- `claude-md`: findings on user + project CLAUDE.md and CLAUDE.local.md
- `rules`: findings on `.claude/rules/` and `rules/` under the user root Phase A resolves
- `skills`: findings on skill bodies and their context/reference files
- `agents`: findings on agent definition markdown
- `hooks`: findings on hook instruction text: prompt-type hook text, and handler output injected
  into the session's context
- `output-styles`: findings on output-style markdown
- `conflicts`: Phase A plus Phase B2 only, so a scheduled routine can compose it on its own budget
- `all`: findings on every locally-owned surface, and the conflict pass (default)

A finding still names both sides of a conflict even when one side is out of scope; the filter decides
which side the run is auditing.

`--target-model <version>` sets the model the audit judges against. The catalog's model-scoped
checks and rows (its "Model scoping" section) fire only when this resolved target matches their
scope; non-matching ones are inert and the report lists them as `skipped-for-target`.

- **Default resolution ladder:** (1) an explicit `--target-model` always wins; (2) otherwise use
  the session's EFFECTIVE model, what this session actually runs, which a `--model` launch
  override may have set rather than the bare settings pin, and normalize it alias → model VERSION
  against the live model-config docs at run time; (3) anything that cannot be normalized to a
  single version fails loud (below). The normalized token is the catalog's local grammar,
  lowercase family and version joined by hyphens (`opus-5`, `sonnet-5`, `fable-5`), derived from
  the documented model the alias or full model name resolves to, not a string upstream publishes.
  Matching against catalog scopes is exact equality of the normalized version token, and the
  catalog's "Model scoping" section owns that predicate.
- **Fail loud on ambiguity:** a value may carry no version at all, such as a family alias like `opus`
  (with or without a context-window suffix such as `[1m]`), an absent `model` setting in an
  out-of-session run, or a custom/gateway deployment ID that matches no documented pattern.
  Normalization MUST stop in that case by ABORTING the run with an error that names the exact
  argument to pass (`--target-model <version>`), a non-interactive abort, never a mid-run prompt,
  and never a silent guess that a family alias means its newest version, which would misfire the
  exact model-scoped distinctions the catalog draws. When the ambiguous value is a documented
  family alias, the abort message ALSO names the normalized token of the version that alias
  currently resolves to per the live model-config docs, as a suggested `--target-model` value the
  user confirms, never a value the run proceeds on (e.g. "`opus` currently resolves to `opus-5`;
  re-run with `--target-model opus-5` to confirm"). Suggesting is not guessing: the user's
  confirmation is what turns the resolution into a target. The resolved target (and how it was
  resolved) is named in the report's tier-transparency line.

Two flags govern the `OPINION` tier, whose enablement policy the catalog defines:

- `--opinion`: also run the `OPINION`-tier checks that emit findings. Off by default; their
  findings are capped at `info` and are never applied. **Which rows those are is read from the
  catalog at run time and deliberately not restated here**: the catalog owns the enablement policy,
  so a second copy of the set in this file is one more thing to keep in sync on every new
  `OPINION` row, and a stale copy silently narrows the flag. The run's tier-transparency line
  reports how many it found.
- `--no-stopping-condition`: disable the `OPINION`-tier stopping condition that bounds I6 and I8.
  It is on by default because it withholds findings rather than emitting them, so turning it off
  makes both trimming checks more aggressive, not the audit more conservative.

`--persist-findings` also writes the run's I28 and I29 findings as a `type: review-findings` file
for `review:fanout`'s `fix` action (off by default; only I28 and I29 are eligible, body-scoped; a
proposal for a human-gated relay, not an applied edit; see
[context/persist-findings.md](context/persist-findings.md)).

## Phase A: Inventory

Enumerate every locally-owned instruction surface, then hand the per-surface list to Phase B.
Read [context/phase-a-inventory.md](context/phase-a-inventory.md) before starting Phase A: it
owns the surface discovery order, the per-surface record fields Phase B and Phase B2 both key
off, and the exclusions. Phase B cannot run against a record set built any other way.

## Phase B: Per-surface lanes

Run one **fresh read-only subagent per surface**, each sharing
[reference/criteria.md](reference/criteria.md) and applying the per-surface check partition from
the Scope boundary. Seed each lane's candidate set with the deterministic pre-scan over that
surface's files (the seeded checks span both evidence tiers; the scan itself is only ever
deterministic pattern-marking):

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh" <file>...
```

It emits `file:line:check-id` candidate rows for I6 (bare prohibitions lacking a rationale
marker), I10 (reasoning-echo directives), the I8 families under per-family ids: `I8-a`
instructed self-check, `I8-b` conservative-reporting, `I8-c` don't-think / don't-reason (I8-c's
tag-naming sub-detect is lane-only, not seeded, as are I8's base row and `I8-d` short-turn
assumptions, whose phrasings are too varied for a pattern that would earn its false-positive rate;
`I8-e` forced interim-status cadence is likewise unseeded, but on a narrower ground: its skeleton is
patternable, and it waits only on an attested instance to calibrate the interval forms against), I23
(self-estimated context-budget phrasing, the budget clause alone, never the stop/summarize/hand-off
verb it licenses, which routinely sits in a different sentence), I25 (retired sampling parameters),
I27 (effort-for-brevity: an effort-lowering directive paired with a brevity token on one line), and
the I28 families (`I28-a` forced-compliance emphasis, case-sensitive; `I28-b` blanket tool
defaults). Concatenate `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/restatement-scan.py`
over the same files for the I29 families (`I29-a` description-restatement; `I29-b`
sibling-section-restatement); `--count` prints the row count.
Advisory: a grep cannot judge whether a rationale is genuinely present, whether a restraint clause
is a reporting gate, whether a budget mention is a directive or the counter-steer against one, or
which model a row targets, so the lane refines every candidate against the catalog's fences and the
run's resolved target model.

Bound concurrency to 3–5 lanes at a time; the skills surface fans out one lane per skill. Before the
total dispatch count (lanes plus Phase C verifiers) would exceed ~20, confirm with the user.

## Phase B2: Cross-surface conflict pass

Phase B judges each surface alone, so a contradiction spanning two surfaces is invisible to it. This
pass supplies the missing unit: a **pair** of surfaces that both claim authority over one behavior and
disagree. Every criterion, table and worked example lives in
[reference/conflict-criteria.md](reference/conflict-criteria.md). **A scope filters findings, never
reads.** B2 enumerates every surface `all` would collect and reports a pair when at least one anchor
is in scope; the criteria file states why.

Seed it with the deterministic pre-scan over the inventoried files:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/conflict-scan.sh" <file>...
```

It emits `fileA:lineA|fileB:lineB|entity|flags` candidate pairs; `--count` prints the row count.
Advisory and always exit 0, so every row is refined against the criteria file's must-not-flag set.

**The scan is a priority ordering, not the work list.** It only reaches directives naming a
tool-shaped entity, so an ordinary pair such as "Always run tests before committing" against "Never run
tests" emits nothing. Work the rows first, then read the surfaces for pairs it cannot shape-match.
**A pass that reports only what the scanner emitted has not run this check.**

**Detect the disagreement; do not adjudicate it:** name a winner only where the criteria file's
precedence table cites a documented order, otherwise report `unresolved`. Its routing table governs
what belongs to `claude-memory:audit`'s C6 instead.

## Phase C: Verify pass

Every removal or rewrite proposal is re-judged before it reaches the report. Dispatch **fresh-context,
non-fork** subagents, since this is a self-grade of the audit's own proposals and a fork that inherits the
producing context would not be independent, prompted to refute: "would removing this instruction
cause Claude to make mistakes? Argue that it is still load-bearing." Where the removal call is
high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is
installed and set up**, e.g. the OpenAI Codex plugin, when its documented surface can take this
artifact, invoked per its own docs, with the fresh-context same-vendor subagent as the stated
fallback, never a route to a command that may not resolve
(per `docs/PLUGIN-PHILOSOPHY.md` "Fresh-eyes checkpoints" in the marketplace repository).
Batch one verifier per surface
(not one per finding), counted under the same ~20-dispatch gate. A proposal the verifier defends is
demoted to `info` or dropped, never surfaced as a confident removal.

**A conflict pair takes a different refutation**, because the removal prompt cannot falsify it: both
sides are usually load-bearing, so "argue it is still needed" defends both and demotes the finding
untested. Refute a pair on its own gates: *same observable, or two sharing a keyword? does any
resident text already arbitrate? is there a prompt that fires both?* A defended pair is one where a
gate fails, dropped for that named reason.

### When dispatch is unavailable

Phases B and C **require** fresh-context, non-fork subagent dispatch. When the Agent tool is
blocked, unavailable, or the session cannot spawn subagents:

1. **Disclose in the report header** which phases ran inline, which were skipped, and why dispatch
   was unavailable. A run that skipped verification MUST be structurally distinguishable from a
   fully verified one.
2. **Mark unverified proposals.** Every removal or rewrite that did not receive an independent
   verifier MUST carry an `(unverified)` marker in the findings table and MUST NOT be surfaced as a
   confident removal.
3. **Extend the cost line.** The Phase D cost line MUST list phases that did not run and name the
   verification mode per surface (`verified` | `inline` | `skipped`).

## Phase D: Report

Persist the report to `${CLAUDE_PLUGIN_DATA}/audit-instructions/<state-key>/last-audit.md`, deriving
`<state-key>` by running `bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"` and using its output.
[context/report-keying.md](context/report-keying.md) owns the rest: why the key is load-bearing
here (an unkeyed path makes the cost line below compare against another project's surface set), and
the two absent-prior cases.

Then summarize in chat. The report header carries a **cost line**: how many checks ran per surface
(naming any added by a catalog version bump), the model-scoped rows skipped for the resolved target,
and the estimated per-surface token delta versus the previous catalog version **for this project**,
and it confirms the run added zero new interactive gates (report-only contract unchanged; the
target-model fail-loud stop is an invocation-time validation abort, not an interactive gate, since it
prompts nobody and blocks nothing mid-run). Present findings as a table:

| # | Check | Surface:Line | Severity | Tier | Authority | Finding | Proposed change |
|---|-------|--------------|----------|------|-----------|---------|-----------------|

Phase B2's findings carry two anchors, so they get their own **Cross-surface conflicts** subsection.

For each finding, give the proposed removal or rewrite as a fenced diff block. Tier is `mechanical`
(pattern-detectable) or `behavioral` (its ground truth is observed behavior); authority is the
check's tag from the catalog. An I15 conflict finding names **both** participating locations, since it is
a relation between two instructions, not a property of one line.

**No-change findings are exempt from the diff contract.** Where a check forbids proposing an edit,
covering the I15 managed-policy case and any finding routed to an owning repository rather than applied,
write `no change proposed` in the Proposed change column and, in place of the fenced diff, a one-line
statement of who owns the resolution. Never manufacture a diff to satisfy the table; a check that
forbids an edit and a report that demands one would otherwise contradict each other.

Three sections the catalog's `OPINION` policy requires: the shadowed-definition `info` section (the
live definition and the inert one, for shadowed skills and subagents, since MCP servers are outside this
report's contract, per I15); a **Withheld** subsection naming every I6/I8 proposal the stopping
condition suppressed and on what ground; and a one-line `OPINION` discovery note stating how many
`OPINION`-tier checks were available, how many did not run, and the argument that enables them.

End with a **Routing** subsection listing every excluded upstream-owned
or memory-layer surface and where its findings should go, and a **Recommended follow-through**
subsection: apply an accepted change, then observe whether Claude's behavior actually shifts;
re-add on the next mistake as the compounding safety net; for example blocks, A/B against the
no-example default. The full delete-and-watch loop is operationalized by `/claude-config:unhobble`
(same plugin); route there when the operator wants the experiment run rather than described.

Open the Sources line with the two official pages the paths and doctrine derive from
(code.claude.com memory + `.claude`-directory docs; the prompting pages cited per check in the
catalog).

**With `--persist-findings`**, also emit the run's I28 and I29 findings for the apply relay per
[context/persist-findings.md](context/persist-findings.md), which owns every mechanic and the
carve-out drop preceding the write. Report the path and the emitted/declined counts, and say
plainly that nothing has been applied.

## Gotchas

- **Examples are not scaffolding.** Keep the 3–5 format/tone/structure-steering examples the docs
  recommend; flag an example block only when it pins the model's *approach* to a task (behavioral
  scaffolding), never when it steers output format.
- **Bare-prohibition rewrites go positive first.** The primary remediation is "say what to do
  instead of what not to do"; adding a rationale is the fallback where a genuine hard "never"
  survives. Do not mechanically delete every prohibition the pre-scan flags.
- **Behavioral findings ship as proposals, not confident cuts.** A narrow eval can miss a small
  regression from an over-aggressive trim, which is why the verify pass and the delete-and-watch
  loop exist. Never present a behavioral removal as certain.
- **Windows shell.** The pre-scans are bash; on native Windows run them through Git Bash.
- **A conflict pair needs two files.** Feeding `conflict-scan.sh` one surface at a time reproduces
  Phase B's blind spot and always reports clean.

## What this skill does NOT do

- Never edits an instruction file and never auto-files a tracker item; output is a report plus
  proposed diffs the human applies.
- Not a token-brevity pass (`docs-hygiene:compress`) and not structural skill lint
  (`skill-quality:check`).
- Not memory-layer hygiene: checks I1–I5 on CLAUDE.md/rules route to `claude-memory`'s `audit`
  skill when installed, and upstream-owned plugin-cache or managed materializations route to the
  owning repository rather than being edited here.
- Does not grade a contradiction whose two halves both sit in the
  **discover-instruction-surfaces** population, namely root-level project **or user** `CLAUDE.md` /
  `CLAUDE.local.md` / rules, including **user↔project** pairs. That is `claude-memory:audit`'s C6.
  A **nested** `CLAUDE.md` / `CLAUDE.local.md` side, an auto-memory side, or any surface outside that
  population keeps the pair here;
  [reference/conflict-criteria.md](reference/conflict-criteria.md) owns the routing table and its
  evidence.
