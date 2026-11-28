# Session observer: live checks and catch-up

The observer watches each session for process faults and files them in `running-retro`'s ledger, so
a retro or `/corrections:codify` has findings without anyone running a checkpoint. It has two parts,
one per kind of session, and one switch, `observer_enabled`:

- **Live checks** (the hooks module `hooks/register.tsx`) run inside an interactive session while
  it works.
- **Catch-up** (the SessionStart hook `hooks/observer-catchup.sh`) runs at the next session's start
  and analyzes ended sessions that got no live checks: headless `-p` lanes, and sessions that ended
  before a check fired.

`running-retro` owns the analysis method, the finding taxonomy, redaction and the ledger; both parts
write to that ledger and add no second format.

## Live checks

**When.** On the main thread only (never a subagent's steps), on every `observer_step_every`th
(default 6) model step of a turn (`observer_step_check`, on by default); when
`observer_turn_end_check` is on, once at the end of each turn that ran tools and was not
interrupted; when `observer_change_check` is on, at the step after one whose tool calls match
`observer_change_tools` (default `Edit,Write,NotebookEdit`); and when `observer_gate_check` is on,
before each Bash command matching `observer_gate_pattern` (see "Gate"). One check runs at a time per
session: a trigger while one is in flight starts none, except a gate check, which always runs. The checks run only where a person is at the prompt (the
`session.start` event's `isInteractive`) and never in the catch-up's own analysis run
(`SESSION_FLOW_OBSERVER_ANALYSIS` set).

**What.** A check is a `$.model.fork` with a prompt only: it reuses the main thread's cached
request, has no tools and writes nothing to the transcript. The prompt asks for at most one fault in
four categories (`process`, `decision`, `verification`, `instruction`), plus `request` (a skipped or
unanswered part of the person's latest request, or drift from the session's stated goal) with
`observer_request_check` on, `skill` (work done by hand or another way where a listed skill or a
written rule assigns it to a skill, or a skill run that hit a case its steps miss, ran inefficiently
or ended without its `## Next`) with `observer_skill_check` on, and `improvement` (a step that ran
far longer than it should, a bug or failure seen and not raised, or work against a principle the
repository's loaded docs state) with `observer_improvement_check` on, all three off by default. Each
finding is tied to a rule or owner decision the session's own instructions or conversation state,
and a check defaults to `finding: none`. The reply is labeled lines, parsed leniently; a reply with
no rule, an unknown category or a finding over `observer_field_max` (240) characters counts as
`parse_failed`; the prompt states that cap for rule and evidence, and a longer one is cut to it. An optional last line routes the fix: `fix: session` (a dedicated session, with a
ready command as harness findings carry, never auto-sent) or `fix: issue` (file it under the
repository's filing rules); a missing or unknown line means here, and never fails the parse.

**Repository layer.** At session start the module runs `lib/observer-team.mjs`, which reads two
files from the default branch only, through `lib/default-branch-file.sh`, so a branch cannot change
the rules it is checked by: the `observer` map of the repository's `session-flow.yaml` (`skill_check`,
`improvement_check`, `defer_kinds`, `codify_threshold`; schema `schemas/session-flow.schema.json`),
each of which wins over the user option of the same name with the `observer_` prefix, and the
`## Observer guidance` section of `session-flow.md` in the same convention home, added to every
check before the person's `observer_guidance`, each cut to `observer_guidance_max`. An invalid
repository value is dropped, the user's value stands, and an `option_invalid` row names it as
`team:<key>`. An unreadable default branch leaves the user's options in force.

**Stale and repeated replies.** A reply that arrives after the next turn started, or after the
session ended, is dropped as `stale`; its row's `held` says whether it carried a finding. Findings already reported (the last `observer_list_max`, default 50, across sessions) and
findings the person disputed are listed in the prompt and dropped again in code (`deduped`), matched
case-insensitively without a trailing period.

**Delivery.** A finding is appended to this session's running-retro ledger
(`<main checkout>/.work/running-retros/`, found by its `session_id:` frontmatter, created with
`observer: live`) under `## Live check <time> (<trigger>, turn <id>, step <n>)`, after the same
self-ignore guard the catch-up uses. `<main checkout>` is the repository's main working tree
(`git rev-parse --git-common-dir`, minus `.git`), so a session started in a linked worktree keeps
its ledger when the worktree is removed; outside a repository it is the session's project folder.
Every ledger and usage write is an append (`node`'s `appendFileSync`, run through
`$.process.run`), so a running-retro checkpoint written at the same moment is never lost. Where
`$.process.run` cannot run, the write falls back to a read and rewrite through `$.fs` that checks the
file's size and modification time again just before writing and retries when they moved; that
narrows the window but cannot close it, since `$.fs` has no append. The finding also shows as a band row above the
prompt, with a blank line above it as the built-in side agent's has, led by a `◆` (`*` when
`TERM` is `dumb`), `observer`, its category and the trigger that found it
(`step 12`, `turn end`), with buttons `5` Send to Claude (appends a quoted note to the prompt box,
marked as background the person did not write), `6` Noted (marks the ledger entry confirmed), `7`
Dispute (marks it disputed and suppresses it for good), `8` Why (shows the rule, the evidence, this
session's check cost and how to pause) and `9` Dismiss. The hotkeys are `5` to `9` because the
built-in side agent's band uses `1` to `4` and `0`, and a hotkey two plugins share presses neither.
Nothing reaches the main conversation unless the person sends it or auto-send is on. After Dismiss, one row offers
the built-in side agent's answers on our hotkeys: `5` That was helpful, `6` Not relevant, `7`
Couldn't understand, `8` Turn off checks (live checks stop for this session only; `/observer off`
pauses every session) and `9` Close. It clears itself after `observer_feedback_seconds` (20); the answer goes to the usage
file, so `/observer` can show how often findings were worth showing. Not relevant also adds the
finding to a stored list the next checks are told not to report, nor faults like it; Couldn't
understand makes every later check ask for plain words. Nothing is sent outside the machine.

**Auto-clear.** While a finding is shown, the next check is told about it and answers
`resolved: yes` when the assistant has since fixed it; the band then clears and the ledger records
it as resolved by the assistant.

**Auto-send.** With `observer_auto_send` on (off by default, attended or away alike), a finding
reaches the agent without a button press, framed as the observer's note, never the person's words
(`observer_auto_note` sets its lead). Found while a main turn runs, it is appended with
`$.session.append` and rides the agent's next model request, starting no turn. Found while the
session is idle, it starts one observer turn with `$.prompt.submit`, unless an observer prompt is
already waiting or the last turn was itself an observer turn; such a finding is appended and rides
the next turn, whoever starts it. Idle findings come from the end-of-turn check, so idle delivery
needs `observer_turn_end_check` on. The first main turn after an observer submit counts as the observer
turn; when its start text matches the note, `/observer off` or Turn off before it starts aborts it,
and when it does not, the turn runs and its usage row reads `matched: false`. The band keeps a delivered finding, marked sent, with
Send hidden and Noted, Dispute, Why and Dismiss working; a refused delivery leaves it unsent and
records the error. A category in `observer_defer_kinds` (empty by default) found while a main turn
runs is written to the ledger and band at once but held, and every finding held that turn goes in
one observer turn when it ends, except one the person disputed, dismissed or sent, or a check marked resolved; its `auto_sent` row carries `deferred`, the count sent. `observer_guidance` steers what checks look for; it does not choose what is sent:
to stop sending, turn auto-send off.

**Gate.** With `observer_gate_check` on, a Bash command matching `observer_gate_pattern` waits for a
check that sees the command. A finding refuses the command, and the agent reads the observer's note
as the error; the same command is refused at most `observer_gate_refusals` times (default 1), after
which it runs and its row carries `repeat: true`, so the usage file shows refused commands retried
unchanged. No finding, a fork error or `observer_gate_timeout_seconds` (default 30) lets the command
run: an observer fault never blocks work.

**Harness checks.** With `observer_harness_check` on (off by default), the pure module
`hooks/observer-harness.ts` (event in, findings out) runs seven scripted checks on the main thread
that call no model, so they cost no tokens:

- *Hook latency*: at each turn's end, reads `<observer_hook_log_dir>/sessions/<session>.jsonl`,
  session-telemetry's per-session hook log, and reports a hook with at least
  `observer_hook_min_runs` runs whose p95 `duration_ms` passes `observer_hook_p95_ms`.
- *Cache miss*: cache tokens a turn wrote beyond the context growth the next `session.measure`
  reports count as rewritten; past `observer_cache_miss_tokens`, the cause is compaction, idle
  past the cache lifetime (5 minutes, or 60 once a 1-hour cache write is seen), a model switch, or
  else a prefix change. Compaction and idle misses are recorded, not shown; the first turn never
  counts, and each cause is shown once a session.
- *Slow tool*: `tool.run` times each call; a tool (a Bash command by its first two words) that runs
  past `observer_tool_slow_seconds` `observer_tool_repeat` times is reported once.
- *Loop*: a tool (keyed the same way) whose call fails `observer_loop_repeat` times in a row with
  the same error (its whole text, digits masked, so failures that differ under the same exit-code
  line are not a loop) is reported once per tool and error in a session, its finding quoting the
  error, so a different loop on the same tool is never hidden as a repeat; a success resets the count. `0` turns it off.
- *Context*: each upward crossing of an `observer_context_percents` value.
- *Rate limit*: a window at or past `observer_rate_limit_percent`, once per reset.
- *Codify*: after a live finding is shown, counts the `shown` usage rows of this machine's sessions
  whose `rule` matches it (case-insensitive, trailing period dropped); at `observer_codify_threshold`
  (default 3, `0` off) across two or more sessions, it reports one finding routed to a dedicated
  session running `/corrections:codify <rule>`, once per rule across sessions.

Findings use category `harness` and go through the same ledger, band, remembered lists and usage
rows as a live check's, with a `harness` field naming the check. Each names its fix: `here` (in
this session) or a dedicated session, with a ready `cd '<repo>' && claude -n <name> "<prompt>"`
command (`Set-Location` on Windows). A dedicated-session finding is never auto-sent. `/observer`
counts harness findings beside the live checks.

**Backoff.** A finding the person types past `observer_clear_after_prompts` (default 2) times without
answering clears. Past `observer_ignored_free` (default 2) such findings in a row, the next 1, 2, 4,
8 and then at most `observer_skip_max` (default 16) eligible checks are skipped; any button resets
the count. A delivered finding clears the same way without counting as ignored.

**Usage.** Each check appends one line to `<plugin data>/session-flow-observer/live-<session>.jsonl`:
time, trigger, turn, step, outcome, latency and the fork's token usage; each answer (sent, noted,
disputed, dismissed, ignored, resolved, and the answers after Dismiss) appends one too. Auto-send adds
`auto_sent` rows (delivery `append` or `submit`, note length in `chars`, and `stepsLate` for an
append), `auto_send_failed` rows with the error, and one row per observer turn with its token usage;
gate rows carry trigger `gate`, outcome `refused`, `deferred` (a finding of an `observer_defer_kinds` category, which never refuses), `none`, `timeout`, `error` or
`allowed_after_refusals`, and `repeat`. A `parse_failed` row, check or gate, adds `reason`
(`no_finding`, `no_rule`, `bad_category` or `field_too_long:finding`) and, when the reply had a
finding, the `lengths` of its finding, rule and evidence; never the reply text. A `shown` check row
and a `refused` gate row carry the finding's `category`; a `shown` check row also carries its
redacted `rule`, which the codify check counts. That file is
how a day's cost is read, and its presence tells the catch-up this session had live checks.

