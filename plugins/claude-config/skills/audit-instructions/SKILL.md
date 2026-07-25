---
name: audit-instructions
description: "Audit locally-owned Claude Code instruction surfaces — user + project CLAUDE.md, .claude/rules, skill bodies, agent definitions, prompt-type hooks, output styles — for instructions current models no longer need: prior-model workarounds, over-prescriptive scaffolding, bare prohibitions, reasoning-echo directives, stale examples. Report-only: emits a findings report with proposed diffs, gated to the human, never auto-applied. Use when: 'after a model upgrade', 'are my instructions holding the model back', 'instructions the model no longer needs', 'too prescriptive', 'audit instructions', 'instruction audit'. Not a brevity pass and not memory-layer hygiene."
argument-hint: "[scope] [--opinion] [--no-stopping-condition] — scope: claude-md|rules|skills|agents|hooks|output-styles|all (default: all)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Audit whether the instructions you have written for Claude Code are still earning their context
cost against **current** model capability. As models improve, prior-model-era scar tissue
accretes: workarounds for mistakes the model no longer makes, prescriptive step lists that now
constrain more than they help, bare prohibitions, and show-your-thinking directives. This skill
sweeps the locally-owned instruction surfaces, cites each finding to current official prompting
doctrine, tiers it by how confident the evidence can be, and packages proposed removals or
rewrites as a human-gated diff — so instruction surfaces shrink as models get better instead of
only ever growing.

The check catalog — the checks I1–I13, their evidence tier, authority tag, severity, per-surface
applicability, and the `OPINION`-tier enablement policy — lives in
[reference/criteria.md](reference/criteria.md). The
deterministic pre-scan is
`${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh`.

## Read-only contract

This skill is report-only. There is no `--fix`: instruction files are the operator's voice —
every change is applied by the human (or explicitly delegated afterward), never by this skill.
Diffs are proposed artifacts. A clean audit is a valid outcome.

## Scope boundary (route out)

This skill owns instruction **content vs current model capability**. It does not own the adjacent
concerns its siblings already cover — route rather than re-answer:

- Structural skill lint (frontmatter, line caps, broken refs) is `skill-quality:check`.
- Token brevity for its own sake is `docs-hygiene:compress`.
- Config-file mechanics (settings.json, .mcp.json, hooks wiring) is `claude-config:audit`; grant
  portability is `claude-config:audit-permission-grants`.

On **memory-layer surfaces** (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, `~/.claude/rules/`),
this skill runs only the model-era checks I6–I13. It never runs or reports the hygiene checks
I1–I5 (line-necessity, length, placement, inferable content, rule-to-hook) on these surfaces —
that instruction-memory hygiene layer belongs to the `claude-memory` plugin. When that plugin is
installed, route memory-layer hygiene to its `audit` skill; when it is not installed, emit a single
one-line pointer to the official CLAUDE.md include/exclude guidance (recorded with I1–I5 in
[reference/criteria.md](reference/criteria.md)) so the operator knows where that audit lives — this
skill still does not perform it. Either way, no I1–I5 hygiene finding is ever produced here. On
**non-memory surfaces** (skill bodies, agent definitions, prompt-type hooks, output styles) the
full catalog I1–I13 applies — no incumbent auditor covers instruction content there.

I12 (cross-surface conflict) carries its own narrower routing on the same convention: a contradiction
wholly inside the memory surfaces `claude-memory:audit` check C6 actually inventories — the
project-root `CLAUDE.md`/`CLAUDE.local.md` and the project `.claude/rules/` tree — is C6's and is not
reported here, while one reaching any surface C6 does not discover (user-scope memory, nested
`CLAUDE.md`), one with at least one side outside the memory layer, or any side in the managed-policy
tier, is this skill's. The catalog states the full rule.

**Upstream-owned surfaces are excluded from the editable set.** Installed plugin-cache content is
owned by the publishing repository, and a managed materialization is owned by whatever upstream
the consuming repo's own distribution seam names (a `managed` versus `locally-owned` split in the
sync manifest that repo documents, when it documents one). Findings on these become routing
recommendations to the owning repository's tracker, never in-place edits. Absent such a
declaration in the consuming repo, no managed-file exclusion applies.

## Arguments

Parse `$ARGUMENTS` for an optional scope filter. It narrows which surfaces may **produce** findings —
never which surfaces are read. Phase A always inventories the full comparison set, because I12 is a
relation between two surfaces and a scoped run still needs the counterpart:

- `claude-md` — findings on user + project CLAUDE.md and CLAUDE.local.md
- `rules` — findings on `.claude/rules/` and `~/.claude/rules/`
- `skills` — findings on skill bodies and their context/reference files
- `agents` — findings on agent definition markdown
- `hooks` — findings on prompt-type hook text
- `output-styles` — findings on output-style markdown
- `all` — findings on every locally-owned surface (default)

