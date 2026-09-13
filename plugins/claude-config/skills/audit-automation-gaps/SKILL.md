---
description: "Audit a repo's Claude Code automation landscape, covering hooks, MCP servers, skills, subagents and scheduled tasks, against the enforcement hierarchy, producing PASS/REJECT/CONDITIONAL verdicts backed by evidence. The default verdict is REJECT because most gaps are already covered by compiler/analyzer/build-time checks. Use when: 'audit automations', 'what automations should we add', 'are we missing any hooks', 'hook gap analysis', 'should I add an MCP server for X'; pass --implement to apply approved items, or filter by category (hooks|mcp|skills|subagents|scheduled)."
argument-hint: "[--recommend-only] [--implement] [category]: hooks|mcp|skills|subagents|scheduled|all (default: all)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Audit the repo's automation landscape for hook, MCP, skill, and subagent gaps worth adding
---

## Pre-computed context

Automation inventory: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/scripts/inventory.sh" 2>/dev/null || echo "inventory unavailable"`

That block counts files present separately from handlers actually registered, and marks a scope it
could not read as `unreadable` rather than as zero. Treat it as a starting point, never as a
finding. Re-derive any count a verdict leans on, and where your own count disagrees with the block,
report both numbers and say which one the verdict used. A partial inventory that reads as complete
is this skill's own recorded failure: see [context/gotchas.md](context/gotchas.md).

## Purpose

Audit the repo's automation landscape and identify genuine gaps, not surface-level "you don't have X"
observations, but evidence-backed gaps where no mechanism in the enforcement hierarchy covers the
concern.

**Design principle**: most "missing automation" gaps are already covered by higher enforcement levels
(compiler, analyzers, build-time checks, architecture tests, behavioral rules). This skill's job is to
prove a gap exists before recommending a solution. The default verdict is REJECT, not PASS.

**The enforcement hierarchy** (strongest first): compiler settings → static analyzers/linters →
architecture tests → unit/integration tests → git hooks → Claude Code hooks → code review →
documentation/behavioral rules. A consuming repo that documents its own hierarchy in `CLAUDE.md` or
rules files overrides this default ordering, so read and use theirs.

## Boundary: no machine-readable hook enumerator

This skill ships no hook-enumeration mode, and the absence is a decision rather than a gap. The
native `/hooks` browser already reports the harness's own resolved set: it lists every event with a
count of the hooks configured on it, and selecting one "shows its details: the event, matcher, type,
source file, and command". A script here would restate that set from the settings files instead of
from the resolution the harness actually performs, which is the weaker source. Revisiting the
decision requires first recording a native-surface verdict for `/hooks` in whatever registry the
repository keeps for native-overlap decisions, because whether such a reference should exist at all
is a human's call. This paragraph is a boundary, not a routing verdict.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| `/hooks` opens a read-only browser listing every hook event with its configured count, and selecting a hook "shows its details: the event, matcher, type, source file, and command" | [Automate actions with hooks](https://code.claude.com/docs/en/hooks-guide), the hooks-browser step | 2026-09-13 | A re-fetch finds the browser no longer read-only, or showing a different detail set |

## Adapting to your environment (graceful degrade)

This skill is self-contained. Where a phase names an adjacent capability, such as a research skill, an
implementation-planning skill, a work-item tracker, or an outcome verifier, treat it as optional: if
your setup provides an equivalent, use it; otherwise follow the inline guidance, which stands on its
own. Adjacent skills cover neighboring questions: the sibling `audit` skill (are the config FILES
correct?) and the `audit` skill in the `claude-memory` plugin (is the instruction layer healthy?).

This skill proposes NEW automation. The inverse question, whether the automation already in place
still earns its carry cost, is owned by `/overengineering:audit`, whose evidence-earned-keep walk
treats every incumbent as a retirement candidate until evidence keeps it. Send a retirement question
there when the `overengineering` plugin is installed; when it is not, the **Already enforced** gate
still names the mechanism covering a concern, and any retirement observation is recorded in the
verdict for the human rather than acted on here.

## Arguments

Parse `$ARGUMENTS` for:

- **`--recommend-only`**: Run evaluation phases only, skipping implementation. Default behavior
- **`--implement`**: After presenting validated recommendations, implement user-chosen items sequentially
- **Category filter** (`hooks`, `mcp`, `skills`, `subagents`, `scheduled`): Limit to a specific automation type. Default: `all`