**Storage and retention.** One usage file per session and per machine, each with one writer, so no
lock is needed; an agent reads them with `jq` or a line search, no index required. Session start
deletes every observer file in that folder not written for `observer_keep_days` (30) days: the usage files and the
catch-up's `observations-*`, `status-*`, `observer-*.log` and `observer-*.lock` files. The catch-up
only considers transcripts changed in the last 3 days, so a deleted marker never makes it analyze an
old session again. Each machine (a Windows host and its WSL, for one) keeps its own data
folder and store; a report that spans machines reads each machine's folder (another machine's
through `/fleet:reach`) and merges the rows by `at`, with no sync between machines.

**Cache.** A check forks the request the main thread just sent, mid-turn or at the turn's end, so it
reads the conversation from a warm prompt cache and writes only its own prompt; it passes no effort
level, since a level other than the main thread's can cost a cache write of the whole conversation.
A check that wrote more than 20,000 cache tokens is counted as cold in `/observer`.

**Commands.** The module registers `/observer`: bare, it shows whether live checks are on and, for
this session and for the last 24 hours of usage files, the checks by trigger and outcome, tokens
(cache read, cache written, output, read per check), latency, cold-cache checks and answers.
`/observer off` pauses live checks on this machine until `/observer on`; the catch-up still runs.
The lasting switches are the `observer_*` options in `/plugin configure`.

