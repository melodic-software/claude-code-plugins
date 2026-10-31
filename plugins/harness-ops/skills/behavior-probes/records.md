# Behavior probes: recorded outcomes

Each record below is a claim about Claude Code platform behavior that a case in `cases/` measures, in
the record format `/source-control:worktree` uses for its fixtures:
claim, basis, as-of, recheck trigger, outcome. They are probed behaviors in the sense of the
[upstream-drift convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/upstream-drift/README.md):
the pointer is the case, and the observation is ours. A record whose case cannot be rerun is a
memory, not a record; change a case and rerun it in the same commit.

## Basis shared by every record

One live suite run, `probe.py run --live --retries 1 --max-runs 20 --max-cost-usd 10`, which launched
one session per case:

```text
claude -p --output-format stream-json --verbose --permission-mode <case> \
  --setting-sources project,local --settings <case settings.json> --model sonnet \
  --max-turns <case> --max-budget-usd <case> --no-session-persistence \
  --append-system-prompt <driver prompt>
```

Each session ran in its own temp directory, with the prompt on stdin and the child environment
reduced to the runner's allowlist plus the case's `env`. Linux (WSL2), Claude Code **2.1.295**,
2026-10-08: 18 runs, no retry needed. The two dry-run-push controls were first written expecting
`ran`; the diverged remote rejects that push after the permission layer allows it, so they were
corrected to `allow` and the saved streams were re-read with `probe.py rejudge` (no new run). Raw
streams were not kept.

**Recheck trigger for every record:** `probe.py recheck` naming the case for a release range (run
by `/harness-ops:changelog apply`), or the case's own trigger below. **Unconditional expiry:**
Claude Code 2.1.320 or 2027-01-08, whichever comes first.

## 1. A PreToolUse `allow` hook skips the classifier

**Claim.** In auto mode, a force push sourced from a file is denied by the classifier, and the same
call runs when a PreToolUse hook returns `permissionDecision: "allow"` for it.

**Recheck trigger.** A release note naming PreToolUse `permissionDecision`, hook precedence, or the
auto-mode decision order.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `auto-mode/classifier-denies-file-sourced-force-push` | deny (classifier) | deny, classifier, `[Git Destructive]` | pass |
| `hooks/pretooluse-allow-skips-classifier` | ran | ran, forced update | pass |

## 2. An ask rule under `claude -p` becomes a denial, in the main agent and a foreground subagent

**Claim.** With no prompt host, a `permissions.ask` rule turns a call the classifier would allow
into a denial with `decision_reason_type: "rule"`, and the same holds for a foreground subagent's
call. Background subagents are not covered.

**Recheck trigger.** A release note naming `--permission-prompts`, ask rules, headless or print
mode permission handling, or subagent permission prompts.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `auto-mode/ask-rule-denies-in-print-mode` | deny (rule) | deny, rule | pass |
| `auto-mode/dry-run-push-allowed-without-ask-rule` | allow | allowed; the push itself was rejected by the remote | pass |
| `auto-mode/subagent-ask-rule-denies` | deny (rule), in subagent | deny, rule | pass |
| `auto-mode/subagent-dry-run-push-allowed` | allow, in subagent | allowed; rejected by the remote | pass |

## 3. A narrow allow rule lets a classifier-blocked command through

**Claim.** `permissions.allow` `Bash(git push --force origin main)` lets that exact command run in
auto mode, where the classifier denies it without the rule. The rule matches the literal command
string: a `git -C <dir> push …` rewrite does not match it (seen in the hand-run probes that preceded
this suite, not asserted by a case).

**Recheck trigger.** A release note naming allow-rule matching, rules carried into auto mode, or
`classifyAllShell`.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `auto-mode/narrow-allow-rule-passes-classifier` | ran | ran, forced update | pass |
| `auto-mode/classifier-denies-file-sourced-force-push` | deny (classifier) | deny, classifier | pass |

## 4. `EnterWorktree` under `claude -p`

**Claim.** By name, `EnterWorktree` creates and enters a worktree under `.claude/worktrees/` without
a prompt; by a path outside it, the call is denied with `decision_reason_type: "safetyCheck"`.