There is deliberately no `ci` category. Two skills own that ground. The `ci-lanes` layer of
`/overengineering:audit` walks the lanes already running and judges whether each still earns its
carry cost, and `/review:audit-enforceability` maps one review finding through its enforcement-rung
crosswalk to the cheapest rung that could catch it, a CI lane included. Route a CI concern to
whichever fits when the `overengineering` or `review` plugin is installed; when neither is, record
the concern in the verdict as out of scope and name its owner, rather than widening this audit's
categories.

## Track progress

For any deep-dive run (Phases 1-4), keep a phase checklist and tick each phase + every anti-noise
doctrine check as it completes, either in-response or by copying
`${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/templates/checklist.md` into wherever the consuming
repo keeps working task notes. Phase 4 is SKIPPED in default `--recommend-only` mode.

## Phase 1: Discover Candidates (Self-Generated)

Analyze the current automation landscape directly, with no external recommender dependency.

### 1.1 Inventory Current State

The pre-computed block already ran
`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/scripts/inventory.sh"`; re-run it directly
if that block is missing. It settles the per-scope hook-location counts, the component counts, and
the enablement inputs. It deliberately leaves three things to you: effective plugin enablement,
because `enabledPlugins` follows precedence rather than the merge that hook entries follow; the
contents of any frontmatter `hooks:` block, which it counts but does not parse; and plugins
installed on the machine from outside this repository. Then read:

| What | Source |
|------|--------|
| Hooks | Every hook location: user + project + local `settings.json` → `hooks`, managed policy settings when readable, each enabled plugin's `hooks/hooks.json`, and skill or agent frontmatter `hooks:`. Also record which hook EVENTS you considered: the documented event set is far wider than `PreToolUse` and `PostToolUse`, so a no-gaps hooks verdict has to name the events it examined, because an event nobody looked at cannot surface a candidate |
| MCP servers | `.mcp.json` + `settings.json` → `disabledMcpjsonServers` |
| Permissions | `settings.json` → `permissions` (deny/ask/allow) |
| Enforcement | Ecosystem-specific build config (`<root-build-config>`, e.g. `Directory.Build.props` for .NET, `pyproject.toml` for Python, `package.json` for TS/JS), `.editorconfig` (top 20 lines), any enforcement-hierarchy section in the repo's own instruction files |
| Codebase shape | File counts per language: `find . -name "*.cs" \| wc -l`, same for `.py`, `.ts`, `.sh`, `.ps1` |
| Incident history | `git log --oneline \| wc -l` for the denominator, then a `--grep` count for the concern. That count is a CEILING, never a frequency: read a sample before citing one, and carry the match count, the denominator, the sample size and what the sampled commits actually were into the verdict |

### 1.2 Gap Analysis

For each automation category, systematically check for gaps using the category-specific checklists in
[context/gap-analysis.md](context/gap-analysis.md): Hooks (formatter exists? fast enough? higher
enforcement already covers?), MCP Servers (configured? CLI equivalent? service in use yet?), Skills
(skill exists? frequency? simpler mechanism?), Subagents (value over hook/skill? isolation help?
plugin exists?), Scheduled (tracked in the repo's work-item tracker? Dependabot/CI covers? right
durability model?).

### 1.3 Generate Candidate List

Produce a numbered list of candidates with category and one-line rationale. Target **5-10 candidates**.
Cast a wide net, the quality gates will filter. Include borderline items; it's better to evaluate
and reject with evidence than to silently exclude.

## Phase 2: Deep-Dive Each Candidate

For each candidate, execute the evaluation workflow. **Batch the Explore phase** (read all configs
once), then evaluate candidates sequentially.

### 2.1 Explore (Local Codebase)

For each candidate:

- **Read the relevant config/code**: the specific files that would be affected
- **Check the enforcement hierarchy**: walk up from the weakest level (docs) to the strongest (compiler). Stop when you find coverage. Document which level covers it
- **Check incident history**: `git log --grep` for related problems, then read a sample of the hits.
  The count is a **ceiling**, the number of commits whose message mentions a word, not a count of
  incidents and not a frequency. Report the match count, the total commit count, the sample size
  read, and what the sampled commits actually were
- **Measure performance**: if the candidate involves a CLI tool as a hook, time it:

```bash
time <tool-command> 2>&1 | tail -5
```

Judge that measurement against the **consuming repository's own documented hook budget** where one
exists, and say which source the threshold came from. No upstream latency budget exists, so any
fixed number this skill supplies is a house rule and is labelled as one in the verdict. Note that
`PostToolUse` cannot block a tool call, so its cost is turn latency rather than a blocked call.
Budget-resolution ladder, per-event costs, the documented levers, and the dated upstream-fact
records: read [context/hook-timing.md](context/hook-timing.md).

