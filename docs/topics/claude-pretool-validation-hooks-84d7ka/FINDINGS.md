# PreToolUse validation and blocking hooks: findings

Read-only audit. Nothing filed, nothing changed. Branch `claude/pretool-validation-hooks-84d7ka`.

Authority for every harness claim below is a raw fetch of `code.claude.com/docs/en/hooks.md`
(317 KB, fetched 2026-09-04), not a summarizer. Two claims that a summarizing fetch got
backwards are flagged where they appear.

## Scope

17 distinct guard scripts across 10 PreToolUse hook entries in 5 plugins.

| Plugin | Matcher(s) | Guards | Decision channel |
|---|---|---|---|
| guardrails | `Write\|Edit\|MultiEdit\|NotebookEdit`; `Bash\|PowerShell`; `Workflow` | 11 (3 + 8 + 1, one shared) | `exit 2` + stderr, via `run-guards.sh` |
| source-control | `Bash` (2 `if:` rows); `^mcp__github__(create\|update)_pull_request$` | 3 | `exit 2` + stderr |
| disk-hygiene | `Bash` (`if: Bash(*hygiene.py*)`); `PowerShell` (no `if:`) | 1 | JSON allow/ask/deny, `os._exit(2)` fail-closed |
| context-guard | `Write\|Edit\|NotebookEdit\|Agent\|Workflow` | 1 | JSON `deny` |
| context-budget | `Write\|Edit\|MultiEdit\|NotebookEdit` | 1 | JSON `ask` |

---

## Part 1: Four premises corrected before the findings

### 1.1 Auto mode is an argument FOR these gates, not against

Verbatim from the PreToolUse decision-control section:

> A hook's `"ask"` also forces a permission prompt in auto mode: the classifier can still deny
> the tool call, but it can't approve the call silently.

PreToolUse hooks fire in every permission mode. Auto mode removes the human from the loop that
would otherwise catch a bad call, so a policy deny-gate is *more* load-bearing under auto mode,
not less. `context-budget`'s `settings-write-ask.mjs` exists for exactly this reason and its
header says so.

The correct read: auto mode is a reason to delete **behavioral** guards (both the model and the
classifier now get it right) and a reason to keep **policy** deny-gates.

**Measured confirmation from the prompt-hooks lane.** That session ran a dedicated wave mapping
every blocking guard against the live auto-mode classifier default-block list. Its headline:
**zero guards rate FULL coverage; the best rating is PARTIAL.** I have not reproduced this
measurement, so it is attributed, not asserted. Its findings:

- Gating only the classifier-covered guards takes the PreToolUse Bash lane from 145 ms to
  115 ms. The classifier covers the *cheap* guards, not the expensive ones.
- Gating the whole lane reaches 0.98 spawn-equivalents but discards six guards nothing replaces.
- **The structural reason they are not interchangeable:** classifier verdicts are
  *intent-clearable*, since the documented rules repeatedly clear on "unless you named the
  target / named the execution effect". Hooks are deterministic. Even where the category
  overlaps, one does not substitute for the other.
- `secret-pattern-detection` is PARTIAL in a precise and important way: the classifier covers
  the **egress** moment (commit, push, PR body) and never sees the **write** moment. The hook is
  the only thing watching a secret land on disk.
- `block-dangerous-git` PARTIAL. `block-hook-bypass`, `block-noncanonical-commit`,
  `block-convention-violation`, `hardcoded-path-check`: **NONE**.

Practical conclusion: **do not gate guards on `permission_mode == "auto"`.** The saving is small,
the coverage is partial everywhere and absent in most places, and the two mechanisms answer
different questions.

### 1.2 `classifierContext` is not available on PreToolUse

A sibling session proposed converting deterministic blocks into auto-mode classifier hints via
`classifierContext`. The field is real (v2.1.236+) but it is a **PostToolUse** field. The
PreToolUse decision-control table has exactly four fields:

| Field | Notes |
|---|---|
| `permissionDecision` | `allow` / `deny` / `ask` / `defer` |
| `permissionDecisionReason` | For `allow` and `ask`, shown to the user **but not Claude**. For `deny`, shown to Claude. For `defer`, ignored |
| `updatedInput` | Replaces the **entire** input object. Permission rules and auto-background eligibility are re-evaluated against the hook's returned input |
| `additionalContext` | Added to Claude's context alongside the tool result |