**Recheck trigger.** A release note naming `EnterWorktree`, worktree confirmation, or permission-root
relocation.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `worktree/enterworktree-inside-allowed` | ran | ran, "Created worktree" | pass |
| `worktree/enterworktree-outside-denied` | deny (safetyCheck) | deny, safetyCheck | pass |

## 5. `autoMode` is read from `--settings`, not from project settings

**Claim.** A `soft_deny` rule in the project's `.claude/settings.json` is not applied though that
file's `env` is; the same rule passed with `--settings` makes the classifier deny the command. The
denial's label was a default category (`[Auto-Mode Bypass]`), not the custom rule's text.

**Recheck trigger.** A release note naming `autoMode`, settings scopes for auto mode, or classifier
reason labels.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `auto-mode/project-automode-rule-ignored` | ran | ran, `PROBEMARK project-settings-loaded` | pass |
| `auto-mode/flag-automode-rule-denies` | deny (classifier) | deny, classifier, `[Auto-Mode Bypass]` | pass |
| `auto-mode/probemark-runs-without-rule` | ran | ran | pass |

## 6. A custom `soft_deny` list without `"$defaults"` keeps the defaults

**Claim.** A `--settings` `autoMode.soft_deny` list that omits `"$defaults"` still leaves the default
rules applied: the force push is denied `[Git Destructive]`.

**Recheck trigger.** A release note naming `$defaults` or `soft_deny` semantics.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `auto-mode/soft-deny-without-defaults-keeps-defaults` | deny (classifier) | deny, classifier, `[Git Destructive]` | pass |
| `auto-mode/custom-soft-deny-benign-command-runs` | ran | ran | pass |

## 7. The concurrent-subagent cap refuses, it does not deny

**Claim.** With `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=2`, one of three concurrent background Agent
calls is refused with an error result ("Concurrent subagent limit reached"), not a permission
denial; with the cap at 3, all three launch.

**Recheck trigger.** A release note naming `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` or the subagent
concurrency cap.

**Basis.** Both cases now spawn `sonnet` subagents instead of `haiku`, and were rerun live after
that change, `probe.py run --live --retries 1 --max-runs 4 --max-cost-usd 4 --case <id>...`, with
the launch above. Linux (WSL2), Claude Code **2.1.296**, 2026-10-11: 2 runs, no retry needed. Raw
streams were not kept. The recheck trigger and expiry above apply.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `concurrency/subagent-cap-refuses-over-limit` | refused (any of 3) | 1 of 3 refused, "Concurrent subagent limit reached" | pass |
| `concurrency/subagent-cap-allows-within-limit` | ran (all 3) | 3 of 3 launched | pass |

## 8. The sandbox blocks unlisted hosts inside the command

**Claim.** On Linux with `sandbox.enabled`, Bash runs with no prompt; a request to a host outside
the allowlist fails inside the sandbox (curl exit 7, a `sandbox_violations` note) and is not a
permission denial.

**Recheck trigger.** A release note naming the sandbox network proxy, `allowed_domains`, or
`autoAllowBashIfSandboxed`.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `sandbox/network-blocked-outside-allowlist` | refused | refused, sandbox violation | pass |
| `sandbox/write-in-cwd-runs` | ran | ran | pass |

## Basis for records 9 and 10

A second live run of only these cases, `probe.py run --live --retries 1 --max-cost-usd <ceiling> --case
<id>...`, with the launch above. Linux (WSL2), Claude Code **2.1.295**, 2026-10-09: 6 runs, no retry
needed. An earlier run the same day failed two cases for fixture reasons, corrected before this run:
the first control allow entry carried the conditions record 9 now tests separately, and the first
hook put `&& echo` after the heredoc start (see record 10). Raw streams were not kept. The recheck
trigger and expiry above apply.

## 9. A `resolveReviewThread` mutation needs an `autoMode.allow` entry the classifier can check

