# E-session-behavior

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 11 `HUMAN` rows (5 plugin READMEs,
5 CHANGELOGs, plus `plugins/adhd/README.md`). The 5 CHANGELOGs are judged as a class in `README.md`.

This is the densest group for predicate `Am1`. Seven of the twelve broken parentheticals in the
whole corpus are here, six of them in `plugins/discipline/README.md` alone.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| E1 | `plugins/autonomy/README.md:183` | `Am1` | S1 |
| E2 | `plugins/autonomy/README.md:89` | `Am1` | S1 |
| E3 | `plugins/discipline/README.md:130` | `Am1` | S1 |
| E4 | `plugins/discipline/README.md:149` | `Am1` | S1 |
| E5 | `plugins/discipline/README.md:150` | `Am1` | S1 |
| E6 | `plugins/discipline/README.md:273` | `Am1` | S1 |
| E7 | `plugins/discipline/README.md:376` | `Am1` | S2 |
| E8 | `plugins/discipline/README.md:381` | `Am1` | S2 |
| E9 | `plugins/autonomy/README.md:155` | `M2` | S2 |
| E10 | `plugins/discipline/README.md:3` | `M1` | S2 |
| E11 | `plugins/session-flow/README.md:3` | `L1` | S2 |

### E1. The worst instance in the corpus

`plugins/autonomy/README.md:183`, verbatim across two lines:

```text
Setup writes tracked config to `.claude/autonomy/` in the consuming repo (concern-named. The
config outlives any plugin restructure). Personal overlays follow the marketplace overlay
```

`concern-named` is a two-word fragment. The sentence that follows it sits inside the parentheses and
the closing paren then lands after a completed sentence, so the reader cannot tell where the
parenthetical was meant to end without rereading. Predicate `Am1`.

The shape is what the resolved guide's substitution guardrail produces when "end the sentence" is
applied between parentheses, which is the one case that guardrail does not cover. This lane did not
check the site against git history, so the mechanism is the likely explanation rather than a
verified one. The defect is in the text as it stands either way.

Replacement:

```text
Setup writes tracked config to `.claude/autonomy/` in the consuming repo, named for the concern so
the config outlives any plugin restructure. Personal overlays follow the marketplace overlay
```

### E2

`plugins/autonomy/README.md:88` to `:89`, verbatim:

```text
Each capability below lands with its own work package; none ships before its contracts are
locked (no step-skipping. Trust before scale).
```

Same shape. `no step-skipping` is a fragment; `Trust before scale` is a slogan, not a sentence.

Replacement:

```text
Each capability below lands with its own work package. None ships before its contracts are locked:
no step-skipping, and trust before scale.
```

### E3

`plugins/discipline/README.md:130` to `:132`, verbatim:

```text
side re-anchors the consuming org's simpler-code convention (named failure
modes; constraints. Clarity, tests, error handling, conventions,
observability, never traded for line count); prose terseness usually has no
```

`named failure modes; constraints` is a fragment, and what follows the period is a list, not a
sentence. Predicate `Am1`.

Replacement:

```text
side re-anchors the consuming org's simpler-code convention, which names the failure modes and the
constraints that are never traded for line count: clarity, tests, error handling, conventions, and
observability. Prose terseness usually has no
```

### E4 and E5. Two in one sentence

`plugins/discipline/README.md:147` to `:152`, verbatim:

```text
**gap** (docs say X, we do Y, no recorded rationale, including deprecation
and version drift), a **deliberate divergence** (rationale recorded in
repo docs / an ADR. Re-checked only for whether it still holds, since
upstream may have obsoleted it), or an **undocumented divergence** (looks
intentional, no rationale, needs the human's call. Routed to the repo's
ADR/docs convention). Reports what was compared versus skipped; unverified
```

The first parenthetical is correct. The second and third both carry a fragment, a period, and a
further clause. Predicate `Am1` twice. The `repo docs / an ADR` slash is also `Am3`.

Replacement for the second and third parentheticals:

```text
**gap** (docs say X, we do Y, no recorded rationale, including deprecation
and version drift), a **deliberate divergence** (rationale recorded in the
repo docs or an ADR, re-checked only for whether it still holds, since
upstream may have obsoleted it), or an **undocumented divergence** (looks
intentional, has no rationale, and needs the human's call, so it routes to
the repo's ADR/docs convention). Reports what was compared versus skipped; unverified
```

### E6

`plugins/discipline/README.md:273`, verbatim:

```text
`reason-dont-recite` (evaluation-side. Is the inherited convention justified?)
```

`evaluation-side` is a fragment; the question that follows is a sentence. Predicate `Am1`.

Replacement:

```text
`reason-dont-recite`, the evaluation side, which asks whether the inherited convention is justified,
```

### E7

`plugins/discipline/README.md:376`, a table cell. Verbatim:

```text
| `research_deep_verification` | `do-your-research-deep` verification depth: `tiered` (default. Subagents only over load-bearing items) or `full` (subagent-verify every item); an invocation argument overrides it |
```

`(default. Subagents only over load-bearing items)` puts a period after a one-word fragment.
Predicate `Am1`.

Replacement for the cell:

```text
| `research_deep_verification` | `do-your-research-deep` verification depth. `tiered` is the default and fans subagents out only over load-bearing items; `full` subagent-verifies every item. An invocation argument overrides it |
```

### E8

`plugins/discipline/README.md:381`, verbatim:

```text
read-only (it never writes config. Reconfiguration stays the native flow).
```

