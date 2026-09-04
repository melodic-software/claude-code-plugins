# PostToolUse hook audit: measured findings

Session `claude/posttool-hooks-review-ji6rl5`, 2026-09-04. Read-only audit of the fleet's 26 wired
`PostToolUse` handler rows, plus a doc-alignment pass against a same-day raw fetch of the official
hooks reference. No hook, plugin, or convention file was modified.

## Measurement method

Wall-clock via `EPOCHREALTIME` around direct hook invocation, fed realistic `PostToolUse` payloads
on stdin, samples written under the measured cwd inside the repository. A `bash -c :` spawn floor S
is interleaved with every sample; figures are given in both absolute ms and spawn-equivalents. Host
is a Linux container with S between 1.8 and 2.3 ms across runs, N per row between 8 and 20.

**Method caveat, and it applies to this repo's own harness.** `docs/conventions/hook-budget`
normalizes to spawn-equivalents so figures "survive a change of host". That holds only for
spawn-dominated hooks. `markdown-format`'s cost is mostly Node startup plus a `markdownlint` scan,
which is near-constant in absolute ms and not proportional to S, so dividing it by a 2 ms floor
yields a large ratio and the doc's conversion to an 80 ms reference host then predicts a figure that
is almost certainly a large overestimate. Spawn-equivalents need a per-hook spawn-dominated versus
work-dominated split before any Windows projection built on them is trustworthy.

## Per-hook cost

| Hook | On a file it handles | On a `.txt` it does not |
| --- | --- | --- |
| `skill-reference-verify` (`.md` carrying `/plugin:skill` refs) | **622.1 ms (352 S)** | 33.9 ms when the payload carries no refs |
| `markdown-format` (`.md`) | 371.2 ms (174 S) | gated out by `if:`, no spawn |
| `ruff-format` (`.py`) | 91.9 ms (44 S) | gated out by `if:`, no spawn |
| `guardrails` verifier trio | 88.7 ms (31 S) | **79.3 ms, ungated, full cost** |
| `bash-format` (`.sh`) | 84.0 ms (43 S) | gated out by `if:`, no spawn |
| `skill-usage-audit` | 84.4 ms (43 S) | n/a |
| `typos-format` (`.md`) | 69.8 ms (38 S) | **76.3 ms, ungated, full cost** |
| `biome-format` (`.ts`) | 53.2 ms (26 S) | gated out by `if:`, no spawn |
| `eol-normalizer` (`.md`) | 44.2 ms (22 S) | **48.7 ms, ungated, full cost** |
| `tool-failure-audit` | 26.3 ms (14 S) | n/a |

Parallel wall as Claude Code actually dispatches the set: an in-repo `.md` Write costs **345 ms**;
an in-repo `.txt` Write costs **83 ms**, and every millisecond of that is the three ungated rows.

## Finding 1: `skill-reference-verify` is the fleet's most expensive PostToolUse hook

`plugins/guardrails/hooks/skill-reference-verify.sh:200-213` builds a plugin index by running two
`jq` and two `tr` processes per manifest across 74 manifests, roughly 296 processes. The build is
lazy, gated at line 721 on `((${#REFS[@]}))`, so it fires only when the written markdown actually
carries a `/plugin:skill` reference. That describes most documentation in this repository.

Measured:

| | ms |
| --- | --- |
| Hook total, `.md` with 4 skill references | 622.1 |
| Hook total, same file with no references in the payload | 33.9 |
| The per-manifest index loop alone, 74 manifests | 547.7 |
| One batched `jq` doing the same work | 5.7 |

About **542 ms of the hook's 622 ms is recoverable**, which is 87 percent of its cost, for a single
batched `jq` in place of the loop. This is the largest concrete performance win identified in the
audit and it revises the assumption that `markdown-format` is the dominant per-Write cost.

