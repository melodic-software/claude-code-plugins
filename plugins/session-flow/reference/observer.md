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

**When.** On the main thread only (never a subagent's steps), on every 6th model step of a turn
(`observer_step_check`, on by default), and, when `observer_turn_end_check` is on, once at the end of
each turn that ran tools and was not interrupted. One check runs at a time per session: a trigger
while one is in flight starts none. The checks run only where a person is at the prompt (the
`session.start` event's `isInteractive`) and never in the catch-up's own analysis run
(`SESSION_FLOW_OBSERVER_ANALYSIS` set).

**What.** A check is a `$.model.fork` with a prompt only: it reuses the main thread's cached
request, has no tools and writes nothing to the transcript. The prompt asks for at most one fault in
four categories (`process`, `decision`, `verification`, `instruction`), each tied to a rule or owner
decision the session's own instructions or conversation state, and defaults to `finding: none`. The
reply is labeled lines, parsed leniently; a reply with no rule, an unknown category or a field over
240 characters counts as `parse_failed`.

**Stale and repeated replies.** A reply that arrives after the next turn started, or after the
session ended, is dropped as `stale`. Findings already reported (the last 50, across sessions) and
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
prompt, with a blank line above and below it as the built-in side agent's has, led by a `◆` (`*` when
`TERM` is `dumb`), `observer`, its category and the trigger that found it
(`step 12`, `turn end`), with buttons `5` Send to Claude (appends a quoted note to the prompt box,
marked as background the person did not write), `6` Noted (marks the ledger entry confirmed), `7`
Dispute (marks it disputed and suppresses it for good), `8` Why (shows the rule, the evidence, this
session's check cost and how to pause) and `9` Dismiss. The hotkeys are `5` to `9` because the
built-in side agent's band uses `1` to `4` and `0`, and a hotkey two plugins share presses neither.
Nothing reaches the main conversation unless the person sends it. After Dismiss, one row offers
the built-in side agent's answers on our hotkeys: `5` That was helpful, `6` Not relevant, `7`
Couldn't understand, `8` Turn off checks (live checks stop for this session only; `/observer off`
pauses every session) and `9` Close. It clears itself after 20 seconds; the answer goes to the usage
file, so `/observer` can show how often findings were worth showing. Not relevant also adds the
finding to a stored list the next checks are told not to report, nor faults like it; Couldn't
understand makes every later check ask for plain words. Nothing is sent outside the machine.

**Auto-clear.** While a finding is shown, the next check is told about it and answers
`resolved: yes` when the assistant has since fixed it; the band then clears and the ledger records
it as resolved by the assistant.

**Backoff.** A finding the person types past twice without answering clears. Past two such findings
in a row, the next 1, 2, 4, 8 and then at most 16 eligible checks are skipped; any button resets the
count.

**Usage.** Each check appends one line to `<plugin data>/session-flow-observer/live-<session>.jsonl`:
time, trigger, turn, step, outcome, latency and the fork's token usage; each answer (sent, noted,
disputed, dismissed, ignored, resolved, and the answers after Dismiss) appends one too. That file is
how a day's cost is read, and its presence tells the catch-up this session had live checks.

**Storage and retention.** One usage file per session and per machine, each with one writer, so no
lock is needed; an agent reads them with `jq` or a line search, no index required. Session start
deletes usage files not written for 30 days and the retired background observer's `observations-*`
and `observer-*.log` files. Each machine (a Windows host and its WSL, for one) keeps its own data
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
| `observer_step_check` | `true` | Live check on every 6th model step of a turn. |
| `observer_turn_end_check` | `false` | Live check at the end of each tool-using turn (see "Cost" above). |
| `observer_analysis_enabled` | `true` | Run the catch-up. Off, ended sessions are not analyzed; live checks are unaffected. |
| `observer_analysis_model` | plugin.json | Catch-up analysis model (a cost lever; see "Model and effort"). |
| `observer_analysis_effort` | plugin.json | Catch-up analysis effort, passed as `--effort` (a cost lever; see "Model and effort"). |
| `observer_analysis_bare` | `false` | Pass `--bare` (see above; breaks OAuth-login auth). |
| `observer_min_lines` | `300` | Skip the catch-up for a not-yet-analyzed session with fewer transcript lines (see "Short sessions and run usage"); `0` analyzes every session. |
| `observer_idle_seconds` | `900` | How long a transcript must be unchanged before the catch-up treats its session as ended; keep above the longest single turn. |

## Self-trigger guard

A SessionStart hook fires on every session start, including the catch-up's own analysis `-p` run.
The hook runs only when `CLAUDE_CODE_ENTRYPOINT == "cli"` (a real interactive session; the `-p` run
reports `sdk-cli`), skips when the stdin `agent_type` field is present (subagent / `--agent` run),
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
