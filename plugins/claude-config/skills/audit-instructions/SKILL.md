---
description: "Audit local CLAUDE.md, AGENTS.md, rules, skills, agents, hook text for instructions current models no longer need, misstated Claude Code behavior, and cross-surface conflicts. Report-only. Use when: 'audit instructions', 'instruction audit', 'are my instructions holding the model back', 'too prescriptive', 'stale Claude Code behavior', 'my @path import is not loading', 'instruction re-reads CLAUDE.md', 'conflicting instructions', 'which instruction wins'. Missing text: audit-prompting-postures."
argument-hint: "[scope] [--target-model <version>] [--opinion] [--no-stopping-condition] [--persist-findings] [--unattended] [--resume]; scope: claude-md|rules|skills|agents|hooks|output-styles|conflicts|all (default: all)"
disallowed-tools: Edit, NotebookEdit
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Find instructions current models no longer need across CLAUDE.md, AGENTS.md, rules, and skill bodies
---

## Purpose

Audit whether the instructions you have written for Claude Code are still earning their context cost
against **current** model capability. As models improve, prior-model-era scar tissue accretes:
workarounds for mistakes the model no longer makes, prescriptive step lists that now constrain more
than they help, bare prohibitions, and show-your-thinking directives. This skill sweeps the
locally-owned instruction surfaces, cites each finding to current official prompting doctrine, tiers
it by how confident the evidence can be, and packages proposed removals or rewrites as a human-gated
diff, so instruction surfaces shrink as models get better instead of only ever growing.

The check catalog, covering the checks I1–I35, their evidence tier, authority tag, severity,
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
declaration and the identical caveat, because the two state the same contract.

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

On **memory-layer surfaces** (CLAUDE.md, a natively read AGENTS.md, CLAUDE.local.md,
`.claude/rules/`, and `rules/` under the user root Phase A resolves),
this skill runs only the model-era checks I6–I35. It never runs or reports the hygiene checks
I1–I5 (line-necessity, length, placement, inferable content, rule-to-hook) on these surfaces;
that instruction-memory hygiene layer belongs to the `claude-memory` plugin. When that plugin is
installed, route memory-layer hygiene to its `audit` skill; when it is not installed, emit a single
one-line pointer to the official CLAUDE.md include/exclude guidance (recorded with I1–I5 in
[reference/criteria.md](reference/criteria.md)) so the operator knows where that audit lives, though this
skill still does not perform it. Either way, no I1–I5 hygiene finding is ever produced here. On
**non-memory surfaces** (skill bodies, agent definitions, hook instruction text, output styles) the
catalog applies, since no incumbent auditor covers instruction content there, **bounded by each row's
own surface declaration**, which is narrower than the partition for some checks. I13, I14, I29,
I31, I32, I33, and I34 name their own surface sets and are not run outside them; I15 is answered
pairwise by Phase B2; this partition never widens a row.

I15 (cross-surface conflict) carries its own narrower routing on the same convention, drawn from the
population `claude-memory:audit`'s C6 actually enumerates via `discover-instruction-surfaces`
(project **and** user root-level CLAUDE.md / a natively read AGENTS.md / rules) rather than from the
name of the layer.
[reference/conflict-criteria.md](reference/conflict-criteria.md) states that boundary and owns it.

**Upstream-owned surfaces are excluded from the editable set.** Installed plugin-cache content is
owned by the publishing repository, and a managed materialization by whatever upstream the consuming
repo's distribution seam names (a `managed` versus `locally-owned` split in the sync manifest that
repo documents, when it does). Findings on these become routing recommendations to the owning
repository's tracker, never in-place edits; absent such a declaration, no exclusion applies.

## Boundary, the bundled `claude-api` skill

One native surface audits prompts for the same anti-pattern families this catalog names, and the
two are routinely conflated:

- **`claude-api` (bundled skill), `prompt-audit` subcommand.** Ships with Claude Code rather than
  as a marketplace plugin. It audits the whole prompt surface of the working directory, application
  code that calls the Claude API included, against the current model's documented anti-patterns,
  and produces a report with a proposed diff that it applies when asked. Its catalog is the
  vendor's own migration guidance, refreshed with the model.
- **This skill (marketplace plugin).** A standing, report-only audit of locally-owned Claude Code
  instruction surfaces against the versioned I-catalog in [reference/criteria.md](reference/criteria.md):
  target-model scoping, deterministic pre-scans, the cross-surface conflict pass, and harness-claim
  staleness the vendor sweep does not look for. Prompts embedded in application source are outside
  this skill's scope by design; that surface stays with the bundled subcommand.