### 2.2 Research (One Mandatory Batch, Then Conditional)

Research splits by who owns the fact, and the two halves are not optional in the same way.

**Mandatory: one batched docs fetch for harness mechanisms.** Any candidate whose mechanism is a
Claude Code surface gets its harness facts fetched before its verdict, however settled the local
evidence already looks. That covers hook event semantics and what each event can and cannot block,
`async` and `timeout` behavior, MCP server scope and configuration, and skill, agent or plugin
frontmatter fields. Collect every such question across every surviving candidate into ONE fetch
pass rather than one pass per candidate. The batch is mandatory because a docs pass routinely
changes the shape of a candidate that local evidence had already settled: a gate written as `exit 2`
on `PermissionRequest` reads as settled locally and is inert upstream, which no amount of local
reading surfaces.

**Conditional: facts the harness does not own.** Third-party tool performance, an ecosystem's
standard formatter, server stability and auth, known issues in a tool the candidate would run. Fetch
these only where the verdict turns on them.

**When a conditional fetch is skipped, record how the fact was settled** in that candidate's
verdict: the measurement taken, the file read, or the existing dated record relied on. "Not needed"
and "not done" must stay distinguishable in the artifact.

Group related queries to minimize agent count, and run the mandatory batch as one dispatch for all
candidates rather than one per candidate.

**Per-candidate research questions by type:**

| Type | Research Questions |
|------|-------------------|
| **Hook** | Tool per-file performance? Ecosystem standard formatter? Known hook compatibility issues? |
| **MCP Server** | Server stability? Auth requirements? CLI equivalent comparison? Known issues? |
| **Skill** | Existing solutions? Frequency justification? Similar skills in marketplaces? |
| **Subagent** | Can a hook/skill do this more deterministically? Is context isolation needed? |
| **Scheduled** | Platform requirements (CLI vs Desktop vs cloud)? Durability model? Existing coverage via Dependabot/CI/work items? |

Verify Claude Code mechanisms against official docs
([code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks),
[code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp)); use web search for tool
performance and community practices. Research agents gather evidence and state no verdict; the
gates in 2.3 read that evidence and decide.

### 2.3 Vet / Validate (Quality Gates)

A candidate **fails** if ANY gate triggers.

**Run this gate in a fresh context.** Phase 1 generated these candidates in the context now being
asked to refuse them, and a context that produced work is a biased judge of it. Dispatch a
fresh-context subagent, handing it the candidate list, the Phase 2.1 and 2.2 evidence, and this
table, and keep the gate results it returns. Where the environment exposes no subagent surface, run
the gates inline and say in the report that the refusal gate ran in the same context that generated
the candidates, so the bias is visible rather than assumed away.

| Gate | Condition | Evidence Required |
|------|-----------|-------------------|
| **Already enforced** | A higher enforcement hierarchy level covers it, and the shift-left carve-out below does not apply | Name the level and mechanism; where the candidate claims the carve-out, the result of each of its three conjuncts |
| **Too slow** | Measured cost exceeds the resolved budget ([context/hook-timing.md](context/hook-timing.md)) for the event's actual cost: a blocked call on a blocking event, turn latency on `PostToolUse`, which never blocks | Timing measurement + the budget it was judged against and that budget's source |
| **Not scriptable** | The mechanism can't be automated with available tools | Specific limitation cited |
| **Zero incidents** | A read sample of the matching commits shows the problem has never occurred. A `--grep` count alone never triggers this gate, in either direction | Keyword match count, total commit count, the sample size read, and what the sampled commits turned out to be |
| **Already exists** | A skill, behavioral rule, or convention already handles it | File path and line |
| **YAGNI** | Low frequency (<5% of commits) AND low severity, where the frequency is sampled rather than counted | The match count over total commits as the ceiling; plus a sampled frequency whenever that ceiling is 5% or higher, and none when it is already below |
| **Platform mismatch** | Requires infrastructure the user doesn't have | Platform requirement cited |
| **Premature** | Depends on unfinished work (planned database, future CI) | What's missing cited |

#### Incident counts are ceilings

**Zero incidents** and **YAGNI** both read a `git log --grep` count, and that count is an upper
bound on the concern, not a measure of it: it counts commits whose message mentions a word. On this
marketplace at merged main `49912c63`, `secret|gitleaks` matched 209 of 2202 commits while the first
15 read were dependency bumps, component syncs and CI pins, with no leaked secret among them, and
`markdownlint|lint` matched 1128, about 51%. Cite a frequency only after reading a sample and saying
what the sampled commits were.