**Measurement rule, not a war story.** A first pass measured this hook at 33.9 ms because the
synthetic payload carried `tool_input.content` of `"x"`. A `PostToolUse` hook reads the payload
content, not the file on disk, so the index never built and the harness measured a no-op and would
have reported it as the hook's cost, an 18x error. This is a general harness-design defect rather
than a fact about this hook: **any measurement of a content-scanning hook must put the real file
text in the payload.** Paired with the spawn-equivalents caveat above, it is one of two method
defects this audit found by measuring rather than reading, and both belong in the method section of
any successor harness. Both are encoded as rules at the top of
[`harness/measure-posttooluse.sh`](harness/measure-posttooluse.sh), which reproduces every figure in
this document.

## Finding 2: a disabled hook is not free

Every hook sources `lib/hook-utils.sh` before reading its own kill switch. In every hook inspected
the order is the same: `markdown-format` sources at line 38 and checks at 40, `typos-format` at 87
and 89, `eol-normalizer` at 34 and 38.

| | ms | vs floor |
| --- | --- | --- |
| No-op script | 2.1 | 1.3 S |
| Sourcing `lib/hook-utils.sh` alone | 5.5 | 3.4 S |
| `markdown-format` with its switch set to `false` | 5.6 | 3.0 S |
| `typos-format` with its switch set to `false` | 5.5 | 2.9 S |
| `eol-normalizer` with its switch set to `false` | 6.1 | 3.5 S |

A fully disabled hook costs what loading the library costs, because loading the library is the only
thing it does. The library is 2,766 lines and exists in 18 byte-identical copies (17 under
`plugins/*/hooks/` plus `lib/`), so the parse is paid on every fire of every hook.

Hoisting a two-line environment read above the `source` line recovers about 2 S per disabled hook
across roughly 44 switch sites. Reaching an actual zero requires `if:` in `hooks.json`, which
prevents the spawn entirely, but `if:` matches permission-rule patterns and cannot express an
environment variable, so it cannot carry a kill switch.

## Finding 3: telemetry emission is free

`HOOK_TELEMETRY_SINK` wired against a null sink versus unset measured within noise on both
`eol-normalizer` (46.1 vs 44.3 ms) and `typos-format` (71.3 vs 69.5 ms). The fire-and-forget
background dispatch in `docs/conventions/hook-telemetry` works as designed. Whatever problems the
logging pipeline has, producer-side latency is not among them.

## Finding 4: three PostToolUse rows carry no `if:` predicate

`typos-format`, `eol-normalizer`, and the `guardrails` verifier trio spawn on every `Write` and
`Edit` regardless of file type, and measurably pay near-full cost on files they have nothing to say
about. The six extension-gated formatters spawn zero processes on a non-matching file. Fleet-wide,
`if:` is present on 27 of 55 handlers.

## Doc alignment against the official reference

Verified against a raw-markdown fetch of <https://code.claude.com/docs/en/hooks.md> and
<https://code.claude.com/docs/en/cli-reference.md> on 2026-09-04. A summarizing fetch got two of
these backwards, so every claim below was checked against raw source.

**The repo's existing conventions were confirmed accurate**, not stale:

- `docs/conventions/hook-observability` is correct that `systemMessage` is the user channel
  ("Warning message shown to the user") and `additionalContext` the model channel (inserted into
  Claude's context as a system reminder).
- The `Ctrl+O` / `--verbose` async-notification sentence is verbatim intact.
- `--include-hook-events` is real and current. It is documented in the CLI reference rather than the
  hooks reference, and emits `hook_started`, `hook_progress` and `hook_response` under
  `--output-format stream-json`. **Do not "fix" the observability doc on this point.**
- `tool_response`, not `tool_output`, is the correct `PostToolUse` input field.

**Genuine deltas:**

- Hook output over 10,000 characters now overflows to a file with a preview and path rather than
  being truncated. The repo's docs say "cap" only.
- The `additionalContext` cap is 10,000 characters per value, with no shared pool across hooks
  ("Claude receives all of the values").
- A separate 2,000-character cap, **shared across every hook responding to one call**, governs the
  auto-mode classifier note (`classifierContext`) and not `additionalContext`. That section also
  states the note is ignored for background hooks and discarded on read-only lookups.

**Refuted during the audit.** A peer session reported `plugins/typos-format/hooks/typos-format.sh:700`
as a correctness bug for self-capping `additionalContext` at 8,000 against the 2,000-character shared
pool. The 2,000 cap sits under `#### Annotate a result for the auto mode classifier` and governs the
classifier note. `typos-format` at 8,000, and its `systemMessage` at 4,000, are both inside the real
10,000 limit. There is no bug at that line. The finding was withdrawn by its author after review.

## Unused schema levers

None of the following appears anywhere in the fleet's hooks: `async`, `asyncRewake`, `args` (exec
form), `updatedToolOutput`, `classifierContext`, or the `http`, `mcp_tool`, `prompt` and `agent`
handler types. `tool_use_id` appears in no hook, though it is the correlation key that matches
Claude Code's own `claude_code.tool_result` and `tool_decision` telemetry events.