Two clauses, the first a fragment relative to its parenthesis. Predicate `Am1`.

Replacement:

```text
read-only: it never writes config, so reconfiguration stays the native flow.
```

### E9. Release history in a reference document

`plugins/autonomy/README.md:155`, verbatim:

```text
A `--settings`-only `lane_stop_gate_enabled=true` (the pre-0.12.0 opt-in) is **no longer honored**.
That value reaches the hook only as the forgeable env mirror.
```

Predicate `M2`. The parenthetical names a form that no longer exists, and `no longer` frames the
sentence against a version the reader may never have run.

This one is close to the carve-out and is filed at S2 rather than S1 because a reader upgrading from
before 0.12.0 does need to be told their old config is inert. The remediation is not deletion:

```text
A `--settings`-only `lane_stop_gate_enabled=true` is **not honored**. That value reaches the hook
only as the forgeable env mirror, so the gate ignores it and says so once per session. Arm a lane
through the launcher instead.
```

The version detail moves to `plugins/autonomy/CHANGELOG.md`, which per
`scripts/check-changelog-parity.sh` already carries the 0.12.0 entry.

### E10. Mode: a plugin README carrying its own audit provenance

`plugins/discipline/README.md:3` to `:11`, verbatim tail of the opening paragraph:

```text
(Some correctors audit the conversation's own output; others audit state and decisions that
predate the session, a config already on disk, a tool already chosen, because existing state is not
evidence of its own correctness. Scope
recorded as a deliberate widening from the original "work in flight" framing,
a `/discipline:reason-dont-recite` finding on that boundary.)
```

Predicate `M1`. The final sentence is a record of how this plugin's own scope decision was reached.
That is explanation, and specifically process explanation, sitting in the first paragraph a person
reads when deciding whether to install the plugin. It answers a question no installing reader has.

Replacement: keep the widened scope, drop the provenance.

```text
(Some correctors audit the conversation's own output; others audit state and decisions that
predate the session, a config already on disk, a tool already chosen, because existing state is not
evidence of its own correctness.)
```

The dropped sentence belongs in `plugins/discipline/CHANGELOG.md` at the version that widened the
scope, if it is not already there.

**Overlap**: `L5-noise` may reach the same sentence through its plan-reference or historical-citation
shape. If it does, either lane's edit closes it. Wave 3 should apply it once.

### E11. The lead sentence of `session-flow`

`plugins/session-flow/README.md:3`, 86 words, 3 interrupters. Verbatim:

```text
A Claude Code plugin bundling fourteen skills for one cohesive capability: managing the lifecycle of
a working session, where you are in the work, how to pause and resume it, how to recover it after an
interruption, how to leave it durable before the machine goes away, how to retire finished work and
reconcile the task ledger, where things stand and why, whether its assumptions are still current,
```

Predicate `L1`. This is the first sentence of the document and it carries seven appositives before
the reader reaches a verb they can act on.

Replacement:

```text
A Claude Code plugin bundling fourteen skills for one cohesive capability: managing the lifecycle of
a working session. The skills answer where you are in the work, how to pause and resume it, how to
recover it after an interruption, how to leave it durable before the machine goes away, how to
retire finished work and reconcile the task ledger, and whether the session's assumptions are still
current.
```

`C1` note: the `fourteen skills` claim is correct against the tree, and
`scripts/check-skill-count-claims.sh` enforces it, so the number must survive the rewrite verbatim.

### The remaining 14 `L1` sentences in this group

Over the filter, same treatment, no individual rewrite supplied:

```text
plugins/autonomy/README.md:28
plugins/autonomy/README.md:39
plugins/autonomy/README.md:110
plugins/autonomy/README.md:133
plugins/autonomy/README.md:141
plugins/discipline/README.md:182
plugins/discipline/README.md:203
plugins/discipline/README.md:300
plugins/session-flow/README.md:60
plugins/session-flow/README.md:94
plugins/session-flow/README.md:114
plugins/session-flow/README.md:197
plugins/session-flow/README.md:226
plugins/session-flow/README.md:243
plugins/session-flow/README.md:342
```

## Document mode

`plugins/adhd/README.md` and `plugins/playbooks/README.md` are clean: one mode each, reference with
a short explanation lead, no mixing.

`plugins/discipline/README.md` and `plugins/session-flow/README.md` both run a `## What each skill
does` section of 193 and 161 prose lines respectively. That is the largest reference block in any
plugin README in the corpus. It is **not** a mode finding: the content is reference, the heading
promises reference, and a per-skill section is the structure the thing being documented supplies.
The size question belongs to `L2-progressive-disclosure`, which owns splits. Recorded here so the
wave 3 editor does not read the length as a mode defect.

`plugins/autonomy/README.md:86`, `## Roadmap (deferred, trigger-gated)`, is a genuine mode mix:
a roadmap is neither reference nor explanation about the product as it is. It is filed at S3 and no
edit is proposed, because the section is explicitly labelled deferred and a reader can see that from
the heading. Flagged for the orchestrator rather than acted on.

## Predicates with no findings in this group

`A1`, `A2`, `Am2`, `Am4`, `N1`, `C1`, `M3`.

On `M3`: all five plugin READMEs in this group that carry a generated options block have it under
`## Configuration`. This group is fully conformant on that predicate.

On `A2`: `plugins/adhd/README.md:71` contains `explain simply`. It is a quoted trigger phrase, which
the resolved guide's legitimate-hit class 1 exempts and which is load-bearing verbatim text.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group.
