---
description: "The return contract every agent a plugin skill dispatches reports in: problems first, one fenced block, every claim graded off disk by the parent, preloaded into the agent definition and dispatched only."
user-invocable: false
disable-model-invocation: false
---

# Return contract

This is the one return shape every agent dispatched by a plugin skill reports in. Your final
message is the only thing the orchestrator sees. The parent parses the fenced block below and
grades every claim in it against disk, so a claim about your own run is evidence of nothing until
the parent's own gate confirms it. This is your output format, not a procedure to run.

## The core block, problems first

Report problems before successes. A parent that has to read to the end of a payload to learn the
run failed has already spent the context the error was meant to save.

```yaml
problems:            # FIRST. STOPs, deviations, failed gates, anything not done. [] if none.
  - kind: stop | deviation | gate-failed | not-done
    what: <one line>
    evidence: <file, line, or command output, one line>
verdict: complete | partial | stopped
results:
  files_created: [<relative paths>]
  files_edited: [<relative paths>]
  commit: <sha or none>
  gate: pass | fail | not-run
counts:
  <name>: <n>
open_questions:
  - <question, with a one-line recommended default>
```

Fields appear in that order. `problems:` is `[]` when there are none, never omitted.

**Extension fields go after `counts:` and before `open_questions:`**, so the closing key is always
the same one. An extension exists only where the agent definition or the dispatch brief names it,
and this contract never redefines one. The discovery agents carry `preload_token`,
`topic_as_received` or `scope_as_received`, `persistence`, `artifact`, `sidecars`, `coverage` and
`verification`; the implementation worker carries its worktree, branch and pushed state. Those are
per-agent extensions, not a second core.

**Every value under `counts:` is a claim, and so is `results.gate`.** The parent runs the gate
itself and reads the counts off disk. Reporting them anyway is how a disagreement becomes visible,
which is the whole reason both sides exist.

## Structure cap

Your final message is **exactly one fenced YAML block followed by at most 5 bullets, and nothing
else**. No preamble, no closing summary, no diffs, no file bodies, nothing resembling a transcript.

- Never restate this schema in your report.
- Every path is relative to the worktree root. Absolute paths cost more than they explain.
- The cap is structural, not a word count. Five bullets is a ceiling, not a target.

## Parsing: the fenced block, and two trailers around it

A parser anchors on the fenced block and tolerates exactly two things around it:

- a leading `[harness: ...]` line before the block, and
- the Agent tool's trailer glued onto the end of the last line, carrying the agent id and a
  `<usage>` element with `subagent_tokens`, `tool_uses` and `duration_ms`.

**Cost numbers come from that trailer and are never self-reported.** You cannot observe your own
token spend, and an estimate is worse than no number at all.

*Claim.* A dispatched subagent's result reaches the parent through the Agent tool, and in this
harness the returned text carries an agent-id and `<usage>` trailer appended to the final message
with no separating newline.
*Basis.* [Create custom subagents](https://code.claude.com/docs/en/sub-agents) documents the Agent
tool and the subagent result it returns. The glued trailer's exact shape is an observed shape of
that returned text rather than a documented format, and is recorded here as an observation.
*As of.* 2026-09-13.
*Recheck trigger.* A Claude Code release note touching the Agent tool result format.

## `commit: none` is allowed

On a red gate, leave the tree uncommitted, report `commit: none` with `results.gate: fail`, and
name the failure in `problems:`. That is a correct return, not a failed one. Committing over a red
gate to avoid an empty `commit:` field is the failure.

## `status: truncated` for a capped run

An agent under a turn cap cannot observe its remaining budget, so "leave a turn spare" schedules
against a limit you cannot see. Emit the block **early** with `status: truncated` and keep it
current at each phase boundary. A stop at any point after that leaves the parent a well-formed
payload instead of silence.

`status:` describes the run and takes `complete` or `truncated`. It never describes the disk. A run
that finished every phase and could not write its artifact is complete, not truncated, and reports
the write failure through its own agent's persistence field.

## `preload:` and `preload_token:`

An agent whose definition preloads a skill echoes that skill's token verbatim as `preload_token`
and states how the body reached it in `preload: fired | fallback`:

- `preload: fired` means the body was already in context at startup and you read no skill file.
- `preload: fallback` means you read it from disk. Fallback is an accepted recovery, not a defect.

A `skills:` entry that fails to resolve is skipped silently, so the token is the only evidence that
the discipline reached you. Never report a token you found by reading the skill file as `fired`.

**When no body reached you at all**, return `preload_token: MISSING` and `verdict: stopped`.
`verdict: stopped` is terminal and **not resumable**: no resume can deliver a skill body that never
loaded. The remedy is to fix the preload or the fallback path and re-dispatch. A resume ladder
never applies to it.

## A fence widening goes in `open_questions:`

When the work needs a file the fence keeps FORBIDDEN, report the widening in `open_questions:`,
naming the consumer, with a one-line recommended default. **Never report it as
`kind: deviation`.** That kind is reserved for harness friction and scope events, so a parent can
tell a widening from friction without reading `what:`.

STOP means stop crossing the fence, not stop working: finish everything the fence allows, then
report.

## Verifier dispatch

These clauses bind any parent that dispatches a fresh-context verifier, and the verifier it
dispatches:

- The parent hands over the binary acceptance criteria and a pointer to the artifact, and
  **withholds its own rationale**. The verifier audits the artifact, not the story behind it.
- The verifier returns this same core block, adding a per-criterion PASS or FAIL and, for every
  FAIL, the evidence behind it.
- The verifier decides every criterion. Where one genuinely cannot be decided from the evidence
  available, it returns that criterion as INCONCLUSIVE prose in `problems:`, naming what is
  missing. That is not `verdict: stopped`.
- **The verifier writes nothing** and gets no Edit grant. It has no artifact to update.
- **The parent writes the `verification:` line into the artifact**, copying the enum verbatim out
  of the verifier's returned `verdict:`.

## `verdict` and `status` carry four separate meanings

Keep them apart: the payload's `verdict:` is the outcome of the run, the payload's `status:` is
whether the run finished or was cut off, the dispatch-artifact gate script check-dispatch-artifact.sh
prints a `verdict` line that grades what is on disk, and that same script's
`status=usable|unusable` is the value of that disk grading.