**Claim.** In auto mode, a `gh api graphql` `resolveReviewThread` mutation the user did not name is
denied `[External System Writes]`. An unconditional `autoMode.allow` entry passed with `--settings`
clears it. An entry conditioned on facts only tool output shows (the session opened the pull
request, a pushed commit fixed the finding, the author is a bot) does not, when those facts appear
only in a file the model read. `GH_HOST` points at an `.invalid` host, so no call reaches GitHub.

**Recheck trigger.** A release note naming `autoMode.allow`, External System Writes, or what the
classifier reads from tool results.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `auto-mode/bot-thread-resolve-denied-without-allow` | deny (classifier) | deny, classifier, `[External System Writes]` | pass |
| `auto-mode/bot-thread-resolve-conditional-allow-denied` | deny (classifier) | deny, classifier, `[External System Writes]` | pass |
| `auto-mode/bot-thread-resolve-allowed-with-allow-entry` | allow | allowed; gh failed to connect to `probe.invalid` | pass |

## 10. A PreToolUse `updatedInput` with no decision is applied and still goes through the permission layer

**Claim.** A PreToolUse hook that returns `updatedInput` and no `permissionDecision`, rewriting a
multi-line `git commit -m` to `git commit -F -` fed by a heredoc, has its rewrite run. It approves
nothing: under `claude -p` in default mode with no allow rule the call is denied ("This command
requires approval"), and an allow rule matching only the rewritten form lets it run, so rules are
read against the rewritten input. The stream's `tool_use` input keeps the model's original `-m`
command; `result.permission_denials[].tool_input` carries the rewritten one. In the earlier run, a
rewrite with `&& echo` after the heredoc start was denied in default mode with "Text after the
heredoc start on the same line cannot be statically analyzed" whatever the rules said, while auto
mode ran it (not asserted by a case).

**Recheck trigger.** A release note naming PreToolUse `updatedInput`, heredoc parsing in permission
checks, or how rules match a hook-modified input.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `hooks/updatedinput-no-decision-runs-in-auto` | ran | ran, `PROBE_REWRITE_APPLIED` | pass |
| `hooks/updatedinput-no-decision-denied-in-default` | deny | deny, `other`, "This command requires approval" | pass |
| `hooks/updatedinput-no-decision-rule-matches-rewrite` | ran | ran | pass |

## Basis for the 2026-10-10 Windows refresh

A rerun of every case on Windows 11, with Git for Windows bash running the scaffolds, Claude Code
**2.1.296**, 2026-10-10. It used the launch above and the runner defaults (`--max-runs 20`,
`--max-cost-usd 10`, each case's `max_budget_usd`), in batches that keep each negative case with its
control. The two failing cases were run a second time and failed the same way. The sandbox cases are
Linux-only and were skipped. Platform and version both differ from the runs above, so a changed
outcome here is not attributed to the release alone. Raw streams were not kept. Records 1 to 10 hold
on this run except where the table says otherwise.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `auto-mode/flag-automode-rule-denies` | deny (classifier) | deny, classifier, `[Auto-Mode Bypass]` | pass |
| `auto-mode/probemark-runs-without-rule` | ran | ran | pass |
| `concurrency/subagent-cap-refuses-over-limit` | refused (any of 3) | 1 of 3 refused, "Concurrent subagent limit reached" | pass |
| `concurrency/subagent-cap-allows-within-limit` | ran (all 3) | 3 of 3 launched | pass |
| `auto-mode/ask-rule-denies-in-print-mode` | deny (rule) | deny, rule | pass |
| `auto-mode/dry-run-push-allowed-without-ask-rule` | allow | allowed; the push itself was rejected by the remote | pass |
| `auto-mode/subagent-ask-rule-denies` | deny (rule), in subagent | deny, rule | pass |
| `auto-mode/subagent-dry-run-push-allowed` | allow, in subagent | allowed; rejected by the remote | pass |
| `auto-mode/classifier-denies-file-sourced-force-push` | deny (classifier) | deny, classifier, `[Git Destructive]` | pass |
| `auto-mode/narrow-allow-rule-passes-classifier` | ran | ran, forced update | pass |
| `hooks/pretooluse-allow-skips-classifier` | ran | ran, forced update | pass |
| `auto-mode/project-automode-rule-ignored` | ran | ran, `PROBEMARK project-settings-loaded` | pass |
| `auto-mode/soft-deny-without-defaults-keeps-defaults` | deny (classifier) | deny, classifier, `[Git Destructive]` | pass |
| `auto-mode/custom-soft-deny-benign-command-runs` | ran | ran | pass |
| `auto-mode/bot-thread-resolve-denied-without-allow` | deny (classifier) | deny, classifier, "judged this action dangerous (it gave no explanation)", no category label | pass |
| `auto-mode/bot-thread-resolve-conditional-allow-denied` | deny (classifier) | deny, classifier, same unlabeled reason | pass |
| `auto-mode/bot-thread-resolve-allowed-with-allow-entry` | allow | allowed; gh failed to connect to `probe.invalid` | pass |
| `hooks/updatedinput-no-decision-runs-in-auto` | ran | deny, classifier, `[Auto-Mode Bypass]` | fail |
| `hooks/updatedinput-no-decision-denied-in-default` | deny | deny, `other`, "This command requires approval" | pass |
| `hooks/updatedinput-no-decision-rule-matches-rewrite` | ran | ran | pass |
| `worktree/enterworktree-inside-allowed` | ran | refused: the temp path was an 8.3 short name and git resolved the worktree to the long name | fail |
| `worktree/enterworktree-outside-denied` | deny (safetyCheck) | deny, safetyCheck | inconclusive (its control failed) |
| `sandbox/network-blocked-outside-allowlist` | refused | not run, Linux-only | skipped |
| `sandbox/write-in-cwd-runs` | ran | not run, Linux-only | skipped |

**Changed.** Record 10's auto-mode claim did not hold: the classifier denied the call as
`[Auto-Mode Bypass]` instead of running the rewrite. Record 4's inside case was refused because the
run's temp directory came through as a Windows 8.3 short path that git resolves to the long form, so
it measures the fixture's path rather than `EnterWorktree` itself. Record 9's denials no longer
carried the `[External System Writes]` label.

## Basis for records 11 to 13

A live run of the `subagent` area, `probe.py run --live --area subagent --retries 1 --max-runs 12`,
with the launch above. Linux (WSL2), Claude Code **2.1.296**, 2026-10-10: 6 runs, no retry needed.
Each case reads the level from the `effort.level` field of the hook payload, which the fixture's
hook appends to `effort.log` and the subagent then `cat`s, so the reading is not the model's own
report. `env-effort-overrides-spawn` first ran with a stricter check that also wanted the Agent
call's `effort` in the PreToolUse hook's `tool_input`. It failed because that `tool_input` carried
no `effort`, even though the saved stream shows the driver passed `"effort":"high"`. That was
observed only with `CLAUDE_CODE_EFFORT_LEVEL` set. The case went back to its original check and
was rerun once with `--keep`. That run passed, and its saved stream again shows `"effort":"high"`
on the Agent call. The streams were not committed. The recheck trigger and expiry above apply.

## 11. A per-spawn effort overrides a subagent's pin, and the environment variable overrides both

**Claim.** A subagent pinned at `effort: low` runs at `low` when the spawn passes no `effort`, even
with the session at `high`. It runs at `high` when the Agent call passes `effort: "high"`. With
`CLAUDE_CODE_EFFORT_LEVEL=medium` it runs at `medium` despite both the pin and the spawn value.

**Recheck trigger.** A release note naming the Agent tool's `effort` parameter, a subagent's
`effort` field, or `CLAUDE_CODE_EFFORT_LEVEL`.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `subagent/definition-pin-applies-without-spawn-effort` | ran, `effort=low` | `effort=low` (session `high`) | pass |
| `subagent/spawn-effort-overrides-pin` | ran, `effort=high` | `effort=high` | pass |
| `subagent/env-effort-overrides-spawn` | ran, `effort=medium` | `effort=medium`; the stream shows `effort: "high"` passed | pass (rerun) |
| `subagent/spawn-agent-call-carries-effort` | Agent call with `"effort": "high"` runs | ran | pass |

## 12. An unpinned subagent with no spawn effort runs at the session level

**Claim.** A subagent with no `effort` field, spawned with no `effort`, runs at the session's
`effortLevel` (`low`). This case checks the instrument the other effort cases depend on.

**Recheck trigger.** As record 11.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `subagent/placeholder-tracks-session-effort` | ran, `effort=low` | `effort=low` | pass |

## 13. `${CLAUDE_EFFORT}` in a skill preloaded into a subagent is the session's level

**Claim.** In a skill preloaded into a subagent pinned at `effort: low`, `${CLAUDE_EFFORT}` expands
to the session's `effortLevel` (`medium`), not to the pin. A `fail` showing `low` would mean the
placeholder now follows the subagent's level; `/discovery:research`'s parent contract depends on
this case.

**Recheck trigger.** A release note naming `${CLAUDE_EFFORT}` or skill string substitution.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `subagent/preloaded-skill-placeholder-reflects-session-effort` | ran, `effort=medium` | `echo effort=medium` | pass |

## Basis for record 14

One live run, `probe.py run --live --max-runs 1 --case subagent/skill-tool-skill-placeholder-effort`,
with the launch above. Linux (WSL2), Claude Code **2.1.310**, 2026-10-25: 1 run, no retry. The case
was written expecting `effort=medium`, the level record 13 found for a preloaded skill, and that run
judged `fail` on `effort=low`. The saved stream shows the subagent's Skill call loading
`print-effort` with no error, then `echo effort=low`; no literal `${CLAUDE_EFFORT}` appears, so the
skill text reached the subagent already expanded. `expect.json` was corrected to `effort=low` and
the stream re-read with `probe.py rejudge` (no new run). The stream does not carry the session's
level and this run's workdir was not kept. Record 15's control, run on the same version with the
same `settings.json` and its workdir kept, read `medium` through a preloaded skill. The two loading
paths differ on 2.1.310; neither moved between versions.

Refreshed on Claude Code **2.1.312**, 2026-10-28, with
`probe.py run --live --max-runs 2 --max-cost-usd 4 --keep` over this case and record 15's: 2 runs,
both pass, no retry. The subagent's Skill call returned `Launching skill: print-effort`, then it ran
`echo effort=low`; no literal `${CLAUDE_EFFORT}` reached a command. With the workdir kept, its hook
logged `agent_type=effort-probe-skill-tool tool=Bash effort=low`.

## 14. `${CLAUDE_EFFORT}` in a skill a subagent loads through the Skill tool is the subagent's level

**Claim.** In a skill a subagent pinned at `effort: low` loads through the Skill tool (no `skills`
preload), `${CLAUDE_EFFORT}` expands to the pin (`low`), not to the session's `effortLevel`
(`medium`). Record 15 shows the preloaded path still giving `medium` on the same version, so the
substituted level depends on how the skill is loaded. A `fail` showing `medium` would mean the
Skill-tool path now follows the session level.

**Recheck trigger.** A release note naming `${CLAUDE_EFFORT}`, skill string substitution, or the
Skill tool inside subagents.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `subagent/skill-tool-skill-placeholder-effort` | ran, `effort=low` | `echo effort=low` | pass |

## Basis for record 15

One live run,
`probe.py run --live --max-runs 1 --keep --case subagent/preloaded-skill-placeholder-reflects-session-effort`,
with the launch above. Linux (WSL2), Claude Code **2.1.310**, 2026-10-25: 1 run, no retry, workdir
kept. The fixture's hook wrote this `effort.log`:

```text
event=SubagentStart agent_type=effort-probe tool=- effort=unset env=unset
event=PreToolUse agent_type=effort-probe tool=Bash effort=low env=low
```

The subagent ran at its `low` pin when it ran `echo effort=medium`. The hooks fire only for the
subagent, so no line names the session's level directly. `medium` appears nowhere in the run but
the case's `effortLevel`, and the substituted value is not the subagent's.

Refreshed on Claude Code **2.1.312**, 2026-10-28, in the record 14 refresh run: pass, the same
`effort.log` lines, and the subagent ran `echo effort=medium`.

## 15. On 2.1.310, a preloaded skill still reads the session's level while the subagent runs at its pin

**Claim.** The record 13 case, rerun with the record 14 case on the same version: `${CLAUDE_EFFORT}`
in a skill preloaded into a subagent pinned at `effort: low` still expands to `medium`, while the
hook payload for that subagent's Bash call reports `effort.level` `low`. The preloaded and
Skill-tool paths differ; the preloaded path did not change between 2.1.296 and 2.1.310.

**Recheck trigger.** As record 13.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `subagent/preloaded-skill-placeholder-reflects-session-effort` | ran, `effort=medium` | `echo effort=medium`; hook `effort=low` | pass |

## Basis for record 16

A live run of the `autocompact` area, `probe.py run --live --area autocompact --max-runs 4
--max-cost-usd 1.0`, each case at `max_budget_usd` 0.25, with the launch above plus each case's
`cli_args` and `env`. Linux (WSL2), Claude Code **2.1.312**, 2026-10-28: 4 runs, no retry. Each
session printed its window with no model turn: the stream held a `<synthetic>` assistant message
with the text and a result with `num_turns` 0 and no cost. The runner then read any assistant
message as a model turn, so all four first reported `inconclusive`; the verdict now trusts a result
reporting `num_turns` 0, and the saved streams were re-read with `probe.py rejudge` (no new run).
The streams were not committed. The recheck trigger and expiry above apply.

## 16. `/autocompact` window precedence within project scope, the flag and the environment variable

**Claim.** `/autocompact` with no argument reports the effective window. A project settings file's
top-level `autoCompactWindow` sets it; that file's `modelSettings.<model id>.autoCompactWindow`
beats its top-level key; `--autocompact` beats the project file; `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
beats the flag. The printed line names its source as `(from settings)` for both the file and the
flag, and `(from CLAUDE_CODE_AUTO_COMPACT_WINDOW)` for the variable, so a case matches the window,
not the source label. User-scope precedence is not probed here.

**Recheck trigger.** A release note naming `/autocompact`, `--autocompact`,
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` or `modelSettings`, or `claude -p` starting a model turn for a
local slash command.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `autocompact/project-top-level-window-applies` | 250k | `Auto-compact window for Sonnet 5.5: 250k tokens (from settings)` | pass |
| `autocompact/project-per-model-beats-top-level` | 400k | `... 400k tokens (from settings)` | pass |
| `autocompact/flag-beats-project-settings` | 200k | `... 200k tokens (from settings)` | pass |
| `autocompact/env-beats-flag` | 150k | `... 150k tokens (from CLAUDE_CODE_AUTO_COMPACT_WINDOW)` | pass |

## Basis for record 17

A live run of the `lane-permissions` area, `probe.py run --live --area lane-permissions --retries 1`
(default ceilings), with the launch above plus `--permission-mode dontAsk` and the write lane's lists
from `cases/lib/lane-write-tools.json` as `--allowedTools` and `--disallowedTools`. Linux (WSL2),
Claude Code **2.1.312**, 2026-10-28: 7 runs, no retry needed. Every case is verdict-only: no stream
was saved, `raw/` stayed empty, and every result row's tool text was blank. The recheck trigger and
expiry above apply.

## 17. The write lane's Read deny rules keep Grep, Glob and Read out of `/proc` and `.git`

**Claim.** Under `dontAsk` with the write lane's tool lists, `Read(//proc/**)` denies Grep and Glob
calls that reach `/proc/*/environ`, and `Read(/<workspace>/.git/**)` denies a Grep of the checkout's
`.git` directory and a Read of its `.git/config`. Grep and Read of a file inside the checkout run.

**Recheck trigger.** A release note naming Read rules on Grep or Glob, `--allowedTools`,
`--disallowedTools` or `dontAsk`, or a change to the lane's lists in `collect-base-activity`.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `lane-permissions/grep-proc-environ-denied` | deny (rule) | deny, rule | pass |
| `lane-permissions/grep-proc-self-glob-environ-denied` | deny (rule) | deny, rule | pass |
| `lane-permissions/glob-proc-environ-denied` | deny (rule) | deny, rule | pass |
| `lane-permissions/grep-git-dir-denied` | deny (rule) | deny, rule | pass |
| `lane-permissions/read-git-config-denied` | deny (rule) | deny; seen only in `result.permission_denials`, so `unknown` | pass |
| `lane-permissions/grep-in-checkout-runs` | ran | ran | pass |
| `lane-permissions/read-in-checkout-runs` | ran | ran | pass |

## Basis for record 18

A live run of the `intake-permissions` area, `probe.py run --live --area intake-permissions
--retries 1 --max-runs 10 --max-cost-usd 2`, with the launch above plus `--permission-mode dontAsk`
and `--allowedTools 'Bash(gh issue view *)'`. Each case's settings put the stub `gh` first on
`PATH`. Linux (WSL2), Claude Code **2.1.312**, 2026-10-29: 5 runs, no retry needed. The streams
were not committed. The recheck trigger and expiry above apply.

## 18. Under `dontAsk`, a `Bash(gh issue view *)` rule does not approve a compound command

**Claim.** Under `dontAsk` with only `Bash(gh issue view *)` allowed, a plain `gh issue view 1` runs,
and the same call with `; touch`, `&& touch`, `| touch` or `$(touch ...)` appended is denied: the
rule approves no subcommand it does not match. The denial reports `decision_reason_type` `mode`
(the `dontAsk` mode denies what no rule allows), not `rule`.

**Recheck trigger.** A release note naming Bash permission rule matching, compound commands, command
substitution, `--allowedTools` or `dontAsk`.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `intake-permissions/gh-issue-view-runs` | ran, `gh-stub-marker` | ran, `gh-stub-marker: issue view 1` | pass |
| `intake-permissions/gh-issue-view-semicolon-denied` | deny | deny, mode | pass |
| `intake-permissions/gh-issue-view-and-denied` | deny | deny, mode | pass |
| `intake-permissions/gh-issue-view-pipe-denied` | deny | deny, mode | pass |
| `intake-permissions/gh-issue-view-substitution-denied` | deny | deny, mode | pass |

## Basis for record 19

A hand run on the owner's host on 2026-10-31, before the case existed. The case follows the same
steps. `claude -p "/schedule ..." --permission-mode auto` created one one-off routine on this
repository with `run_once_at` 06:03Z, the Default environment and tools `Bash` and `Read`, then ran it
once. The scheduled fire was the second run. Claude Code **2.1.314** ran on the host and inside both
runs. Run 1 (manual, 05:47Z) posted
[a nonce](https://github.com/melodic-software/claude-code-plugins/issues/8991#issuecomment-6539724978),
and run 2 (scheduled, 06:08Z, a separate session) posted
[the same nonce read back](https://github.com/melodic-software/claude-code-plugins/issues/8991#issuecomment-6539913643).
The [host-run report](https://github.com/melodic-software/claude-code-plugins/issues/8991#issuecomment-6540243272)
has the rest. The case `cloud-routine/state-read-back-next-run` has passed a dry run but has not run
live; its first live run replaces this basis. The recheck trigger and expiry above apply.

## 19. A cloud routine reads back on its next run the state it posted to an issue comment

**Claim.** A one-off routine's first run posts a state record to an issue comment, and its next run,
a separate cloud session, reads the same record back. Starting a run by hand does not use up the
one-off: the scheduled fire still ran it a second time, and then the routine reported
`"enabled":false,"ended_reason":"run_once_fired"`. The comments post as the owner's GitHub login, not
a bot, so a reader finds a routine's comments by their marker, not their author. Inside the run the
shell's zone is UTC (`date +'%Z %z'` gave `UTC +0000`, `TZ` unset). The date in the session's own
context was `2026-10-31` in both runs, which does not settle its zone: at 05:47Z and 06:08Z that is the
date in both UTC and New York. That part stays with #7679.

**Recheck trigger.** A release note naming scheduled tasks or routines, `/schedule`, one-off runs,
**Run now**, or the cloud environment's time zone or GitHub proxy.

| Case | Expected | Observed | Verdict |
|---|---|---|---|
| `cloud-routine/state-read-back-next-run` | ran, `result=pass` | hand run: `read-back nonce=267acddb-…, result=pass` | pass (hand run; the case has not run live) |