**Cost.** Every check bills the session's account. The end-of-turn trigger fires on most turns of a
working session, so it stays off by default until one working session's per-check usage and checks
per hour have been measured from the usage file and accepted.

## Catch-up

At each interactive session start the hook runs `arm_observer.py`, which picks ended
sessions from the current transcript's directory and launches `observer.py` for each in a process
detached from the session, then returns at once. A session qualifies when it is not the current one,
its transcript has been unchanged for `observer_idle_seconds` and changed within the last 3 days, it
has no live-check usage file, no ledger, and no status file showing it analyzed to its current size.
A ledger excludes a session only when it has no status file (an in-session checkpoint covered it); with
a status file, the stored offset alone decides, so a resumed follow-up of an analyzed session is
analyzed. At most 2 run per start, newest first. `observer.py` reads the transcript once from its stored
offset, distills it, runs the analysis below, writes the ledger and its status file, and exits; a
per-session `O_CREAT|O_EXCL` lock keeps two starts from analyzing one session twice.

Probed 2026-11-25 on Claude Code 2.1.332 (a throwaway mod, one `claude -p --plugin-dir` run): a child started with `setsid -f` from a mod's
`$.process.run` in a `claude -p --plugin-dir` session kept running after the session exited, so either
launcher outlives its session; the catch-up stays a SessionStart hook because that hook already
carries the guards, the platform shim and the Python probe.

