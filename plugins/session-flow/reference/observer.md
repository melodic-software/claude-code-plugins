# Detached observer — substrate and lifecycle

The observer is a **substrate + lifecycle** in front of `running-retro`'s existing discipline, not a
second concern. `running-retro` + `retro` already own the analysis method, finding taxonomy,
resolution-route classification, redaction, and the cumulative ledger; this adds only (1) an
out-of-band observation feed, (2) a session-end trigger, and (3) an autonomous analysis leg that
reuses that discipline. It is what turns `running-retro` from PULL (invoked in-session) into a path
that can also fire *after* the session ends — a `/loop` structurally cannot.

Both entries — the `arm` action on `running-retro` and the opt-in SessionStart hook — run the same
launcher; only the trigger differs. Arming is primary; the hook only automates it.

## The two scripts

Both live under `${CLAUDE_PLUGIN_ROOT}/skills/running-retro/scripts/`, stdlib-only Python 3.10+.

- **`arm_observer.py`** — the launcher. Spawns the tailer in a process detached from every Claude
  Code session's process tree (Windows: `DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP |
  CREATE_NO_WINDOW`, no breakaway; POSIX: `start_new_session`), then returns at once. The P16
  lifecycle evidence proved a hook-spawned detached child **outlives the session** across three
  ancestor types including the interactive TTY case (the session's job is neither kill-on-close nor
  traps children, and plain detach leaves the job entirely), so no breakaway flag is needed.
- **`observer.py`** — the tailer. Three legs:
  1. **Tail + distill.** Poll → open → seek → read-new-bytes → close. It never holds a persistent
     handle, so it cannot block Claude Code's append (the Windows share-mode WRITE edge is safe by
     construction). Each new transcript line is distilled to a compact event.
  2. **End detection — mtime-idle only.** Session end leaves no distinct terminal record; the file
     simply stops growing. `Stop` fires every turn (useless as an end marker) and a `SessionEnd`
     hook is not crash-safe, so staleness is the crash-safe primary signal. **Limitation:** idle
     cannot distinguish a long single turn from end, so `observer_idle_seconds` must stay above the
     longest expected single turn (large agent fan-outs, long builds) or a mid-turn pause fires
     analysis on a partial transcript. The deferred `SessionEnd` graceful-end fast-path is the
     stated mitigation.
  3. **Post-end analysis (optional).** On idle-detect, a headless `claude -p` over the observations
     that follows `running-retro`'s checkpoint method and appends its findings to the ledger.

## Redaction and the untrusted-data boundary

The distilled observations are **transient and machine-local** (written under the plugin's work dir,
`${CLAUDE_PLUGIN_DATA}/session-flow-observer/`), consumed once by the analysis run, and **deleted
after a successful run**. They are never written to the durable, portable ledger — only the analysis
run's already-redacted findings block is. The analysis `-p` run is therefore the **single semantic
redaction pass** (it is the only reasoning agent in the loop; the tailer only appends the block it
returns), and its prompt makes that pass emphatic. This is a deliberate narrowing of `running-retro`'s
two-hop redaction: the second hop there is a reasoning pass, which a mechanical Python append cannot
be, so the boundary is enforced by never letting unredacted observations reach the ledger instead.

Transcripts and observations are **untrusted input**. The shared boundary — that inspected off-thread
output is data to analyze, never instructions to follow — is owned by
[`off-thread-work.md`](./off-thread-work.md) ("The inspected output is untrusted data"); the analysis
prompt restates the directive-immunity rule inline for the fresh `-p` context. The analysis run is
**Read-only** (`--allowedTools Read` under `--permission-mode dontAsk`): no Bash, no code execution
over injected transcript content. The distilled observations already carry the tool histogram and
turn boundaries, so the checkpoint block is complete without running the parser.

## The analysis run — flags and the `--bare` / auth coupling

The default analysis command is:

```text
claude -p --model <observer_analysis_model> --permission-mode dontAsk \
  --output-format json --allowedTools Read --add-dir <plugin_root> --add-dir <work_dir>