The discipline is asymmetric, which keeps it cheap. A ceiling already below the 5% **YAGNI**
threshold settles that gate on its own, because the true frequency cannot exceed the ceiling, so no
sample is needed. Only a PASS, or an affirmative claim that the concern is frequent, has to pay for
one.

#### Shift-left carve-out to Already enforced

A candidate that deliberately duplicates a check a higher rung already runs, at edit time, is not
rejected by **Already enforced** alone. Duplication earns a hearing only when all three conjuncts
below hold, each stated with its evidence. Any conjunct that cannot produce its evidence fails, and
the candidate returns to REJECT. The carve-out changes which gate decides, never the REJECT-by-
default posture: a candidate that clears all three is handed to **Too slow** and the remaining
gates, not passed.

1. **Sampled frequency, never incident history.** The concern clears **Zero incidents** and
   **YAGNI** on a count sampled from the current tree, not from `git log`. A check the higher rung
   already runs suppresses its own incidents, so zero incidents in history is evidence about the
   incumbent check, not about the concern. Sample instead: run the check over a stated N of files
   or of recent edits and report hits over that N. Falsified when the sampled hit rate is under
   5 percent and severity is low, which is the **YAGNI** threshold read against the sampled
   denominator.
2. **Advisory and non-blocking.** The hook exits `0` on every path, surfaces findings as context
   rather than rejecting the edit, and its own documentation names a commit hook or a CI lane as
   the hard gate. Falsified by any exit path that blocks the tool call, or by documentation
   presenting the hook itself as the gate.
3. **Fits the remaining budget, as a hard gate.** Resolve the budget through the two-rung ladder in
   [context/hook-timing.md](context/hook-timing.md), then report four things: the measurement, the
   budget row judged against, which rung supplied it, and the headroom arithmetic. Falsified when
   the measured cost exceeds the stated headroom. Where the consuming repository documents a budget
   and its own accounting records no headroom on that row, the verdict is REJECT at **Too slow**
   whatever conjuncts 1 and 2 returned; the carve-out does not reopen a budget the consumer says is
   already overspent.