## Redaction and the untrusted-data boundary

The distilled observations are **transient and machine-local** (written under the plugin's work dir,
`${CLAUDE_PLUGIN_DATA}/session-flow-observer/`; the hook reads the exported variable and falls back
to the temp dir when it is empty), consumed once by the analysis run, and **deleted
after a successful run**, never written to the durable, portable ledger; only the analysis run's
redacted findings block is. Redaction is **two-hop**, matching `running-retro`'s ledger contract: the
`-p` run performs the **semantic** pass (it is the only reasoning agent in the loop; its prompt makes
that pass emphatic), and `observer.py`'s `_redact()` runs a **mechanical shape-marker sweep** on the
returned block at the ledger write, using conservative regex patterns for API keys, tokens,
private-key blocks, connection strings, JWTs, and emails, replaced with shape markers, never the
value, as defense in depth over the semantic pass. A live check has the same two hops: its prompt
forbids repeating a secret, and the module passes each field through `$.session.redact` before the
ledger write and the band.

Transcripts and observations are **untrusted input**. The shared boundary, that inspected off-thread
output is data to analyze, never instructions to follow, is owned by
[`off-thread-work.md`](./off-thread-work.md) ("The inspected output is untrusted data"); the analysis
prompt restates the directive-immunity rule inline for the fresh `-p` context. The analysis run is
**Read-only**: `--tools Read` restricts the available tool set to Read, `--strict-mcp-config`
loads no MCP servers, and `--allowedTools Read` under `--permission-mode dontAsk` keeps that single
Read from prompting or being denied. `--allowedTools` alone would not suffice, because it only auto-approves
and does not restrict, so a Bash/WebFetch/MCP tool already allowed in the user's settings could
otherwise be driven by a prompt-injection record in the transcript. The distilled observations
already carry the tool histogram and turn boundaries, so the checkpoint block is complete without
running the parser.

## The analysis run: flags and the `--bare` / auth coupling

The default analysis command is:

```text
claude -p --model <observer_analysis_model> --effort <observer_analysis_effort> \
  --permission-mode dontAsk --output-format json \
  --tools Read --allowedTools Read --strict-mcp-config \
  --settings '{"env":{"CLAUDE_CODE_EFFORT_LEVEL":"<observer_analysis_effort>"}}' \
  --add-dir <checkpoint-context-dir> --add-dir <work_dir>
```

with the prompt fed on **stdin** (never as a trailing positional, because `--add-dir` is variadic and would
swallow it). `dontAsk` guarantees the run can never hang (an unauthorized tool call aborts rather
than waiting); `--permission-prompts none` is the print-mode form that denies anything still
waiting on a person and tells the model not to retry it, passed only when `claude --version` reports
2.1.259 or newer (older CLIs reject it as an unknown option and get `dontAsk` alone); `--tools Read` + `--strict-mcp-config` make the run Read-only regardless of
the user's ambient tool grants; `--allowedTools Read` keeps the authorized read from being auto-denied.