A finding still names both sides of a conflict even when one side is out of scope; the filter decides
which side the run is auditing.

Two flags govern the `OPINION` tier, whose enablement policy the catalog defines:

- `--opinion` — also run the `OPINION`-tier checks that emit findings (I13 today). Off by default;
  their findings are capped at `info` and are never applied.
- `--no-stopping-condition` — disable the `OPINION`-tier stopping condition that bounds I6 and I8.
  It is on by default because it withholds findings rather than emitting them, so turning it off
  makes both trimming checks more aggressive, not the audit more conservative.

## Phase A — Inventory

Enumerate the locally-owned instruction surfaces in scope. All paths below are current per the
official memory and `.claude`-directory docs (cited in the report's Sources line):

- User — resolve the root as `${CLAUDE_CONFIG_DIR:-~/.claude}` (setting `CLAUDE_CONFIG_DIR`
  relocates the whole `~/.claude` tree, so never hardcode `~/.claude`), then: `CLAUDE.md`,
  `rules/`, `skills/`, `agents/`, `output-styles/` under that root.
- Project: `./CLAUDE.md` or `./.claude/CLAUDE.md`, `./CLAUDE.local.md`, and every nested
  `CLAUDE.md` / `CLAUDE.local.md` in subdirectories of the project tree (Claude loads these on
  demand when it reads files in those directories, so walk the tree — do not stop at the root);
  `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, `.claude/output-styles/`.
- Prompt-type hook text configured in the project or user `settings.json`, **and in
  `.claude/settings.local.json`** — local settings are a supported hook-configuration scope, so hook
  text there is as live as any other. Extract the prompt text only; never carry a command line,
  token, or other secret-bearing value out of a settings file into the report.

Exclude from the **editable** set, and hold for the routing subsection: auto-memory
(`~/.claude/projects/<project>/memory/`, owned by `claude-memory`), installed plugin-cache content,
and any managed materialization per the Scope boundary. Record each surface found and each surface
skipped, so the report's tier-transparency line can name both.

Some surfaces are inventoried **read-only** rather than excluded outright, because a later phase has
to compare against them even though no proposed edit may ever touch them. Read-only inventory changes
nothing about ownership: these surfaces still produce no proposal of their own, and a finding
involving one still carries the no-change representation and its routing recommendation.

- **Org-managed policy** — the managed-policy `CLAUDE.md`, any `claudeMd` value in managed settings,
  and prompt-type hook text configured in managed settings. All three are live instruction text, and
  a managed hook contradicting a project skill is exactly the conflict I12 explicitly owns; that
  comparison is impossible if the text is never read. Extract managed hook text under the same
  prompt-text-only, no-secrets handling as the other settings scopes.
- **Upstream-owned instruction text that is nonetheless live** — skill bodies and agent definitions
  from the cache of an **enabled** plugin, `type: "prompt"` handler text in an enabled plugin's
  `hooks/hooks.json` (a plugin is a supported hook location and `prompt` a supported handler type, so
  that text is as live as a settings-configured hook), and any managed materialization. Enablement is
  the same gate for all three: a disabled plugin's cache stays on disk while none of its components
  load, so resolve effective `enabledPlugins` across settings scopes first and inventory only the
  plugins that resolve enabled — a cached body from a disabled plugin would put text Claude cannot
  load into the comparison corpus. An invoked plugin skill's
  instructions are in context alongside the project's own, so they can hold one side of a conflict.
  They are read for comparison only, prompt text only and no secret-bearing values: the existing
  exclusion from the editable set and the upstream-routing behavior are unchanged, so a finding here
  routes to the owning repository's tracker and proposes no in-place edit.
- **Every I12 counterpart outside the requested scope.** A scope argument narrows which surfaces may
  *produce* findings, not which are read: a conflict is a relation between two surfaces, so a run
  scoped to `skills` still inventories `CLAUDE.md`, rules, agents, hooks, and output styles as
  comparison counterparts. Findings still name both sides; the filter decides which side the run is
  auditing, never that the counterpart goes unread.

## Phase B — Per-surface lanes

Run one **fresh read-only subagent per surface**, each sharing
[reference/criteria.md](reference/criteria.md) and applying the per-surface check partition from
the Scope boundary. Seed each lane's mechanical tier with the deterministic pre-scan over that
surface's files:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh" <file>...
```

It emits `file:line:check-id` candidate rows for I6 (bare prohibitions lacking a rationale marker)
and I10 (reasoning-echo directives); `--count` prints the row count. It is advisory and a grep
cannot judge whether a rationale is genuinely present, so the lane refines every candidate rather
than reporting it verbatim.

**I12 is not a per-surface lane.** A conflict is a relation between two surfaces, so a lane holding
one surface's files cannot see the other side, and a lane that rescans everything re-derives the same
pair in every lane. Every per-surface lane therefore runs its assigned checks **minus I12**, and one
additional **cross-surface conflict lane** runs I12 alone. That lane receives the whole inventory —
including the read-only managed-policy text and the out-of-scope counterparts Phase A collected —
already symlink-resolved and `@path`-expanded on the memory surfaces that implement imports, and
emits each conflict once, naming both locations.
It is one lane regardless of how many surfaces are in scope, and it counts against the dispatch
budget below like any other.

Bound concurrency to 3–5 lanes at a time. The skills surface fans out one lane per skill. Before
the total dispatch count (per-surface lanes plus the cross-surface conflict lane plus the Phase C
verifiers) would exceed ~20, confirm with the user first.

## Phase C — Verify pass

Every removal or rewrite proposal is re-judged before it reaches the report. Dispatch **fresh-context,
non-fork** subagents — this is a self-grade of the audit's own proposals, so a fork that inherits the
producing context would not be independent — prompted to refute: "would removing this instruction
cause Claude to make mistakes? Argue that it is still load-bearing." Where the removal call is
high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is
installed and set up** — e.g. the OpenAI Codex plugin, when its documented surface can take this
artifact, invoked per its own docs — with
the fresh-context same-vendor subagent as the fallback, never a route to a command that may not
resolve. Batch one verifier per surface
(not one per finding), counted under the same ~20-dispatch gate. A proposal the verifier defends is
demoted to `info` or dropped, never surfaced as a confident removal.

## Phase D — Report

Persist the report to `${CLAUDE_PLUGIN_DATA}/audit-instructions/last-audit.md` and summarize it in
chat. Present findings as a table:

| # | Check | Surface:Line | Severity | Tier | Authority | Finding | Proposed change |
|---|-------|--------------|----------|------|-----------|---------|-----------------|

For each finding, give the proposed removal or rewrite as a fenced diff block. Tier is `mechanical`
(pattern-detectable) or `behavioral` (its ground truth is observed behavior); authority is the
check's tag from the catalog. An I12 conflict finding names **both** participating locations — it is
a relation between two instructions, not a property of one line.

**No-change findings are exempt from the diff contract.** Where a check forbids proposing an edit —
the I12 managed-policy case, and any finding routed to an owning repository rather than applied —
write `no change proposed` in the Proposed change column and, in place of the fenced diff, a one-line
statement of who owns the resolution. Never manufacture a diff to satisfy the table; a check that
forbids an edit and a report that demands one would otherwise contradict each other.

Three sections the catalog's `OPINION` policy requires: the shadowed-definition `info` section (the
live definition and the inert one, for shadowed skills and subagents — MCP servers are outside this
report's contract, per I12); a **Withheld** subsection naming every I6/I8 proposal the stopping
condition suppressed and on what ground; and a one-line `OPINION` discovery note — how many
`OPINION`-tier checks were available, how many did not run, and the argument that enables them.

End with a **Routing** subsection listing every excluded upstream-owned
or memory-layer surface and where its findings should go, and a **Recommended follow-through**
subsection: apply an accepted change, then observe whether Claude's behavior actually shifts;
re-add on the next mistake as the compounding safety net; for example blocks, A/B against the
no-example default. That loop is prose guidance — this skill ships no eval tooling.

Open the Sources line with the two official pages the paths and doctrine derive from
(code.claude.com memory + `.claude`-directory docs; the prompting pages cited per check in the
catalog).

## Gotchas

- **Examples are not scaffolding.** Keep the 3–5 format/tone/structure-steering examples the docs
  recommend; flag an example block only when it pins the model's *approach* to a task (behavioral
  scaffolding), never when it steers output format.
- **Bare-prohibition rewrites go positive first.** The primary remediation is "say what to do
  instead of what not to do"; adding a rationale is the fallback where a genuine hard "never"
  survives. Do not mechanically delete every prohibition the pre-scan flags.
- **Behavioral findings ship as proposals, not confident cuts.** A narrow eval can miss a small
  regression from an over-aggressive trim — that is why the verify pass and the delete-and-watch
  loop exist. Never present a behavioral removal as certain.
- **Windows shell.** The pre-scan is bash; on native Windows run it through Git Bash.

## What this skill does NOT do

- Never edits an instruction file and never auto-files a tracker item — output is a report plus
  proposed diffs the human applies.
- Not a token-brevity pass (`docs-hygiene:compress`) and not structural skill lint
  (`skill-quality:check`).
- Not memory-layer hygiene — checks I1–I5 on CLAUDE.md/rules route to `claude-memory`'s `audit`
  skill when installed.
- Does not edit upstream-owned plugin-cache or managed materializations — those findings route to
  the owning repository.