There is no PreToolUse path to the auto-mode classifier. That direction is not available here.

### 1.3 `--include-hook-events` is real; our doc is correct. RESOLVED against two dissents.

**Two** sibling sessions independently reported that `docs/conventions/hook-observability/README.md`
cites a flag that does not exist. Both checked only `hooks.md`, where it is genuinely absent. It is
documented in the **CLI reference**, re-verified after the second dissent (HTTP 200,
`cli-reference.md`, 108,577 bytes, one occurrence):

> `--include-hook-events` Include hook lifecycle events in the output stream. `SessionStart` and
> `Setup` hook events are always included and don't need this flag. [...] Requires
> `--output-format stream-json`

Our convention doc is accurate at lines 175 and 180. **No finding.** Two sessions were about to
file it; both have been told. The generalizable lesson: a flag absent from `hooks.md` is not a
flag that does not exist, and `hooks.md` is not the CLI surface's authority.

### 1.4 "Hooks ship in their own plugin" is a new policy, not an existing one

Stated as existing policy in conversation. It is not documented anywhere, and the de facto
standard is the opposite: **20 of 20 hook-carrying plugins ship hooks alongside skills.**
`source-control` has 7 skills plus 6 hooks; `claude-ops` 12 skills plus 8 hooks; `session-flow`
14 skills plus 1. Even the formatter plugins are hooks plus a setup skill.

Treated below as a proposal to cost, not a rule to audit against. See Part 6.

---

## Part 2: The unhobbling pass

