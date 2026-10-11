# Upstream source: TypeSafe Jev, the "System One" decision model

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [Lane D: Jev as a dependency](#lane-d-jev-as-a-dependency)
- [Lane G: guardrails and security posture](#lane-g-guardrails-and-security-posture)
- [Lane R: routing, context and reads](#lane-r-routing-context-and-reads)
- [Interview queue](#interview-queue)

Provenance record for everything in this marketplace vetted against TypeSafe's Jev model as two
videos pitch it; what Jev is and does is read live at the vendor pages under Source and
verification. One convention, one scoped record, per the shape
[claudedevs-cost-performance.md](claudedevs-cost-performance.md) set: lanes decide but never
implement, and a plain ADOPT row would point at a filed work item. This record has no ADOPT row.

## Status

Verdicts follow the repo-applicability menu of the IndyDevDan digest and our own evaluation in
[#5809](https://github.com/melodic-software/claude-code-plugins/issues/5809). No lane interview has
run; the open questions are in the [interview queue](#interview-queue). Nothing in this record
changes a plugin.

Our evaluation closed with a final no-go. Round 1 posed Jev against 29 decision points drawn from
this repository against `jev-1.13.0`, and every one failed the accuracy bar. Round 2 re-ran the
screening shapes on real, redacted data, the Bash PreToolUse screen among them, and every
deciding bar failed after a fresh-context review. The issue names the reopen condition: a new Jev
model, or a new use with a larger expected effect.

The Ray Amjad digest's menu also raises a data-egress decision (whether repository content may go
to a non-Anthropic model API at all). This record does not decide it; while the Jev REJECT row
stands, no use needs it.

## Source and verification

- Videos (correlate notes only, never the pointer):
  - IndyDevDan, "10 Levels of Jev For Agentic Engineers", 2026-09-28
    (correlate with `https://www.youtube.com/watch?v=_U-O5lYhJ7Q`). Digest:
    [knowledge-corpus `sources/videos/10-levels-of-jev-for-agentic-engineers-_U-O5lYhJ7Q`](https://github.com/melodic-software/knowledge-corpus/tree/main/sources/videos/10-levels-of-jev-for-agentic-engineers-_U-O5lYhJ7Q)
    (landed by knowledge-corpus PR #42).
  - Ray Amjad, Jev and Claude Code video
    (correlate with `https://www.youtube.com/watch?v=ScvXFi4MUSc`). Digest:
    [knowledge-corpus `sources/videos/jev-claude-code-the-cheapest-agentic-cod-ScvXFi4MUSc`](https://github.com/melodic-software/knowledge-corpus/tree/main/sources/videos/jev-claude-code-the-cheapest-agentic-cod-ScvXFi4MUSc)
    (landed by knowledge-corpus PR #39).
- Jev product facts point at the vendor docs: the
  [API reference](https://docs.typesafe.ai/api), the [models page](https://docs.typesafe.ai/models)
  and the [primitives page](https://docs.typesafe.ai/primitives). The launch post is a correlate
  note only (correlate with `https://typesafe.ai/blog/introducing-system-one-models-and-jev`).
- The Lane G and Lane R hook verdicts were derived on 2026-10-10 from
  [Prompt-based hooks](https://code.claude.com/docs/en/hooks#prompt-based-hooks), the prompt-hook
  [Response schema](https://code.claude.com/docs/en/hooks#response-schema),
  [PreCompact](https://code.claude.com/docs/en/hooks#precompact) and
  [Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails).
  Before acting on one of those rows, read the linked sections live.
- The Ray Amjad digest's verification corrected several of that video's product claims; read them
  in its [product and API findings](https://github.com/melodic-software/knowledge-corpus/blob/main/sources/videos/jev-claude-code-the-cheapest-agentic-cod-ScvXFi4MUSc/analysis/research/findings/jev-product-and-api.md)
  and check any one against the [API reference](https://docs.typesafe.ai/api) before relying on it.
- Figures: neither video's prices, multipliers, latencies or accuracy numbers are recorded here,
  and neither are #5809's measurements; read them at the source.

## Row schema

Each row is an [upstream-drift](../conventions/upstream-drift/README.md#required-parts) record.
**Topic** names the video's idea in our words; **Ours** names our mechanism with its repo path;
**Verdict** is our decision and its reasoning; **Pointer** is the exact docs section, or our own
evaluation where no docs page covers the topic; **As of** is when the pointer was last read.
Verdicts: **ADOPT** (with a filed work item), **REJECT** (with reason), **TRACK** (on a named
event), **COVERED** (already present, with evidence). Columns:

| Topic | Ours | Verdict | Pointer | As of |

Shared recheck trigger for every row: a re-fetch of the row's pointer no longer supports the
verdict. A row that names its own trigger in its cell adds it to the shared one.

## Lane D: Jev as a dependency

| Topic | Ours | Verdict | Pointer | As of |
|---|---|---|---|---|
| Jev as a dependency of any plugin, hook or skill | None. Hooks make no undeclared outbound network calls (`docs/migration-playbook.md`, plugin-acceptance review) | REJECT. Our evaluation failed every decision point in round 1 and every screening shape in round 2, and any use would send repository content to a third-party API; read the models page live for its current hosting terms. Recheck trigger: a Jev release after `jev-1.13.0`, or a new use with a larger expected effect than the ones #5809 tested; either one re-runs the #5809 harness, bar unchanged | Our evaluation: [#5809](https://github.com/melodic-software/claude-code-plugins/issues/5809); for the current model version, fetch the [models page](https://docs.typesafe.ai/models) live | 2026-10-10 |
| Agent-callable decision tool the agent writes its own questions for (level 10) | None; the main model already decides in context | REJECT. It adds a moving part that asks a smaller model a question the running model can answer, with no measured gain. | For how the vendor says an agent should use Jev, read its [Agent skill](https://docs.typesafe.ai/agent-skill) page live; for how an inline helper held on our data, read our evaluation [#5809](https://github.com/melodic-software/claude-code-plugins/issues/5809) (round 1, inline triage helper) | 2026-10-10 |

## Lane G: guardrails and security posture

| Topic | Ours | Verdict | Pointer | As of |
|---|---|---|---|---|
| Decision model as a tool-call guardrail (levels 4 and 6) | `plugins/guardrails/hooks/hooks.json` PreToolUse `Bash\|PowerShell` command hooks (`block-root-delete-target.sh`, `block-dangerous-git.sh`, `block-credential-read.sh`), deny rules and the sandbox; `check-bash-file-changes.mjs` runs the Write/Edit content guards on files a shell command changed, which narrows the shell-write bypass of a write guard; the scope residuals it does not examine are listed in its header comment ([#6674](https://github.com/melodic-software/claude-code-plugins/issues/6674)); auto mode tuned through `/harness-config:draft-auto-mode-rules` | COVERED. A classifier gate is a signal, never a control; the #5809 round 2 Bash screen failed on real commands. A future semantic gate must be a `command` hook that never allows, with `onFailure: "block"`: it returns `ask` in an interactive session and `deny` in an unattended lane, which carries no hook `ask` (`AGENTS.md`, "When to stop and when to keep going"), because of the prompt-hook and hook-failure limits in the three hook sections this row points at; read them live before designing one. Recheck trigger: a destructive command observed passing both the guardrails hooks and auto mode | [Prompt-based hooks](https://code.claude.com/docs/en/hooks#prompt-based-hooks), [Response schema](https://code.claude.com/docs/en/hooks#response-schema), [Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails), [Filesystem isolation](https://code.claude.com/docs/en/sandboxing#filesystem-isolation) | 2026-10-10 |
| Fail-closed posture for security guards | The shell guardrails hooks install `plugins/guardrails/hooks/abort-boundary.sh`, declare fail-open and emit a "guard did not run" notice (`plugins/guardrails/README.md`, "Every hook says so when it could not run"); `check-bash-file-changes.mjs` does not, and swallows unexpected errors silently ([#6905](https://github.com/melodic-software/claude-code-plugins/issues/6905)); no hook in the repo sets `onFailure` | TRACK. Keep fail-open; flipping a security-class guard (`block-credential-read`, `block-dangerous-git`) is an operator policy call. Trigger: a guard observed silently not running | [Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails) | 2026-10-10 |
| Prompt-injection screening of fetched content by a classifier | `docs/conventions/untrusted-content/README.md` "The framing contract" plus deterministic permissions; `plugins/discovery/hooks/webfetch-truncation.mjs` checks truncation only, which is its intended scope | REJECT. A classifier is one signal, not a control (the research behind this is in the IndyDevDan digest's [prompt-injection findings](https://github.com/melodic-software/knowledge-corpus/blob/main/sources/videos/10-levels-of-jev-for-agentic-engineers-_U-O5lYhJ7Q/analysis/research/findings/prompt-injection-classification.md)), and a per-fetch model call adds latency and false comfort | No Claude Code docs page covers classifier screening of fetched content as of 2026-10-10. Searched: the docs index (`https://code.claude.com/docs/llms.txt`, 257 `docs/en/` pages) for the titles and descriptions containing classif, injection, screen and untrusted, and the security page for classifier; every classifier hit is auto mode's action classifier. The general safeguards are at [Protect against prompt injection](https://code.claude.com/docs/en/security#protect-against-prompt-injection). Recheck trigger: a Claude Code docs page starting to cover classifier screening, at which point the pointer moves there | 2026-10-10 |
| Confidence-gated actions with numeric thresholds (level 4) | No gate here produces a numeric probability; confidence is categorical (`docs/conventions/detector-findings/README.md`) and escalation is rule-based (the decide-or-ask gate in `/planning:plan`) | REJECT a threshold convention: nothing consumes it. Our rule for the first gate that needs one: never auto-allow on a score, and calibrate any threshold on locally labeled data before trusting it | For how the vendor says to set Jev thresholds, read [Thresholds scale with risk](https://docs.typesafe.ai/confidence#thresholds-scale-with-risk) live; for how vendor-tuned thresholds held on our data, read our evaluation [#5809](https://github.com/melodic-software/claude-code-plugins/issues/5809). Recheck trigger: a gate in this repo starts producing a numeric score | 2026-10-10 |

## Lane R: routing, context and reads

| Topic | Ours | Verdict | Pointer | As of |
|---|---|---|---|---|
| Cheap routing gate in front of agent work (level 5) | Role routing in `plugins/multi-agent/reference/defaults.yaml`, resolved by `/multi-agent:route`; subagents with a `model:` field | COVERED. Native subagents and role routing do the job with no new vendor | [Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model) | 2026-10-10 |
| Haiku tier for per-item classification fan-out | `retrieval` role defaults to `sonnet` at `low` effort (`plugins/multi-agent/reference/defaults.yaml`); no role uses Haiku | TRACK. A shared default changes only on eval evidence, owned by `/multi-agent:audit-defaults`. Trigger: a pilot eval of Haiku against the current `retrieval` default on this repo's fan-out stages | [Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model) | 2026-10-10 |
| Per-turn "should I compact now" decision (level 7) | context-guard token-band zones (`plugins/context-guard/hooks/zone.ts`, `DEFAULT_BANDS`; "Blocking gate" in `plugins/context-guard/README.md`) and the phase-boundary call in `/session-flow:workflow` | TRACK. Build no model-judged compaction trigger until a trigger below fires; which hook types PreCompact runs is read live at the sections this row points at. Trigger: PreCompact gains `prompt` hook support, or a session shows compaction at the wrong moment that the zones and workflow routing did not prevent | [PreCompact](https://code.claude.com/docs/en/hooks#precompact) and [Prompt-based hooks](https://code.claude.com/docs/en/hooks#prompt-based-hooks) | 2026-10-10 |
| Cheap file reads and questions over files at scale (levels 8 and 9) | `/discovery:explore`, `/discovery:read-docs`, the built-in Explore agent, and subagent delegation (the context-economy chapter of `/playbooks:fable-5`) | COVERED, by the delegation the built-in subagents section this row points at describes; the #5809 round 2 file-scouting hint failed its bar | [Built-in subagents](https://code.claude.com/docs/en/sub-agents#built-in-subagents) | 2026-10-10 |

## Interview queue

Open owner decisions, each with its recommendation:

1. **Semantic shell gate.** Has a destructive command ever passed both the guardrails hooks and
   auto mode? Recommendation: build nothing until one is observed; if one is, design it as a
   `command` hook with `onFailure: "block"` that returns `ask` interactively and `deny` in an
   unattended lane.
2. **Haiku tier for `retrieval`.** Recommendation: defer; settle it with an eval through
   `/multi-agent:audit-defaults`, since the default is shared across plugins.
3. **Compaction timing.** Has compaction fired at the wrong moment despite context-guard zones and
   `/session-flow:workflow`? Recommendation: defer until a session shows it.
4. **Fail-closed guards.** Should any security-class guardrails hook flip to fail-closed?
   Recommendation: keep fail-open, and first fix the one guard found that can fail silently ([#6905](https://github.com/melodic-software/claude-code-plugins/issues/6905)) so a silent failure becomes visible.