`classifierContext` is **PostToolUse-scoped**. The PreToolUse decision-control table carries exactly
`permissionDecision`, `permissionDecisionReason`, `updatedInput` and `additionalContext`. Any plan to
soften a PreToolUse block into an auto-mode classifier hint is not achievable; the available levers
there are `permissionDecision: "ask"` and `"defer"`.

## Visibility gaps

- `description` on `hooks.json`, which labels a plugin's hooks in the `/hooks` menu, is absent in
  **20 of 20** plugins.
- `statusMessage` is present on 53 of 55 handlers.
- On `PostToolUse`, exit code 2 "shows stderr to Claude; the tool already ran". Combined with
  `statusMessage` being the only during-run surface, a user has no channel showing what a PostToolUse
  hook did. This matches the operator's report of not noticing hooks unless they error.

## Ordering and capture, for the logging design

- All matching hooks run in parallel and no ordering control exists. Order can only be reconstructed
  after the fact, which makes timestamp resolution a schema decision.
- A handler defined in two settings files is deduplicated and runs once, but a plugin's copy stays
  separate, so a marketplace plugin's hook is never deduplicated against a consumer's own.
- `OTEL_*` is stripped from hook subprocesses, so a hook cannot emit real OpenTelemetry.
  `TRACEPARENT` **is** passed through when tracing is active, which is a stronger correlation key
  than anything currently in the envelope.
- Under `ENABLE_BETA_TRACING_DETAILED`, Claude Code emits its own `claude_code.hook` span carrying
  `hook_event`, `hook_name`, `num_hooks`, `num_success`, `num_blocking`, `num_non_blocking_error` and
  `num_cancelled`, covering every hook including third-party ones with no opt-in. It is aggregate per
  event, not per-hook duration, so it complements the envelope rather than replacing it.
- Claude Code configures no retention of its own. Retention is entirely the consuming pipeline's
  problem.

## Guard evidence relevant to ADR-0003

`plugins/guardrails/hooks/block-hook-bypass.sh` (1,339 lines) fired four times across three
independent sessions in one afternoon with zero true positives, none of which were hunting for it.
Directly observed here: one block on a write to the harness-designated scratchpad directory.
Reported by the sessions that experienced them, and recorded with that attribution rather than as
first-hand: one block on an untracked `.work/` interview-ledger write, and two benign scratch writes,
one of which was triggered by text that merely **quoted the guard's own scope note**.
`CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_SCRATCH_ROOTS` defaults to empty, so none of those paths is
exempt by default.

ADR-0003 clause 3 names this pattern as disqualifying: precision is 0% whether the firing count is
389 or 1. Clause 4 is the operative one, though, and it re-files rather than deletes: the oracle here
is sound and only the scope is wrong, which is the same disposition the withdrawn path guard received
in #1314. The verdict the PreToolUse lane settled on is **withdraw from the current default-on scope
and re-file for rescoping**, with the immediately shippable piece being a non-empty scratch-roots
default plus a repro-first stay-quiet test per `docs/conventions/hook-precision`.

The guard's own header disclaims its adversarial value ("An LLM never emits this form; the deny-list
plus human oversight are the adversarial layers") and documents a detection hole. Every PostToolUse
`Write|Edit` hook it protects is advisory and always exits 0, so a successful bypass costs a missed
formatting pass while a false positive costs a blocked tool call and rework.

This hook is owned by the PreToolUse lane and is recorded here only as evidence.