This repo already owns the rubric. `docs/PLUGIN-PHILOSOPHY.md` § **Classifying a hook** scores
every wired hook on **Mechanism** (deny-gate / context-injection / deterministic-transform /
notification) and **Class** (policy / behavioral / hybrid), with the rule that policy survives
ablation and behavioral is a candidate. It was applied across all 44 wired hook entries in the
2026-08 audit (#2021). This is a **generation-triggered re-run** of that rubric, which the doc
itself mandates at each frontier release.

Two guardrails in the rubric kill most naive deletions:

- **The non-derivable-oracle carve-out.** A hook with a behavioral purpose but ground truth no
  model can know unaided is a keep. "It corrects the model" is never the delete criterion; "the
  model could derive this itself" is.
- **The security carve-out.** "Model-capability claims never relax the security posture."

### What these verdicts are, and what they are not

A peer made a correction that applies to this whole section, so it belongs before the table
rather than in a footnote.

I told the justify-existence lane that its class-based *defence* of `block-hook-bypass` was
unproven, because ADR 0003 clause 4 requires the oracle-versus-scope call to be established
**by checking, per finding**, and four anecdotes are not that. It accepted, then pointed out
that the same standard cuts at me: **a defence and a retirement are symmetric claims.** Both
assert what the evidence shows. Four anecdotes are four anecdotes whichever direction they
point.

That is correct, and it bounds this report:

- **Every verdict below is a CLASS judgment, not a MEASURED one.** They apply the
  Mechanism × Class rubric to what each guard is for. Exactly one guard
  (`block-hook-bypass`) has any real firing data at all, and four sessions is a signal rather
  than the sweep ADR 0003 requires.
- **So the KEEPs are exactly as unproven as the DELETEs.** Not one of the 17 has a measured
  precision on the current corpus. A KEEP here means "this is the class of thing that survives
  ablation", never "this has been shown to earn its cost."
- **The two gates are independent and must not be fused.** The ablation rubric decides whether
  a guard's *purpose* survives a model generation. ADR 0003 clause 3 decides whether anything
  ships *default-on*, and it carries no class exemption. Passing the first says nothing about
  the second. Fusing them is precisely the error that produced my over-escalation and the
  peer's over-defence, in opposite directions, from the same four data points.

Read the table as a triage that says where to look, not as a set of conclusions that justify
action on their own. Anything in the DELETE or WITHDRAW rows should carry its own evidence
before it moves.

### Verdicts

| Guard | Class | Verdict | Rationale |
|---|---|---|---|
| `secret-pattern-detection` | policy | **KEEP** | Security carve-out. Not negotiable on model capability |
| `block-dangerous-git` | policy | **KEEP** | Irreversibility protection. `--force-with-lease` reasoning is a checkable invariant, not a competence guess |
| `block-no-verify` | policy | **KEEP** | "Git hooks must run" is a team invariant you keep with a perfect model |
| `pr-body-linkage-gate` | policy | **KEEP** | Mirrors a required CI check, scope-keyed to the consumer's own workflow file. Saves a CI round trip. Oracle is the gate file's presence, non-derivable |
| `pr-linkage-mcp-gate` | policy | **KEEP** | Same, on the MCP surface |
| `worktree-add-containment-gate` | policy | **KEEP** | Nesting invariant, measured: 9 of 292 worktrees nested (#2611) |
| `settings-write-ask` | policy | **KEEP** | The auto-mode countermeasure. Strengthened by 1.1 |
| `destructive_guard` (engine-gate) | policy | **KEEP** | Fail-closed allowlist on a destructive engine |
| `zone-gate` | policy | **KEEP** | Already defaults to `advisory`; the deny path is opt-in |
| `block-convention-violation` | policy | **KEEP, gate earlier** | Correct as policy, but inert without a configured pattern (line 245) while still paying full spawn and library parse. Config-presence check belongs at the top |
| `block-noncanonical-commit` | hybrid | **TRIM** | 991 lines. The multi-line `-m` block is a real data-loss invariant (`-m` flattens newlines) and stays. The broader "canonical `-F -` form" requirement is model-correcting convention that Opus 5 and Fable 5.1 satisfy unaided |
| `hardcoded-path-check` | hybrid | **TRIM** | Portability invariant is policy; the "model hardcodes `/Users/foo`" predicate is behavioral |
| `block-hook-bypass` | hybrid | **WITHDRAW FROM DEFAULT-ON SCOPE, RE-FILE FOR RESCOPING** | ADR 0003's own vocabulary. Escalated from TRIM, then moderated back from "likely delete" on a peer's counter-argument. See below |
| `block-windows-drive-tmp` | behavioral | **EVIDENCE-GATE** | Classic prior-model failure. But the Git Bash drive-root mapping is arguably a non-derivable platform quirk. Do not delete on assertion; needs the ablation ledger |
| `block-exported-msys-pathconv` | behavioral | **EVIDENCE-GATE** | Same bucket, same reasoning |
| `flag-commit-pr-skill-bypass` | behavioral | **DELETE** | Pure model-correcting nudge. Already `default=false` since #2021, AND `git commit` is deliberately excluded at line 29 (block-noncanonical-commit owns it, to avoid double-firing). What remains is an off-by-default advisory scoped to `gh pr create` alone. Textbook ablation candidate |
| `workflow-resilience-check` | behavioral | **DELETE** | Advisory, `default=false`, model-correcting |

### `block-hook-bypass` is the standout, and the evidence got much stronger

Three independent sessions reported firings of this guard **today**, all false positives:

| Session | Blocked | Legitimate? |
|---|---|---|
| PostTool lane | `cat > <file>` into the harness-designated scratchpad | Yes. This environment's system prompt instructs agents to use it |
| Prompt-hooks lane | Two benign scratch writes, one triggered by text that merely **quoted the guard's own scope note** | Yes |
| Justify-existence lane | Heredoc write to `.work/justify-existence/`, the repo's untracked memory tier | Yes. Written by every `/planning:*` skill in the marketplace |

**Four observed firings, zero true positives**, across three sessions that were not looking for
this. Root cause is configuration: `block_hook_bypass_scratch_roots` defaults to empty, so
neither the harness scratchpad nor `.work/` is exempt out of the box.

Corroborates open issue
[#3689](https://github.com/melodic-software/claude-code-plugins/issues/3689).

**This repo already has an ADR that governs exactly this situation.**
`docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md` (accepted
2026-07-25) exists because a guard with a sound oracle was built, tested to 61 contract cases,
reviewed, and then withdrawn on measurement: 231/975 files firing, 389 findings, **0 true
positives**. Its decision:

> A verification guard does not ship default-on until its firing rate and precision have been
> measured against a real corpus. A sound oracle is a necessary condition, never a sufficient
> one. [...] **A guard that fires and is never right disqualifies itself**, however sound its
> oracle. The disqualifying condition is **observed false positives with no true positive**.

That is the pattern we now have. **One honest caveat:** ADR 0003 is scoped to *verification
guards*, which are PostToolUse advisories, and `block-hook-bypass` is a PreToolUse deny-gate.
The precedent does not transfer automatically. But two things make it apply here anyway:

1. **The cost asymmetry is inverted for this specific guard** (PostTool lane's argument, which
   I find correct). Every PostToolUse `Write|Edit` hook it protects is advisory and exits 0. So
   a successful bypass costs a missed formatting pass, while a false positive costs a blocked
   tool call plus rework. It is a deny-gate protecting advisories.
2. **The guard's own header disclaims its adversarial value**: "An LLM never emits this form;
   the deny-list plus human oversight are the adversarial layers." That is an unmeasured claim
   about model behavior, which is precisely what the Part 2 rubric calls an ablation candidate.

#### The counter-argument, and why it changes the remedy but not the verdict

The justify-existence lane, which supplied one of the four firings, sent an argument *against*
its own evidence. Paraphrased: this is a deny-gate whose class is arguably **policy**, since its
predicate is a checkable invariant (is this shell command a file write routing around the
Write/Edit tool) rather than a guess about model competence. Under "Mechanism never implies
class" and the durable-tier exemption, a policy deny-gate survives ablation, and precision
complaints are an argument for **narrowing**, not deletion.

I checked this against ADR 0003 rather than accepting or dismissing it. **Both positions are
right, about different clauses**, and the ADR resolves them cleanly:

- **Clause 3 disqualifies the current configuration.** Verbatim: "fires at all, no true positive
  | **disqualified**. Precision is 0% whether the firing count is 389 or 1 [...] a single false
  finding with no real one fails identically." Four firings, zero true positives, is the
  disqualifying pattern exactly. Scarcity is explicitly ruled out as a defence: "Scarcity changes
  the volume of noise, never its ratio."
- **Clause 4 decides the remedy, and it favours the counter-argument.** Verbatim: "Distinguish
  'wrong oracle' from 'wrong scope' — by checking, not by assuming. That distinction decides
  whether a guard is **deleted or re-filed for rescoping**." The path guard, the ADR's own
  motivating case, was withdrawn **and re-filed (#1314)**, not deleted.

Here the oracle is sound. `cat > file` genuinely does route around Write/Edit. What is wrong is
the scope: it should not care about the harness scratchpad or `.work/`. That is a scope defect,
which the ADR re-files rather than deletes.

So I am moderating my own escalation. "Likely default-off" overshot; the accurate verdict in the
ADR's own vocabulary is **withdraw from the current default-on scope and re-file for rescoping**.
Credit to the peer for arguing against evidence it had itself supplied.

**Recommendation, in order:**

1. **Ship the scratch-root default now**, independently of everything else: a non-empty default
   for `block_hook_bypass_scratch_roots` covering the harness scratchpad and `.work/`, landed
   **repro-first** per `docs/conventions/hook-precision` (a MUST-stay-quiet case that fails
   against the unmodified hook).
2. **Then run the ADR 0003 sweep.** Four sessions is a signal, not a sweep. Clause 1 requires the
   deployment surface, and clause 4 requires the oracle-versus-scope call to be established **per
   finding, by checking**, the way the path guard's candidates were each re-tested. Report firing
   rate and precision in the PR (clause 2), and name the precision ratio you consider acceptable
   for this surface, since the ADR deliberately fixes no threshold.
3. One ADR detail worth carrying: if the rescoped guard then fires **zero** times, that is
   *undefined* precision, not zero, and the burden shifts to **seeded defects**. Plant instances
   it should catch, confirm it catches them, report the unseeded rate as the noise figure.

---

## Part 3: Schema alignment

### 3.1 Two protocols coexist, and both are correct

I expected to file this. The docs settle it:

> A hook that blocks by exiting 2 routes the same way as `"deny"`: Claude sees the stderr message
> as the denial reason.

`exit 2` + stderr and JSON `deny` are equivalent. Not a finding. Consistency for its own sake
would be churn.

### 3.2 The dispatcher's precedence already matches the spec

Documented: `deny` > `defer` > `ask` > `allow`. `run-guards.sh:emit_one` picks block/deny first,
then ask, else first. That is the documented order minus `defer`, which nothing emits. Correct
today; worth a comment noting the dependency.

### 3.3 Unused fields worth evaluating

| Field | Fleet usage | Assessment |
|---|---|---|
| `updatedInput` | **zero** | The real opportunity. Turns two TRIM verdicts into corrections instead of blocks: `block-noncanonical-commit` could rewrite `-m` into `-F -`; `block-windows-drive-tmp` could rewrite the path. **Caution:** replaces the *entire* input object, and permission rules are re-evaluated against the rewritten input. Silently changing a user's command is a real posture change that needs its own decision |
| `permissionDecision: "defer"` | **zero** | No obvious fit in this fleet |
| `async` / `asyncRewake` | **zero** | Fits the two advisory checks that never block, but both are DELETE candidates anyway. Low value |
| `args` exec form | 1 of 10 rows | Only `context-budget`. The rest use shell form, which `scripts/check-hook-exec-form.sh` already governs. Fine as-is |
| `http` / `prompt` / `agent` / `mcp_tool` handler types | **zero** | The hook-budget program deliberately kept everything `type: command`. Leave it |

### 3.4 The reason-visibility asymmetry

`permissionDecisionReason` is shown **to the user, not Claude**, for `allow` and `ask`. Both
`ask`-emitting hooks write long reasons that read as though addressed to Claude.
`settings-write-ask.mjs` in particular explains what the agent should verify. That text never
reaches the agent. Either shorten it for a human reader, or pair it with `additionalContext`,
which does reach Claude.

Related and useful: an `ask` prompt already labels its source as `[plugin:<name>]`, so plugin
attribution in the prompt is free.

---

## Part 4: Fail-fast, extensibility, visibility

### 4.1 Disabling a guard does not currently make it free

Every guard's kill switch is a one-line env read, but it fires **after** the library is parsed:

```
block-dangerous-git.sh:66      source hook-utils.sh          # 2,766 lines
block-dangerous-git.sh:68      hook::check_enabled "BLOCK_DANGEROUS_GIT"

secret-pattern-detection.sh:24 source hook-utils.sh
secret-pattern-detection.sh:32 source secret-patterns.sh     # a second library
secret-pattern-detection.sh:34 hook::check_enabled "SECRET_PATTERN_DETECTION"
```

`hook::is_enabled` is `[[ "${!var_name:-true}" == "true" ]]`. Nothing about it needs the library.

The sibling lane measured this independently on Linux (spawn floor S = 2.1 ms, N = 15 to 20): a
hook with its switch off costs **5.5 to 6.1 ms against a 2.1 ms floor**, because the 2,766-line
library parse (4.2 ms, about 1.85 S) happens first. Same ordering defect confirmed in
`markdown-format` (source@38, check@40), `typos-format` (87/89), `eol-normalizer` (34/38).

Hoisting a two-line env read above the `source` recovers roughly 2 S per disabled hook across
about 44 switch sites. Mechanical, low-risk, and it is what makes "disable costs nothing" true.

The prompt-hooks lane measured the same defect at fleet scale and put a number on the fix:
**43 of 43 hooks that have both** place `hook::check_enabled` after the `source`. Spawn floor
1.95 to 2.2 ms; spawn plus source 6.3 to 7.3 ms. Today, disabling a hook buys about **15%** of
its cost; after hoisting a raw
`[[ "${CLAUDE_PLUGIN_OPTION_<N>_ENABLED:-true}" == "true" ]] || exit 0` above the source line,
about **75%**.

Two things that fall out of it, both worth carrying into the change:

- **It needs a CI gate, not just a fix.** `scripts/sync-hook-utils.sh` covers the vendored
  library but not the entry scripts, so nothing prevents the next author from reintroducing the
  ordering. A `scripts/check-killswitch-hoist.sh` belongs with the change. This repo has the
  precedent: `check-hook-exec-form.sh` exists because that class shipped three times.
- **The parse is mostly comments.** The comment-removal lane measured `lib/hook-utils.sh` at
  2,684 non-blank lines of which **1,135 (42%) are whole-line comments**, byte-identical across
  **18** locations (17 plugin copies plus `lib/`; that lane self-corrected from 19 after its
  grep matched `sync-hook-utils.sh`). If parse cost tracks bytes, 42% of what every hook process
  parses on every fire is comment text. That does not make the comments deletable, since they
  are decision records, but it does mean a structural split and the hoist attack the same cost
  from two directions. One discipline that lane offered against its own interest, worth keeping:
  "comments cost parse time" is a defensible performance argument; "comments cost comprehension"
  is not, since the eye-tracking literature it cites finds no population-level effect in either
  direction. Keep the two separate and the performance case is stronger.

**The structural limit:** even hoisted, a disabled standalone hook still pays a process spawn,
because the switch is read *inside* the hook. The only zero-cost gates are harness-side: the
`if:` field, or disabling the plugin.

### 4.2 Kill-switch coverage is good, with two gaps

Every guardrails guard and every source-control gate has a `*_enabled` boolean, `default=true`,
read through the `CLAUDE_PLUGIN_OPTION_*` hook mirror, plus tuning seams
(`block_dangerous_git_allow`, `block_hook_bypass_scratch_roots`, `block_noncanonical_commit_allow`).

Gaps: **disk-hygiene** and **context-guard** each expose one plugin-wide switch rather than
per-hook control.

### 4.3 Visibility

8 of 10 rows carry `statusMessage`. Both misses are **disk-hygiene**, and one is the row that
fires on **every PowerShell call** with no `if:` narrowing. That row runs a Python interpreter
(190 to 300 ms measured per call) with no spinner text. It is precisely the "I never notice hooks
are running" complaint, on the most expensive uninstrumented row in the fleet.

The `if:`-less PowerShell row is **deliberate and documented** (a PowerShell filter must match
every subcommand of a compound line, so it would skip the guard silently on a mixed line). The
missing `statusMessage` is not documented and looks like an oversight.

#### A second visibility surface the fleet uses nowhere: `description` on `hooks.json`

Passed over by the metrics lane, unverified there, verified here: **20 of 20 plugin
`hooks/hooks.json` files omit a top-level `description`.** The field is documented
(`hooks.md` line 631):

> Define plugin hooks in `hooks/hooks.json` with an optional top-level `description` field. When
> a plugin is enabled, its hooks merge with your user and project hooks.

It is **optional**, so omitting it is not a defect and this is not a bug report. But it is
directly on point for "I never notice hooks are running unless they error": `statusMessage`
tells you what a hook is doing *while it runs*, and `description` is the standing answer to
*what does this plugin's hook set even do*. Adding twenty one-line descriptions is the cheapest
visibility improvement available in this whole report, and it touches no guard logic.

---

## Part 5: Performance

Owned by [#3685](https://github.com/melodic-software/claude-code-plugins/issues/3685). Contributed
as evidence, not as a parallel plan.

- **`if:` is the cheapest unused lever.** 6 of 10 rows carry no `if:`. It is evaluated harness-side
  before the spawn, so a non-matching row costs nothing. Four of the eight Bash guards
  (`block-no-verify`, `block-dangerous-git`, `block-noncanonical-commit`,
  `block-convention-violation`) only care about `git` and `gh`. **Trade to measure, not assume:**
  splitting the dispatcher into `if:`-keyed rows costs two spawns whenever both rows match, so the
  win depends on the git-to-non-git ratio of real Bash traffic.
- **The kill-switch hoist in 4.1** is a second, independent win that #3685 does not currently cover.
- Budget context: ceiling is 1 s typical per tool call; measured PreToolUse Bash is 1,599 ms and
  Edit 2,062 ms on a quiet host, roughly 7 to 9 s scaled to the Windows reference host. Every
  DELETE and TRIM verdict in Part 2 is also a performance change.

**Caveat on those scaled figures, raised by the prompt-hooks lane and not yet adjudicated.** It
argues the hook-budget doc's spawn-equivalent method only survives a host change for
*spawn-dominated* hooks. Work-dominated ones (it measures `markdown-format` at 35 ms/exec,
`context-budget` at 39 ms/exec) have near-constant absolute cost, so the doc's "at S = 80 ms"
column overstates them by roughly 40x. It also reports that the doc's attribution of the residue
to "each guard sourcing the library and building its telemetry data" is measurably wrong, since
the library is sourced once per dispatcher process and telemetry costs nothing unless
`HOOK_TELEMETRY_SINK` is wired, which this repo's own environment does. If that holds, the
doc's reference figures measure a wired sink while describing the default.

I have not reproduced any of this. Flagging it because **this report cites those figures**, and
if the method is wrong the scaled column is the part to distrust, not the on-host measurements.
Whoever owns `docs/conventions/hook-budget` should adjudicate it; that lane has not edited the
doc and neither have I.

---

## Part 6: The plugin-split proposal, costed

Splitting hooks into sibling plugins (`source-control` plus `source-control-hooks`).

**For:** independent enable/disable, which is the stated goal and which today requires disabling a
whole plugin including its skills. Honest per-plugin cost accounting under the hook-budget
convention. A consumer can take the skills without the latency.

**Against:**
- Roughly 20 plugins become up to 40. Marketplace and catalog-taxonomy load.
- `hook-utils.sh` is already vendored into all 20 plugins by `scripts/sync-hook-utils.sh`. The
  split multiplies that duplication.
- A gate enforcing a sibling skill's invariant becomes independently disableable. That is
  simultaneously the feature and the footgun. `worktree-add-containment-gate` enforces an invariant
  that `source-control:worktree` depends on; separating them lets a consumer install the skill with
  its guard off and not know.
- Per-hook `*_enabled` switches already deliver most of the toggling benefit at zero structural cost.

**Recommendation:** do not do this fleet-wide on current evidence. If you want it, do it for
`guardrails` first, which is already nearly hooks-only (11 hooks plus one setup skill), and measure
whether the independent-toggle benefit is real before touching the other 19.

---

## Part 7: New hook candidates

Run at the REJECT-default bar that `claude-config:audit-automation-gaps` sets. Most died there.

| Candidate | Verdict | Why |
|---|---|---|
| **Extend `secret-pattern-detection` and `hardcoded-path-check` to GitHub MCP write tools** | **ACCEPT** | Not a new hook, a coverage hole in existing ones. `mcp__github__push_files`, `create_or_update_file` and `delete_file` write to a repo without touching Write or Edit, so both guards are blind to them. `pr-linkage-mcp-gate` already set the precedent for MCP-surface parity. This is the strongest item in this section |
| Gate on `WebFetch` / `WebSearch` for untrusted content | REJECT | The `untrusted-content` convention is a reading-posture rule, not a checkable predicate on a URL. A hook here would be a competence guess |
| Gate `Agent` / subagent prompts | REJECT | `context-guard` already gates `Agent` on zone. Nothing else here has a checkable invariant |
| Enforce "open every PR as a draft" (AGENTS.md) | CONDITIONAL | Checkable, and the linkage gate already parses `gh pr create` in the same guard. Cheap to add there. But it is a behavioral nudge under the Part 2 rubric, so it needs stumble evidence first |
| Enforce the ruff-pin rule (`.claude/rules/ruff-pin.md`) | REJECT | Prose rule with no observed violations cited. Anticipatory instructions are the exact failure mode the philosophy doc names |
| Gate `Read` on large files or secrets | REJECT | Output limits already handle size; no secret-exposure incident on record |

---

## Recommended sequence

1. **`block-hook-bypass` scratch-root default** plus the repro-first stay-quiet test, and open
   the ADR 0003 corpus sweep behind it. Four observed false positives, zero true positives,
   three independent sessions, one open issue. Highest value, lowest risk.
2. **Kill-switch hoist** across all 43 sites, plus a `check-killswitch-hoist.sh` CI gate.
   Mechanical, measured (15% to 75% of a disabled hook's cost recovered), makes the
   extensibility promise true. Cross-lane: offered to the PostTool lane to own, since two
   sessions editing 43 shared files would collide.
3. **The two visibility one-liners.** `statusMessage` on the two disk-hygiene rows (the most
   expensive uninstrumented row in the fleet), and a top-level `description` on all 20
   `hooks.json` files. Neither touches guard logic. Note `hooks.json` is a contended file under
   the multi-session protocol, so the `description` sweep needs an owner agreed first.
4. **DELETE the two behavioral advisories** (`flag-commit-pr-skill-bypass`,
   `workflow-resilience-check`). Both already default-off, so blast radius is near zero.
5. **`if:` narrowing experiment** on the guardrails Bash row, measured before adoption, as
   evidence into #3685.
6. **TRIM the three hybrids**, each with recorded rationale per the rubric's removal discipline.
7. **MCP coverage parity** for the two content guards.
8. Everything else needs evidence first: the two EVIDENCE-GATE platform guards want a
   `claude-config:unhobble` ledger run, and `updatedInput` wants its own posture decision.

Items 1 through 4 are independently shippable and do not touch #3685's territory.
