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
after a successful run** — never written to the durable, portable ledger; only the analysis run's
redacted findings block is. Redaction is **two-hop**, matching `running-retro`'s ledger contract: the
`-p` run performs the **semantic** pass (it is the only reasoning agent in the loop; its prompt makes
that pass emphatic), and the tailer's `_redact()` runs a **mechanical shape-marker sweep** on the
returned block at the ledger write — conservative regex patterns for API keys, tokens, private-key
blocks, connection strings, JWTs, and emails, replaced with shape markers, never the value — as
defense in depth over the semantic pass. In collect-only mode (`observer_analysis_enabled` off) no
analysis runs, so the unredacted observations are **retained** under the machine-local plugin work dir
for manual inspection and are never promoted to the ledger.

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
| `observer_analysis_enabled` | `true` | Run the autonomous post-end analysis once armed. Off = collect-only: the distilled observations are retained under the plugin work dir for manual inspection; the observer does not itself analyze or write the ledger. There is no automatic in-session consumer of the observations today (deferred; see below). |
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
  checkpoint. No new plumbing beyond the existing ledger-on-disk model. Before its first ledger write
  the observer runs the topic-docs self-ignore guard on the memory root (ensures
  `<memory_dir>/.gitignore` contains `*`; refuses a repo-root memory root; never the consumer's root
  `.gitignore`). On a `source=resume` re-arm the observer resumes from the prior run's persisted byte
  offset, so an already-analyzed span is not re-analyzed into a duplicate ledger entry.
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
- **Headless prose-inferred memory root.** The SessionStart hook resolves `memory_dir` mechanically
  (the `.claude/topic-docs.yaml` concern file, then the `.work` default); it cannot do retro's rung-2
  inference of a `memory_dir` documented only in `CLAUDE.md`/rules prose (that needs an in-session
  agent). A hook-armed observer would then write under `.work` while in-session checkpoints look under
  the prose-documented root. The manual `arm` entry resolves it in-session and is unaffected.
  **Trigger:** a mechanical concern-file declaration of `memory_dir` (recommended), or a safe headless
  inference path.
- **Headless cross-session continuity.** The opt-in SessionStart hook arms the observer without the
  `previous_running_retro` / `previous_session_id` continuity pointers, because a detached process
  cannot safely apply retro's Phase 1.0 continuity gate (blindly linking the newest handoff could
  splice an unrelated session). The manual `arm` entry passes them (it resolves the chain in-session);
  a later in-session checkpoint reconciles continuity for hook-armed sessions. **Trigger:** a
  safe headless way to resolve the continuity gate.
- **In-session consumer of collect-only observations.** Collect-only mode retains the distilled
  observations under the plugin work dir, but no code path in the in-session `running-retro` checkpoint
  reads them today — they are for manual inspection. **Trigger:** wire the checkpoint flow to fold a
  retained observations file into its analysis (weigh against the redaction boundary — the observations
  are unredacted, so any promotion to the ledger must pass the same two-hop redaction).
- **Cost telemetry.** The `-p` run's JSON carries `total_cost_usd`; recording per-run observer spend
  is `claude-ops:observability` territory.