**Record.** Claim: `--permission-prompts none` on a `-p` run denies requests that would prompt, while the permission mode still decides first, and removes tools that need a person such as `AskUserQuestion`. Version floor: Claude Code 2.1.259; older CLIs get `dontAsk` alone. Basis: <https://code.claude.com/docs/en/headless#turn-off-permission-prompts-in-unattended-runs> and the `--permission-prompts` row of <https://code.claude.com/docs/en/cli-reference> ("Requires Claude Code v2.1.259 or later"), the row re-fetched 2026-09-29. As of: 2026-09-29. Recheck: that headless section or the CLI flag row changes what `none` denies or the version floor, or the flag stops applying to `-p`. The floor lives in `scripts/claude_cli.py`, shared with `scripts/harness/hop_chain.py`.

`--bare` (skip auto-discovery) is a further cost lever, but it is **off by default** and gated behind
`observer_analysis_bare`: verified on Claude Code 2.1.218, `--bare` makes the run report
`Not logged in · Please run /login` and fail on an **OAuth-login** install, because it drops the login
credential state. Enable it only where auth is an env-var API key that survives it. The dominant cost
levers are the **model** and **effort** (`observer_analysis_model`, `observer_analysis_effort`);
`--bare` is a secondary, environment-dependent one.

## Model and effort

The defaults are the `observer_analysis_model` and `observer_analysis_effort` `default` values in
`.claude-plugin/plugin.json`, the one place they are set: the hook and the launcher
pass an empty value when the option is unset, and `observer.py` reads the manifest. The current
defaults were chosen for faithful findings: in a four-session local pilot against Haiku 5.5 high,
Sonnet 5.5 medium and Sonnet 5.5 high, they missed the fewest important findings and invented the
fewest events. The model is a full ID on purpose, so it does not move when an alias does: see
[model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases). Rerun
that pilot on a new model release.

The observer runs at the configured effort whatever the user's own settings set. So the run always
passes `--effort`, even at the default, drops `CLAUDE_CODE_EFFORT_LEVEL` from the child
environment, and pins it with `--settings '{"env":{"CLAUDE_CODE_EFFORT_LEVEL":"<effort>"}}'`, since
an exported value or a settings file's `env` block could otherwise replace the flag. Whether an
exported value outranks the pin is undocumented, hence both.
Probed on Claude Code 2.1.296 with a project `env` of `max` and `--effort low`: output tokens rose
about fourfold without the `--settings` pin and returned to the `low` range with it.

- **Pointer**: when the order between `CLAUDE_CODE_EFFORT_LEVEL`, `--effort` and settings files
  matters, fetch <https://code.claude.com/docs/en/env-vars#precedence> and
  <https://code.claude.com/docs/en/settings#settings-precedence> live; for which levels a model
  accepts, fetch <https://code.claude.com/docs/en/model-config#adjust-effort-level> live.

## When a run counts as failed

The observations are kept, and nothing is written to the ledger, when the run exits non-zero, its JSON
body reports `is_error`, its output is not JSON, `terminal_reason` (when present) is not `completed`,
`subtype` is not `success`, `permission_denials` is non-empty, or the result text is empty.
The status file then records `state: retained` and `failed_attempts`; the next start's catch-up
retries the analysis once over the kept observations, so a span is analyzed at most twice until its
transcript grows again.

## Short sessions and run usage

A session with no ledger yet is analyzed only once it has at least `observer_min_lines` distilled
transcript lines. A shorter session, such as an automated `gh` monitor sweep, gets no `claude -p`
run: the observer logs `analysis skipped: N lines < min M`, adds that skip to
`status-<session>.json` in the work dir, writes no ledger, and keeps the observations, so a session
that resumes counts its earlier lines toward the threshold. Once a run has written the session's
ledger, every later end is analyzed, however short the follow-up. The default of 300 is a setting
to change: a full working session replayed on 2026-11-24 distilled 3,128 lines, and an automated
sweep is far shorter.