**Routing.** The two compose rather than compete. When the bundled `claude-api` skill resolves in
this session, prefer its `prompt-audit` for a model migration or any pass over application-code
prompts, and run it as the vendor procedure whenever the target model changes. Prefer this skill for
the standing catalog audit of Claude Code surfaces, for cross-surface conflicts, and for harness
claims that misstate Claude Code's own behavior. Where a sweep wants both, run both: recurring gap
shapes the vendor sweep surfaces feed this catalog as new rows, and this skill's findings never
substitute for the vendor procedure on a model change.

**Mutation gate.** `prompt-audit` edits files when the request asks for edits. This skill's contract
is report-only, so never chain into a `prompt-audit` apply on this skill's behalf; surface the
finding and let the user invoke the sweep themselves.

**Availability is never assumed.** Bundled surfaces are gated by settings, environment, plan, and
host; this section states what to do when the surface resolves, never that it is present. The
subcommand set, the distribution facts behind it, and their recheck triggers are recorded in
[reference/bundled-claude-api.md](reference/bundled-claude-api.md).

## Arguments

Parse `$ARGUMENTS` for an optional scope filter. It narrows which surfaces may **produce** findings,
never which surfaces are read. Phase A always inventories the full comparison set, because I15 is a
relation between two surfaces and a scoped run still needs the counterpart:

- `claude-md`: findings on user + project CLAUDE.md, a natively read AGENTS.md, CLAUDE.local.md
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
  Normalization stops in that case by aborting the run with an error that names the exact
  argument to pass (`--target-model <version>`), a non-interactive abort, never a mid-run prompt,
  and never a silent guess that a family alias means its newest version, which would misfire the
  exact model-scoped distinctions the catalog draws. When the ambiguous value is a documented
  family alias, the abort message also names the normalized token of the version that alias
  currently resolves to per the live model-config docs, as a suggested `--target-model` value the
  user confirms, never a value the run proceeds on (e.g. "`opus` currently resolves to `opus-5-5`;
  re-run with `--target-model opus-5-5` to confirm"). Suggesting is not guessing: the user's
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

`--unattended` declares that nobody is available to answer: the ~20-dispatch confirmation in
Phase B becomes a disclosure on the Phase D cost line instead of a question. Only the caller
declares it, in the invocation; a run never infers it from its own session, and a run without the
flag asks.

`--resume` continues the latest run under this project's state key instead of starting a new one,
re-running only the lanes whose report is incomplete or whose inputs changed. Phase B's "Run files
and resume" owns the mechanics.

## Phase A: Inventory

Enumerate every locally-owned instruction surface, then hand the per-surface list to Phase B.
Read [context/phase-a-inventory.md](context/phase-a-inventory.md) before starting Phase A: it
owns the surface discovery order, the per-surface record fields Phase B and Phase B2 both key
off, and the exclusions. Phase B cannot run against a record set built any other way.

## Phase B: Per-surface lanes

Run one **fresh read-only subagent per lane**, where a lane is a set of surfaces packed under the
token budget in "Lane sizing" below, each lane sharing
[reference/criteria.md](reference/criteria.md) and applying the per-surface check partition from
the Scope boundary to every surface it holds. **A record whose residency Phase A could not establish carries that state into
its lane**: the lane still runs, and reports each result as `RESIDENCY-UNRESOLVED` with the named
unresolved condition (Phase D) rather than as a finding, since a removal or a rewrite proposed
against a surface the session may never load is work the reader cannot act on. Seed each lane's
candidate set from a **central pre-scan** run once over every inventoried file before dispatching,
with an extended Bash timeout or in the background, because one pass over a large inventory can
take minutes under Git Bash on Windows. Hand each lane the rows whose `file:` prefix is one of its
files; a lane never re-scans. The seeded checks span both evidence tiers; the scan itself is only
ever deterministic pattern-marking:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh" <file>...
```

It emits `file:line:check-id` candidate rows for I6 (bare prohibitions lacking a rationale
marker), I10 (reasoning-echo directives), the I8 families under per-family ids: `I8-a`
instructed self-check, `I8-b` conservative-reporting, `I8-c` don't-think / don't-reason, `I8-f`
think-carefully steer (I8-c's
tag-naming sub-detect is lane-only, not seeded, as are I8's base row and `I8-d` short-turn
assumptions, whose phrasings are too varied for a pattern that would earn its false-positive rate;
`I8-e` forced interim-status cadence is likewise unseeded, but on a narrower ground: its skeleton is
patternable, and it waits only on an attested instance to calibrate the interval forms against), I23
(self-estimated context-budget phrasing, the budget clause alone, never the stop/summarize/hand-off
verb it licenses, which routinely sits in a different sentence), I25 (retired sampling parameters),
I27 (effort-for-brevity: an effort-lowering directive paired with a brevity token on one line), and
the I28 families (`I28-a` forced-compliance emphasis, case-sensitive; `I28-b` blanket tool
defaults). Concatenate `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/restatement-scan.py`
over the same files, in the same central pass, for the I29 families (`I29-a`
description-restatement; `I29-b` sibling-section-restatement); `--count` prints the row count.
Advisory: a grep cannot judge whether a rationale is genuinely present, whether a restraint clause
is a reporting gate, whether a budget mention is a directive or the counter-steer against one, or
which model a row targets, so the lane refines every candidate against the catalog's fences and the
run's resolved target model.

### Lane sizing

Lane sizing is #4114's token-budget rule below. This skill ships no second sizing rule: no lane
cap and no line-count constant. **Plan the dispatch before dispatching** by running
`lane-runs.sh partition` over the inventoried files, then dispatch those lanes.
**Claim:** dispatch sizing is the #4114 token-budget partition only. **Basis:** issue #4656
(the 9-lane cap and 2,500-line constant were a rejected second rule). **As of:** 2026-09-28.
**Recheck:** when `lane-runs.sh partition` grows a second cap, or the catalog ships a line-count
sizing constant.

A lane's budget is a fraction of the **lane model's own** context window, since a subagent's window
is sized by the model it runs on, not the parent's. The budget is **0.25 of that window**, leaving
the rest for the catalog, the lane brief, the lane's reasoning, and its report, at **3.5 bytes per
token** (Anthropic's glossary: "a token approximately represents 3.5 English characters", fetched
2026-09-28 from <https://docs.claude.com/en/docs/about-claude/glossary>; recheck when that entry
changes or a lane overflows its window on a supported model). Non-ASCII text runs more bytes per
character, so the estimate errs toward smaller lanes. Never state the budget as a line count: the
line figure is derived per run from the bytes per line measured over the in-scope files.

Partition deterministically, feeding every in-scope file as `<group>\t<unit>\t<path>`, where the
group is its plugin (or the memory layer) and the unit is its skill (or the file itself):

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/lane-runs.sh" partition \
  --window-tokens <lane model window> --fraction 0.25 --bytes-per-token 3.5 <rows
```

Plugins stay atomic: whole plugins pack into a lane up to the budget, and only a plugin whose
surface text exceeds the budget splits, by skill, into lanes of its own. Each `split=<plugin>:<n>`
line the script prints goes on the Phase D cost line, and an `over_budget=` line (a single skill
larger than the budget, still one lane) is named there too. Lane ids are a function of the
partition, and the partition's digest is part of every lane's input digest.

Bound concurrency to 3 to 5 lanes at a time. Before the total dispatch count (lanes plus Phase C
verifiers) would exceed ~20, confirm with the user; with `--unattended`, proceed instead and let the
Phase D cost line disclose the planned and actual dispatch counts in place of the confirmation.

### Run files and resume

Each run lives under
`${CLAUDE_PLUGIN_DATA}/audit-instructions/runs/<state-key>/<run-id>/`, the run id a UTC
`YYYYMMDDTHHMMSSZ` stamp, and each lane writes its report to `lanes/<lane-id>.md` there.
`last-audit.md` stays where Phase D puts it. The lease is audit-pass's `run-state.sh`, invoked with
`--plugin-data ${CLAUDE_PLUGIN_DATA}/audit-instructions` so its containment pin holds:
`paths` names the run directory, `lease acquire` starts the run, `lease heartbeat` runs as each
lane's report lands, and `lease release` writes the tombstone at the end. The skill is read-only,
so it takes a lease and no lock.

Every lane carries an **input digest** from `lane-runs.sh digest`: the lane's ordered file list with
content hashes, the partition digest, and one `--param` for each of `catalog_version` (the
`version:` in `reference/criteria.md`), `conflict_criteria_version` (the `Version:` in
`reference/conflict-criteria.md`), `prompt_digest` (a sha256 of the lane brief with its surface
list removed), `harness_version` (`claude --version`), `target_model` (the resolved target),
`scope`, `opinion`, and `no_stopping_condition`. The script refuses a digest missing any of them.
The lane brief hands the lane the exact last line its report must end with, from
`lane-runs.sh marker --lane <id> --digest <digest>`; a report without it as its last non-blank line
is incomplete.

With `--resume`, pick the run with `lane-runs.sh latest --runs-dir <plugin-data>/audit-instructions/runs/<state-key>`,
then `lane-runs.sh attach --run-dir <run-dir>`. Exit 4 means a live lease holds the run: stop and
report the `heartbeat_at` and `stale_after_s` it names, and never attach. Otherwise adopt it with
`lease acquire --epoch <next_epoch>`, recompute every lane's digest, and feed `<lane-id>\t<digest>`
rows to `lane-runs.sh plan --run-dir <run-dir>`: dispatch only the `rerun` lanes and read the
`reuse` lanes' reports from disk. A changed input anywhere in the digest re-runs every lane it
touches, and a changed partition re-runs them all. With no prior run, `--resume` says so and starts
a new one.

The standing execution model and the report identity contract are recorded together in [context/execution-and-report.md](context/execution-and-report.md). Lane sizing, resume, and the
lease stay in this section and `scripts/lane-runs.sh`; that file states the two contracts so a later change to either lands in one place.

A lane that persists its report to disk writes it with the Write tool, which the `guardrails`
plugin's `block-hook-bypass` guard exempts by design, never through a shell redirect whose target is
carried in a variable or through inline Python, which that guard blocks because it cannot resolve
the target. A shell redirect to a literal absolute path under the host temp tree is exempt only when
`CLAUDE_PROJECT_DIR` names a project root that is not itself under a temp tree; a temp-rooted
checkout (a CI clone, a test fixture) has no such exemption, so there the Write tool is the only
route. Verified 2026-09-12 against `plugins/guardrails/hooks/block-hook-bypass.sh`
(`_bbh_temp_default_applies` and the scope note in `block_bypass`) and `plugins/guardrails/README.md`
("`block-hook-bypass` ships two scratch roots exempt"); recheck when the guardrails plugin changes
that guard's exemption set or its block message.

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
(per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository).
Batch one verifier per lane that produced proposals (not one per finding or per surface), counted
under the same ~20-dispatch gate as the Phase B plan; the B2 conflict pass keeps its own separate
verifier. A proposal the verifier defends is demoted to `info` or dropped, never surfaced as a
confident removal.

**An out-of-catalog defect takes its own refutation** (the catalog's "Out-of-catalog defects"
section admits it): reproduce the cited evidence, then ask whether the claim is false today. One
whose evidence does not reproduce is dropped.

**A conflict pair takes a different refutation**, because the removal prompt cannot falsify it: both
sides are usually load-bearing, so "argue it is still needed" defends both and demotes the finding
untested. Refute a pair on its own gates: *same observable, or two sharing a keyword? does any
resident text already arbitrate? is there a prompt that fires both?* A defended pair is one where a
gate fails, dropped for that named reason.

### When dispatch is unavailable

Phases B and C **require** fresh-context, non-fork subagent dispatch. When the Agent tool is
blocked, unavailable, or the session cannot spawn subagents:

1. **Disclose in the report header** which phases ran inline, which were skipped, and why dispatch
   was unavailable. A run that skipped verification is structurally distinguishable from a
   fully verified one.
2. **Mark unverified proposals.** Every removal or rewrite that did not receive an independent
   verifier carries an `(unverified)` marker in the findings table and is never surfaced as a
   confident removal.
3. **Extend the cost line.** The Phase D cost line lists phases that did not run and names the
   verification mode per surface (`verified` | `inline` | `skipped`).

## Phase D: Report

Persist the report to `${CLAUDE_PLUGIN_DATA}/audit-instructions/<state-key>/last-audit.md`, deriving
`<state-key>` by running `bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"` and using its output.
[context/report-keying.md](context/report-keying.md) owns the rest: why the key is load-bearing
here (an unkeyed path makes the cost line below compare against another project's surface set), and
the two absent-prior cases.

Then summarize in chat. The report header carries a **cost line**: how many checks ran per surface
(naming any added by a catalog version bump), the model-scoped rows skipped for the resolved target,
the estimated per-surface token delta versus the previous catalog version **for this project**, and
the dispatch count, planned and actual (lanes, Phase C verifiers, the B2 pass, and its verifier),
stating whether the ~20-dispatch confirmation was asked or, because the run carried `--unattended`, disclosed here in
its place. It names the lane budget (tokens and the derived line figure), every plugin the
partition split by skill and into how many lanes, any over-budget skill, and on a `--resume` how
many lanes were reused and how many re-ran. It also confirms the run added zero new interactive gates (report-only contract
unchanged; the target-model fail-loud stop is an invocation-time validation abort, not an
interactive gate, since it prompts nobody and blocks nothing mid-run). Present findings as a table.
Each row's identity is `(check, claim, sites)` per
[context/execution-and-report.md](context/execution-and-report.md); presentation fields stay
outside the hash. An I15 conflict is one finding with two sites.

| # | Check | Surface:Line | Severity | Tier | Authority | Finding | Proposed change |
|---|-------|--------------|----------|------|-----------|---------|-----------------|

Phase B2's findings carry two anchors, so they get their own **Cross-surface conflicts** subsection.
Beside it, an **Out-of-catalog** subsection holds the defects the catalog's "Out-of-catalog defects"
section admits, each with Check `out-of-catalog`, its evidence, and where it routes; those rows never
reach `emit-findings.sh`.

For each finding, give the proposed removal or rewrite as a fenced diff block. Tier is `mechanical`
(pattern-detectable) or `behavioral` (its ground truth is observed behavior); authority is the
check's tag from the catalog. An I15 conflict finding names **both** participating locations, since it is
a relation between two instructions, not a property of one line.

**No-change findings are exempt from the diff contract.** Where a check forbids proposing an edit,
covering the I15 managed-policy case and any finding routed to an owning repository rather than applied,
write `no change proposed` in the Proposed change column and, in place of the fenced diff, a one-line
statement of who owns the resolution. Never manufacture a diff to satisfy the table; a check that
forbids an edit and a report that demands one would otherwise contradict each other.

**A lane whose surface residency is unresolved emits `RESIDENCY-UNRESOLVED`, not a finding.** The
Proposed change column takes a closed set: a proposed removal or rewrite (with its fenced diff),
`no change proposed` (above), or `RESIDENCY-UNRESOLVED`. The third is the verdict for every result
of a lane whose Phase A record carries an unresolved residency condition: the row stays in the
findings table so the surface is covered, its Proposed change cell reads
`RESIDENCY-UNRESOLVED: <the unresolved condition, as Phase A named it>`, and it carries no fenced
diff, since it is not work the reader can act on until that condition resolves. The candidate
removal or rewrite may be described in the Finding cell as what the lane would propose once the
surface is known to load. Such a row is not a proposal, so Phase C does not re-judge it and the
`(unverified)` marker does not apply.

Three sections the catalog's `OPINION` policy requires: the shadowed-definition `info` section (the
live definition and the inert one, for shadowed skills and subagents, since MCP servers are outside this
report's contract, per I15); a **Withheld** subsection naming every I6/I8 proposal the stopping
condition suppressed and on what ground; and a one-line `OPINION` discovery note stating how many
`OPINION`-tier checks were available, how many did not run, and the argument that enables them.

End with a **Routing** subsection listing every excluded upstream-owned
or memory-layer surface and where its findings should go, and a **Recommended follow-through**
subsection. An editorial cut (removal would not change behavior, or the content is derivable)
may be applied from this report. A consequential deletion, a rule that governs a situation and
is outside the exception register, is applicable only when the commit cites a closed
`/claude-config:unhobble watch` (qualifying sessions met, zero attributed rows).

Open the Sources line with the two official pages the paths and doctrine derive from
(code.claude.com memory + `.claude`-directory docs; the prompting pages cited per check in the
catalog).

**With `--persist-findings`**, also emit the run's I28 and I29 findings for the apply relay per
[context/persist-findings.md](context/persist-findings.md), which owns every mechanic and the
carve-out drop preceding the write. Report the path and the emitted/declined counts, and say
plainly that nothing has been applied.

## Next

- An editorial cut is applied from the report; a consequential cut cites a closed watch: `/claude-config:unhobble watch`.
- A finding lands on the memory layer: `/claude-memory:audit`.
- Posture guidance is absent rather than wrong: `/claude-config:audit-prompting-postures`.

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
- Not memory-layer hygiene: checks I1–I5 on CLAUDE.md, a natively read AGENTS.md, and rules route to `claude-memory`'s `audit`
  skill when installed, and upstream-owned plugin-cache or managed materializations route to the
  owning repository rather than being edited here.
- Does not grade a contradiction whose two halves both sit in the
  **discover-instruction-surfaces** population, namely root-level project **or user** `CLAUDE.md` /
  `CLAUDE.local.md` / a natively read `AGENTS.md` or `.claude/AGENTS.md` / rules, including
  **user↔project** pairs. That is `claude-memory:audit`'s C6.
  A **nested** `CLAUDE.md` / `CLAUDE.local.md` side, an auto-memory side, or any surface outside that
  population keeps the pair here;
  [reference/conflict-criteria.md](reference/conflict-criteria.md) owns the routing table and its
  evidence.