Why the carve-out is scoped this narrowly: the hooks documentation states that hooks give
"deterministic control: certain actions always happen rather than relying on the LLM to choose to
run them", which supports duplicating a check so it runs on every edit without exception. It states
nothing about where a check belongs, in CI or in a hook, so no latency or placement argument may be
offered as an upstream one. The record for both facts:

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Hooks exist to give deterministic control, so certain actions always happen rather than relying on the LLM to choose to run them | [Automate actions with hooks](https://code.claude.com/docs/en/hooks-guide), opening paragraph | 2026-09-13 | A re-fetch finds the opening statement of purpose no longer matching this row |
| No official page addresses whether a check belongs in CI or in a hook | Absence record in [context/hook-timing.md](context/hook-timing.md), upstream-fact records | 2026-09-12 | That record's own trigger fires |

These gates answer *should* we mechanize. Whether a candidate *can* be, and how far up the hierarchy
it climbs, is a separate enforceability question: the **Not scriptable** gate maps to concerns no
hook type reaches, **Already enforced** to a deterministic finding already escalated. `prompt` and
`agent` hooks do evaluate reasoning-only concerns, `agent` experimentally.

Produce a verdict per candidate:

- **PASS**: clears all gates, provides genuine value
- **CONDITIONAL**: value exists but only under specific conditions (document the condition)
- **REJECT**: fails one or more gates (cite which gates and evidence)

## Phase 3: Present Results

### Summary Table

```markdown
| # | ID | Candidate | Category | Verdict | Key Evidence |
|---|----|-----------|----------|---------|--------------|
| 1 | h1 | ... | hooks | REJECT | [gate]: [evidence] |
| 2 | s1 | ... | skills | PASS | No existing coverage, [n] of [total] commits, [k] sampled |
```

`ID` is a short stable token for the candidate, and `Category` is one of `hooks`, `mcp`, `skills`,
`subagents`, `scheduled`. Both are what the persisted artifact is keyed and filtered by, so a row
without them cannot be written back or read by `--implement`.

### Detailed Verdicts

For each candidate, provide:

- **Verdict** with gate results
- **Evidence** (timing data, git history counts, enforcement mechanisms found)
- **For PASS/CONDITIONAL**: implementation plan (files to change, effort estimate, test strategy).
  A `PASS` or `CONDITIONAL` without a plan cannot be persisted, because the plan is precisely what
  `--implement` reads back in a later session

**Order by value/impact**, highest value first. Value = frequency × severity × ease of implementation.

### Maturity Assessment

End with a one-paragraph assessment of the repo's automation maturity: what's well-covered, what the
genuine gaps are (if any), and whether the current automation investment level is appropriate for the
project stage.

If items pass: "Which items would you like to implement? I'll work through them sequentially."

If no items pass: State that clearly. A clean bill of health is a valid outcome.

### Persist the findings

Write the run before the session ends, so a later `--implement` has something to read:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/scripts/findings-state.sh" write \
  --plugin-data "${CLAUDE_PLUGIN_DATA}" --findings <file-or-->
```

`${CLAUDE_PLUGIN_DATA}` substitutes here in the skill text but is absent from the Bash tool's own
environment, so it has to travel as that argument; the script exits 2 rather than guessing when it
is missing. The payload is exactly one JSON object with a `candidates` array, each entry carrying
`id`, `candidate`, `category`, `verdict`, an `evidence` array, and a `plan` object on any `PASS` or
`CONDITIONAL`. A malformed payload, or a stream carrying more than one document, exits 3 and writes
nothing, listing every problem at once.

Writes are all or nothing. A run id already taken is reserved under the next free suffix rather than
overwritten, so two runs racing for one id both survive and each is told the id it actually got.

Findings are keyed per project, so one checkout never reads another's verdicts. This tree is the
only durable copy: uninstalling the plugin without `--keep-data` deletes it.

## Phase 4: Implement (if `--implement` or user requests)

Recover the prior run's verdicts first, rather than re-deriving them:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/scripts/findings-state.sh" read \
  --plugin-data "${CLAUDE_PLUGIN_DATA}"
```

That serves this project's newest run. Exit 4 means this project has no stored run, which is the
cue to audit first rather than to implement from memory; the script never falls back to another
project's artifact. Exit 5 is the different answer: stored state exists but cannot be trusted,
because a file is unreadable or a previous write half landed. Treat 5 as a state to repair or
re-audit, never as an absence, and say which of the two you got. `list` shows the earlier runs when
a specific one is wanted.

For each user-selected item:

1. **Explore**: re-read current state (may have changed since evaluation)
2. **Research + Validate**: verify the implementation approach against current docs. The audit
   already ran one batched fetch for Claude Code surfaces in Phase 2.2, so re-fetch only what the
   stored evidence does not already settle, or what has plausibly moved since the run was written
3. **Plan**: detailed implementation steps
4. **Implement**: execute with incremental validation and commit checkpoints
5. **Test**: verify the automation works (run hooks, test skills, etc.)
6. **Review**: dispatch a fresh-context reviewer to check the change against existing patterns,
   since the context that wrote it is a biased judge of it. Where no subagent surface exists,
   review inline and record that the review was same-context
7. **Verify**: build/test the repo if code changed, confirm no regressions

Route steps 2-7 through the consuming environment's own workflow skills when it has them; the inline
steps stand on their own otherwise.

## Quality Principles

Principles that govern every verdict:

1. **The enforcement hierarchy is your first check.** Most "gaps" are covered by the compiler-through-git-hooks levels
2. **Measure, don't assume.** Time every tool before recommending it as a hook. A formatter looks perfect until you measure 15+ seconds per file
3. **Check incident history, then read it.** Zero incidents across 100+ commits is strong evidence the problem doesn't exist in practice, but a `git log --grep` count is a ceiling on the incidents, not a count of them, and a check a higher rung already runs suppresses its own incidents
4. **Behavioral rules are valid enforcement.** A rule in CLAUDE.md is legitimate coverage; not everything needs a hook or script
5. **YAGNI is a quality gate, not laziness.** Automation for a task at 4% frequency is premature
6. **Premature is worse than missing.** Adding a database MCP before a database exists, or scheduling before CI exists, creates maintenance burden for zero value
7. **A clean bill of health is a valid outcome.** Not finding gaps means the automation is mature; don't manufacture recommendations to justify the audit

## Next

- Candidates passed and are ready to build: `/planning:plan`.
- Candidates passed and need slicing into grabbable tickets first: `/work-items:decompose`.
- The run raised a question about automation already in place: `/overengineering:audit`.
- A verdict is worth revisiting later rather than acting on now: `/work-items:track add`.

## Gotchas

Five failure modes this skill has actually produced, each with the evidence and the dated upstream
records behind it: a partial inventory anchoring every later verdict, keyword counts read as
frequencies, `PostToolUse` candidates phrased as gates, an `exit 2` gate on `PermissionRequest` that
is silently inert, and a candidate generator that reaches three of the 33 documented hook events.
Read [context/gotchas.md](context/gotchas.md) before any run whose verdicts a human will act on.