Each run that returns JSON, failed runs included, records the `usage` token counts it reports
(`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`), plus
`duration_ms` and `total_cost_usd` when present, and logs one `analysis usage:` line. Those are the
run's own figures, read back for measurement. Every run and skip is one timestamped entry in the
status file's `analysis_runs` list, which every status write carries, including a later catch-up of
the same session.

## Config (userConfig)

Declared in the plugin manifest; the module and the SessionStart hook read the same values.

| Key | Default | Effect |
|---|---|---|
| `observer_enabled` | `false` | Turns on both parts. Off, the module hooks nothing and the hook exits. |
| `observer_step_check` | `true` | Live check every `observer_step_every` model steps of a turn. |
| `observer_turn_end_check` | `false` | Live check at the end of each tool-using turn (see "Cost" above). Idle delivery under auto-send needs it on. |
| `observer_step_every` | `6` | Model steps between step checks. |
| `observer_auto_send` | `false` | Deliver findings to the agent without a button press (see "Auto-send"). |
| `observer_auto_note` | the plugin-voice note | Text that leads an auto-sent note or a gate refusal. |
| `observer_guidance` | `""` | The person's own guidance, added to every live check's prompt; never the catch-up's. |
| `observer_guidance_max` | `2000` | Characters of guidance kept. |
| `observer_check_prompt` | `""` | Replaces the built-in check instructions; the already-reported lists and the answer shape stay. A replacement that breaks the answer shape shows as `parse_failed`. |
| `observer_change_check` | `false` | Check at the step after one that called a tool in `observer_change_tools`. |
| `observer_change_tools` | `Edit,Write,NotebookEdit` | Comma-separated tool names that count as a change. |
| `observer_gate_check` | `false` | Hold matching Bash commands until a check returns (see "Gate"). |
| `observer_gate_pattern` | `git push`, `gh pr create\|merge\|comment\|review`, `gh issue create\|comment`, `gh api` with a writing method | Regular expression for the held commands. |
| `observer_gate_timeout_seconds` | `30` | Longest hold; the command then runs. |
| `observer_gate_refusals` | `1` | Times the same command is refused before it runs. |
| `observer_request_check` | `false` | Add the `request` category to the live checks. |
| `observer_skill_check` | `false` | Add the `skill` category; the repository's `observer.skill_check` wins. |
| `observer_improvement_check` | `false` | Add the `improvement` category; the repository's `observer.improvement_check` wins. |
| `observer_defer_kinds` | `""` | Categories auto-send holds to the turn's end; the repository's `observer.defer_kinds` wins. |
| `observer_codify_threshold` | `3` | Rule findings across sessions before a codify finding; `0` is off; the repository's `observer.codify_threshold` wins. |
| `observer_harness_check` | `false` | Run the scripted harness checks (see "Harness checks"); they call no model. |
| `observer_hook_log_dir` | `.observability/claude` | Folder of session-telemetry's per-session hook log, absolute or relative to the project. |
| `observer_hook_p95_ms` | `1000` | Hook p95 latency budget in milliseconds. |
| `observer_hook_min_runs` | `5` | Runs a hook needs before its p95 is judged. |
| `observer_cache_miss_tokens` | `50000` | Rewritten cache tokens in one turn that count as a miss. |
| `observer_tool_slow_seconds` | `60` | Seconds after which a tool call counts as slow. |
| `observer_tool_repeat` | `3` | Slow calls of one tool before it is reported. |
| `observer_loop_repeat` | `3` | Failures in a row with the same error before a tool is reported as a loop; `0` is off. |
| `observer_context_percents` | `50,75` | Context-window percentages whose upward crossing is reported. |
| `observer_rate_limit_percent` | `80` | Rate-limit window percent used that is reported, once per reset. |
| `observer_clear_after_prompts` | `2` | Prompts a shown finding survives unanswered. |
| `observer_ignored_free` | `2` | Ignored findings before the backoff starts skipping checks. |
| `observer_skip_max` | `16` | Most checks the backoff skips in a row. |
| `observer_send_note` | the person-voice note | Text that leads a finding the Send button puts in the prompt. |
| `observer_field_max` | `240` | Most characters in a reply's rule or evidence, stated in the prompt and cut to; a longer finding counts as `parse_failed`. |
| `observer_feedback_seconds` | `20` | How long the Useful/Not useful row stays after Dismiss. |
| `observer_list_max` | `50` | Most findings each remembered list (reported, disputed, not relevant) keeps. |
| `observer_keep_days` | `30` | Observer files older than this are pruned at session start. |
| `observer_analysis_enabled` | `true` | Run the catch-up. Off, ended sessions are not analyzed; live checks are unaffected. |
| `observer_analysis_model` | plugin.json | Catch-up analysis model (a cost lever; see "Model and effort"). |
| `observer_analysis_effort` | plugin.json | Catch-up analysis effort, passed as `--effort` (a cost lever; see "Model and effort"). |
| `observer_analysis_bare` | `false` | Pass `--bare` (see above; breaks OAuth-login auth). |
| `observer_min_lines` | `300` | Skip the catch-up for a not-yet-analyzed session with fewer transcript lines (see "Short sessions and run usage"); `0` analyzes every session. |
| `observer_idle_seconds` | `900` | How long a transcript must be unchanged before the catch-up treats its session as ended; keep above the longest single turn. |