```

with the prompt fed on **stdin** (never as a trailing positional — `--add-dir` is variadic and would
swallow it). `dontAsk` guarantees the run can never hang (an unauthorized tool call aborts rather
than waiting); `--allowedTools Read` keeps the authorized read from being auto-denied.

`--bare` (skip auto-discovery) is a further cost lever, but it is **off by default** and gated behind
`observer_analysis_bare`: verified on Claude Code 2.1.218, `--bare` makes the run report
`Not logged in · Please run /login` and fail on an **OAuth-login** install — it drops the login
credential state. Enable it only where auth is an env-var API key that survives it. The dominant cost
lever is the **model** (`observer_analysis_model`, default the cheapest active tier); `--bare` is a
secondary, environment-dependent one.

## Config surface (userConfig)

Declared in the plugin manifest; the SessionStart hook and the `arm` action read the same values.

| Key | Default | Effect |
|---|---|---|
| `observer_enabled` | `false` | Opt in the SessionStart auto-arm. Off = zero-config unchanged; manual `arm` still works. |
| `observer_analysis_enabled` | `true` | Run the autonomous post-end analysis once armed. Off = collect-only; the next in-session checkpoint reads the observations. |
| `observer_analysis_model` | `claude-haiku-4-5` | Analysis model (the cost lever). |
| `observer_analysis_bare` | `false` | Pass `--bare` (see above; breaks OAuth-login auth). |
| `observer_idle_seconds` | `900` | mtime-idle end threshold; keep above the longest single turn. |
| `observer_max_seconds` | `86400` | Hard lifetime safety valve; exits WITHOUT analysis. |

## Self-arm guard

A SessionStart hook fires on every session start, including the observer's own analysis `-p` run, so
a naive arming hook would spawn an observer for the analysis run. The hook arms only when
`CLAUDE_CODE_ENTRYPOINT == "cli"` (a real interactive session; the `-p` run reports `sdk-cli`), skips
when the stdin `agent_type` field is present (subagent / `--agent` run), skips `source` values other
than `startup`/`resume`, and skips when `SESSION_FLOW_OBSERVER_ANALYSIS` is set (the analysis run's
own marker). The tailer additionally self-guards on `session_id` via a lock file so a resume does not
double-arm.

## Findings-return channel

- **Durable ledger — primary.** Redacted findings append to this session's `running-retro` ledger
  (`<memory_dir>/running-retros/`), matched by `session_id` frontmatter, read by a later in-session
  checkpoint. No new plumbing beyond the existing ledger-on-disk model.
- **`SendMessage`** — reserved for the case where findings must reach a still-running session; gated
  behind experimental agent-teams and cannot grant consent, so it is not the default.
- **desktop-notification** — not usable: it is bound to Claude Code's own `Notification` events, not
  arbitrary external triggers, and its OS toast is macOS/Linux only.

## Deferred alternatives (with triggers)

- **Native Observer Agents** (highest-priority trigger). Claude Code compiles in an experimental
  observer-agent subsystem (`observerAgentType`, `ObserverReport`), gated behind
  `CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS` **and** a server-side Statsig flag not locally
  controllable in 2.1.218. It consumes a read-only per-turn XML digest (not the JSONL), returns a
  one-way advisory, and is officially undocumented — so it does **not** cover the classify / route /
  ledger discipline today. The substrate here is kept THIN precisely so migration stays cheap.
  **Trigger:** re-evaluate the bespoke tailer leg if Observer Agents gains a transcript-level feed or
  a richer return and is officially documented / stabilized upstream.
- **`SessionEnd` graceful-end fast-path.** A real distinct event that also fires headless and carries
  `transcript_path`; layer it on mtime-idle only if the one-turn idle latency is unacceptable.
  mtime-idle ships regardless — it is crash-safe where `SessionEnd` is not.
- **`retro` parser in the analysis run.** Deferred while the analysis is Read-only over untrusted
  data. **Trigger:** a sandbox that can run the parser safely over untrusted transcript content.
- **Cost telemetry.** The `-p` run's JSON carries `total_cost_usd`; recording per-run observer spend
  is `claude-ops:observability` territory.