An invalid value falls back to its default, and session start writes one `option_invalid` usage row
naming the key.

## Self-trigger guard

A SessionStart hook fires on every session start, including the catch-up's own analysis `-p` run.
The hook runs only when the shared attended predicate holds (`hooks/session-attended.sh`, generated
from `lib/session-attended.sh`: a person attends the session, so the `-p` run and background sessions
never arm), skips when the stdin `agent_type` field is present (subagent / `--agent` run),
skips `source` values other than `startup`/`resume`, and skips when `SESSION_FLOW_OBSERVER_ANALYSIS`
is set (the analysis run's own marker). The module loads in that run too and checks the same marker
and `isInteractive`, so the analysis run gets no live checks. A per-session lock held by a **live pid
is never reclaimed** (staleness is a dead pid; age is only a fallback when liveness is unknowable).

## Findings-return channel

- **Durable ledger, the primary channel.** Redacted findings append to this session's `running-retro` ledger
  (`<memory_dir>/running-retros/`), matched by `session_id` frontmatter, read by a later in-session
  checkpoint. No new plumbing beyond the existing ledger-on-disk model. Before its first ledger write
  the observer runs the self-ignore guard on the memory root (ensures
  `<memory_dir>/.gitignore` contains `*`; refuses a repo-root memory root; never the consumer's root
  `.gitignore`). A later catch-up of the same session starts from the prior run's stored byte
  offset, so an already-analyzed span is not re-analyzed into a duplicate ledger entry.
- **`SendMessage`** is reserved for the case where findings must reach a still-running session.
  Reaching another session is cross-session messaging, not an agent-teams surface: "Cross-session
  messaging requires Claude Code v2.1.224 or later on macOS, Linux, and WSL 2, and v2.1.234 or
  later on native Windows", and "When a session meets the requirements, messaging is on with
  nothing to enable" (both verbatim, verified 2026-08-24 against
  <https://code.claude.com/docs/en/cross-session-messaging>; recheck trigger: a Claude Code
  changelog entry touching cross-session messaging or its availability). It stays non-default
  here for three reasons: the observer cannot grant consent on
  the target session's behalf (the receiver's inbound controls can hold or refuse the message), a
  still-running receiver reads it only between tool calls during its active turn, and the durable
  ledger is the crash-safe, auditable primary.
- **desktop-notification** is not usable: it is bound to Claude Code's own `Notification` events, not
  arbitrary external triggers, and its OS toast is macOS/Linux only.

## Deferred alternatives (with triggers)

- **`retro` parser in the analysis run.** Deferred while the analysis is Read-only over untrusted
  data. **Trigger:** a sandbox that can run the parser safely over untrusted transcript content.
- **Prose-inferred memory root.** Both parts write under `<project>/.work`; neither can do retro's
  rung-2 inference of a `memory_dir` documented only in `CLAUDE.md` or rules prose, which needs an
  in-session agent. **Trigger:** a safe headless inference path.
- **Cross-session continuity.** Neither part writes the `previous_running_retro` /
  `previous_session_id` pointers, because applying retro's Phase 1.0 continuity gate needs an
  in-session judgment; a later in-session checkpoint reconciles them. **Trigger:** a safe headless way
  to resolve the continuity gate.
- **Cross-session spend report.** Each check's usage is in its session's live usage file and each
  catch-up run's in its status file; totals across sessions are `harness-ops:observability`
  territory. **Trigger:** a need to report observer spend across sessions.
