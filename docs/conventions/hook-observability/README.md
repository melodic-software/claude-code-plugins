# Hook observability: status, failure, and telemetry surfaces for fleet hooks

Owner doc for the three observability surfaces every fleet hook declares or emits: a during-run
status label, a user-visible notice when a runtime prerequisite is missing, and the fleet's
telemetry envelope. The [plugin philosophy](../../plugin-philosophy.md) owns the posture rule:
advisory-versus-blocking, fail-open-versus-closed. This doc owns which of the three surfaces a
given situation uses and how each is shaped. A mod's lines to Claude and its telemetry follow the
same rules ([mod-authoring](../mod-authoring/README.md#boundary)); `statusMessage` and
`systemMessage` are settings-hook fields a mod does not have.

The rules below are this convention's decisions. Where one depends on hook behavior Claude Code
owns, it points at the section of the [hooks reference](https://code.claude.com/docs/en/hooks) to
read live, with the date it was checked and the event that sends someone back.

## The three surfaces

### 1. `statusMessage`: config, not runtime output

A static field on a `hooks.json` **handler object**, sibling of `type`/`command`/`timeout`/`if`:

```json
{
  "type": "command",
  "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/go-format.sh",
  "timeout": 15,
  "statusMessage": "Formatting Go imports..."
}
```

It labels the spinner while the hook runs. **A hook script never emits this: it is configuration,
not a runtime output field.** Pointer: for the field, see
<https://code.claude.com/docs/en/hooks#common-fields>. As of: 2026-10-01. Recheck trigger: that
table moves the field or a runtime output field takes the name. **Rollout status: near-complete.** As of
2026-07-23, 30 of the 31 wired `type: "command"` handlers across the fleet's 15 hook-bearing
plugins declare `statusMessage`; the sole remaining holdout is
`plugins/disk-hygiene/hooks/hooks.json`. Tracked against
melodic-software/claude-code-plugins#836 (this doc landed first per the convention-registry rule;
adoption was the follow-up wave, now all but one site complete. Close #836 once `disk-hygiene`
declares it or is recorded as a deliberate exception). Wording convention: a present-tense gerund
phrase naming what the hook is doing, specific to the tool or check
(`"Formatting Go imports..."`, `"Checking for secrets..."`, `"Recording tool-failure
telemetry..."`), not a generic `"Running hook..."`.

### 2. `systemMessage`: user-visible, scoped by who can act on the content

A JSON output field (`hookSpecificOutput` sibling) addressed to the user. We compose it on any exit
code, exit 2 included, and size it under the cap in
[Output caps](#output-caps-stated-by-the-reference). Pointer: for which exit codes still read JSON
output, see <https://code.claude.com/docs/en/hooks#exit-code-2>. As of: 2026-09-27. Recheck
trigger: that section changes whether JSON output is read on exit 2. Composed via
`hook::emit_channels` / `hook::emit_skip_notice`
(`lib/hook-utils.sh`) alongside `additionalContext` in one JSON document: a hook with both
agent-channel content and a pending notice composes them there and never prints two objects.
Pointer: for how stdout is parsed as JSON, see <https://code.claude.com/docs/en/hooks#exit-code-0>.
As of: 2026-10-01. Recheck trigger: that section changes how a multi-object stdout is read.

**Scope, required for exactly one situation:** a missing runtime prerequisite (binary, config
file, `jq`) causes the hook to silently no-op instead of performing its check. Doctrine
(`lib/hook-utils.sh`, its `Prerequisite visibility` section): *"a missing runtime prerequisite must surface to BOTH the agent
(additionalContext) and the user (systemMessage) — a silently skipped feature is a defect."* <!-- ai-slop-ignore: verbatim quotation of the `lib/hook-utils.sh` Prerequisite visibility doctrine -->

This is the doctrine that fleet hook scripts cite in comments as the **"dim-9 doctrine"**. The
label names *this* visible-skip rule and nothing more, and this section is its authoritative
definition. (The `dim-N` numbers are conformance dimension ids, for example dim-8 = the uniform
setup-skill wave and dim-11 = seam phrasing; [the conformance registry](../../conformance-dimensions.md)
defines the numbering.)

**Also required: a hook that CHANGED the user's file content without being asked.** An autofix hook
edits a file the user is working in, on the strength of an unrelated tool call, with no prompt and no
diff. The harness's own signal for it is a generic "PostToolUse hook modified `<file>` after your
edit (likely a formatter)" line that names no hook and shows no change, quoted from an observed
session, not from a docs page, and used here only as an illustration of the shape such a
notice takes. The rule rests on a negative: we found no file-change or diff surface among the hook
output channels, so a benign reflow and a wrong dictionary rewrite arrive identically.

- **Pointer**: for the hook output fields, see <https://code.claude.com/docs/en/hooks#json-output>.
- **As of**: 2026-08-10
- **Recheck trigger**: a Claude Code release that adds a file-change or diff surface to the hook
  output schema, whether a fourth output field or such a payload on one of
  [the three](#the-three-surfaces), which would make this rule's disclosure requirement redundant.

The person whose file was changed is the only one who can judge whether the change was correct, so
**the hook must name what it changed on the user channel**, not only the agent one: what
was rewritten, to what, where, and how to prevent it. This is a *narrow* addition to the scope above,
and its boundary is content the user did not request. A hook that only *reports* (a lint finding, a
suggested fix, a diagnostic) still belongs on `additionalContext` alone. The same cap discipline as
the repeat-notice rule applies: a per-item list must be bounded, with the remainder summarized as a
count, or the disclosure becomes the noise problem it was meant to prevent.

**Not required** for two situations that are already visible or already correctly agent-scoped:

- **Exit-2 blocking paths.** A block already delivers its reason, so repeating it on
  `systemMessage` is redundant, not more observable. Pointer: for where the blocking message goes,
  see <https://code.claude.com/docs/en/hooks#exit-code-2>. As of: 2026-10-04. Recheck trigger:
  that section changes what a `PreToolUse` block shows or which text becomes its reason. A
  blocking hook may still carry a `systemMessage` (see above), but only for content that meets the
  carve-out below, never for the reason itself.
- **Legitimate advisory findings *the model can act on*.** A hook that surfaces a finding to Claude
  for it to act on (e.g. a lint result, a suggested fix) belongs on `additionalContext` only. That
  is the correct channel for agent-actionable content, not a gap. This is the case the
  content-mutation clause above is deliberately distinguished from: reporting is agent-scoped,
  rewriting is not.

  **The predicate is what decides this, and it is *who can act*, not *how routine the content is*.** The
  harm this bullet names is misrouting **agent-actionable** content to the user channel. Content the
  model is *forbidden* to act on is not agent-actionable, so the bullet does not reach it, and
  routing such content to `additionalContext` anyway is the mirror-image defect, because an
  instruction the model cannot act on still shapes what it does.

  **Carve-out, admitted only on all three conditions together (one owner-approved exception is
  recorded under Conformance).** This is a conjunction, never a
  judgment call, because a soft "when it seems important" is exactly the drift the closing bullet
  guards:

  1. the payload states a **choice among actions whose only legitimate actor is the human**,
     because a rule the consuming project holds forbids the model to act on it (a session-lifecycle
     or harness-command choice is the usual shape), not merely because a human might also care;
  2. the model channel **separately carries the determination the model does need**, so nothing
     agent-actionable is lost by keeping the choice off it; and
  3. the emission is keyed to a **state transition**, not to every invocation.

  **Delivery may never be asserted.** The model channel may state that a choice belongs to the
  operator; it may **never** state that the operator has seen it. We found no documented way for a
  hook to learn whether an operator is present, so a delivery claim is a fact the hook cannot know
  in *any* mode, not only headless ones. Emitting to an unread operator channel is harmless;
  telling the model a human holds the choice when none does is not.

  **Synchronous hooks only.** The carve-out holds only where `systemMessage` stays off the model
  channel, and the reference decides that per hook kind and per event. We admit it from a
  synchronous hook on an event whose own section leaves the field on the user channel, and never
  from an `async` hook. Where the field would reach the model, drop the payload; never re-route it.

  - **Pointer**: for the field's delivery, see <https://code.claude.com/docs/en/hooks#json-output>
    and the event's section under <https://code.claude.com/docs/en/hooks#hook-events>; for
    background hooks, see <https://code.claude.com/docs/en/hooks#how-async-hooks-execute>.
  - **As of**: 2026-10-01
  - **Recheck trigger**: either section changes where `systemMessage` is delivered, or an event's
    section changes how it treats the field.

**Repeat-notice discipline.** A missing-prerequisite notice behind a broad matcher (every
`Write|Edit`, every `Bash` call) must not repeat on every invocation. Use `hook::require jq`
(wraps `hook::notice_once` + `hook::emit_skip_notice`) for a missing-`jq` gate, or pair
`hook::notice_once` with `hook::emit_skip_notice` directly for a non-`jq` prerequisite. A raw,
unguarded `hook::emit_skip_notice` call on a broad-matcher hook is a conformance defect. The user
notice fires once per session; the model notice fires once per agent, because a subagent does not
share the parent's context and would otherwise never see why the hook skipped. Neither renews. The
text says the notice will not repeat this session, never that the skip lasts the session: the hook
probes again on every call. A plugin README states the cadence as "once per session". A missing
external binary keeps the same cadence, with the install route in its user notice.

**Important exit-code caveat:** a bare `echo "..." >&2; exit 0` skip is **not a notice**; only
stdout JSON carries one. Pointer: for where exit-0 stderr goes, see
<https://code.claude.com/docs/en/hooks#exit-code-0>. As of: 2026-10-04. Recheck trigger: that
section starts showing exit-0 stderr in the transcript or to the model. `scripts/check-silent-skips.sh` **still treats a bare
stderr write as a sanctioned visibility signal as of this doc's introduction.** That is incorrect
for the exit-0 skip shapes the gate inspects, and the gate does not yet enforce the rule this doc
states. **Gate correction is pending**, scoped into the same fleet-adoption follow-up PR (against
issue #836) that converts the 9 fleet sites currently relying on that leniency
(`plugins/guardrails/hooks/*.sh`). The gate and its dependent sites land together so CI never
regresses between them. Once corrected, a quiet skip must use one of the sanctioned helper calls
or an explicit `# silent-skip-ok: <reason>` annotation.

**The annotation, precisely.** `# silent-skip-ok: <reason>` is a comment line placed directly
above the quiet exit it sanctions (the `exit 0` behind a `command -v` gate, or the
`|| exit 0` on a prerequisite test), with the reason stating why no notice channel exists or
why silence is the correct outcome. `scripts/check-silent-skips.sh` reads the annotation: a
gated skip it would otherwise reject passes when the line above it carries the marker, so the
reason is reviewed once, in the diff, rather than re-litigated on every gate run. Two shapes
use it today. A fire-and-forget process whose stdout and stderr the producer discards (the
harness-ops telemetry sink: "the producer side owns prerequisite visibility"), and a hook that
is off by design for the consumer who has not enabled it (the per-session event log's
`session_event_log_enabled: false` default, where a notice would fire on every event of every
session that never asked for logging). A hook that could speak and simply does not is not a
candidate; give it a helper call.

### Output caps stated by the reference

Three cap decisions, each with the section that owns the figure.

1. **This convention sizes every user- or agent-channel string under the output cap.** The cap
   is a ceiling, not a target: the Length rule in
   [Text a hook adds for the model](#text-a-hook-adds-for-the-model-frequency-and-phrasing) sets
   the size. A disclosure the content-mutation rule above requires must reach the reader inline
   and whole, so a hook that must stay inline caps itself under the figure with a truncation that
   keeps its counts and says it truncated, leaving headroom for JSON escaping. The adopting
   reference is `plugins/typos-format/hooks/typos-format.sh` (4,000 for `systemMessage`, 8,000 for
   `additionalContext`).
   - **Pointer**: for the output cap and what happens over it, see
     <https://code.claude.com/docs/en/hooks#json-output>.
   - **As of**: 2026-10-04
   - **Recheck trigger**: that section changes the cap figure or what happens over it.

2. **Each `additionalContext` value is sized on its own.** We size the value against the cap above
   and never against what other hooks on the same event emit.
   - **Pointer**: for how several hooks' values are delivered, see
     <https://code.claude.com/docs/en/hooks#add-context-for-claude>.
   - **As of**: 2026-09-05
   - **Recheck trigger**: that section states a budget shared across hooks.

3. **`classifierContext` is not a fourth surface, and its cap governs neither channel above.** It
   is a `PostToolUse` field addressed to the auto-mode classifier, never the user or the model, so
   it changes nothing about which channel a fleet hook writes a notice to. No fleet hook emits it
   today, and a `PreToolUse` guard cannot. Why this doc records it: a 2026-09-04 peer review read
   the classifier note's shared cap as the `additionalContext` cap and filed the typos-format
   8,000-character self-cap as a bug; the report was withdrawn on this reading of the page, and
   this is where the next reader should find the answer.
   - **Pointer**: for the field and its limits, see
     <https://code.claude.com/docs/en/hooks#annotate-a-result-for-the-auto-mode-classifier>.
   - **As of**: 2026-09-05
   - **Recheck trigger**: that section changes the field's cap, its sharing rule, or the events
     that accept it.

### 3. OTel-style telemetry envelope

Every wired producer hook emits one envelope per meaningful-outcome run via `hook::emit_telemetry`
(`lib/hook-utils.sh`) to the consumer-opted-in `HOOK_TELEMETRY_SINK`. Full schema and adoption
list: [`docs/conventions/hook-telemetry/`](../hook-telemetry/README.md). This doc does not
restate that shape, only the adoption requirement: **every hook wired in a plugin's `hooks.json`
emits it for each meaningful outcome it produces** (a check that ran and returned ok / blocked /
skipped-for-cause). A pure inapplicability short-circuit before any check logic runs (wrong tool
type, excluded path, missing prerequisite) does not need one; see the Conformance section below
for the precise rule and why. The guard mods emit on fewer outcomes, under a
[recorded exception](#recorded-exception-the-guard-mods-lines-and-telemetry-owner-approved-2026-10-03).

**Why a local file sink, not a real OTel exporter.** A hook process does not receive the session's
`OTEL_*` exporter configuration, so it cannot emit real OpenTelemetry. The file-sink envelope is
the only telemetry surface we give a hook; this is a constraint, not an oversight. Pointer: for
which subprocesses get no `OTEL_*` variables, see
<https://code.claude.com/docs/en/monitoring-usage#administrator-configuration>. As of: 2026-10-01.
Recheck trigger: that section starts passing `OTEL_*` variables to hook subprocesses.

**Deferred: `prompt_id` correlation.** Carrying the hook input's `prompt_id` in the envelope would
let external tooling correlate a hook's local envelope with the same turn's real OTel stream.
Adding it is a `hook-telemetry` schema change (`schema_version` 1.0 → 1.1) touching every
producer's `data_json` construction, out of scope for this doc's three-surface convention.
Pointer: for the field, see <https://code.claude.com/docs/en/hooks#common-input-fields>. As of:
2026-10-01. Recheck trigger: that table drops the field or its OpenTelemetry match.
melodic-software/claude-code-plugins#930 is closed: the per-session event log (`harness-ops`,
melodic-software/claude-code-plugins#3750) records `prompt_id` per event, and the envelope-spine
promotion is tracked at melodic-software/claude-code-plugins#3758.

## Text a hook adds for the model: frequency and phrasing

These rules cover every line a hook or mod sends either reader: the model channels
(`additionalContext`, a deny, block or Stop reason, a mod's context and results) and the user
channels (`systemMessage`, a mod's `$.ui.*` lines). We treat model-channel text that repeats often,
or context-channel text that reads as an order, as a prompt-injection risk, both for the hook's own
text and for a genuine user message that arrives beside it.

- **Frequency.** Speak only when the reader acts on the text: a finding, a state transition, or a
  missing prerequisite under the repeat-notice latch above. A check that ran clean sends nothing on
  either channel; its outcome goes to the telemetry envelope. A fleet hook sends no per-call status
  line, no reminder repeated on every call, and no countdown or budget line after tool results.
- **Phrasing.** Context channels (`additionalContext`, a mod's context) state facts with their
  source, never orders: name the hook, what it observed, and where
  (`typos-format: 2 misspellings in docs/a.md:12`), and state a remedy as a fact about the project
  (`markdownlint: README.md:40 is 131 characters; this repo wraps markdown at 100`). Decision
  channels (a deny, block or Stop reason) may direct the next step. Hook text claims no authority
  it lacks (system, administrator, user) and never presents itself as a message from the user.
- **Length.** Send only what the reader acts on, in the fewest tokens that keep the intent:
  - a verdict, not the raw figures behind it;
  - nothing the reader can look up on demand: a `PATH` dump, an absolute path where a relative one
    serves, an allowlist the owning skill documents, rationale, provenance asides, disclaimers;
  - no boilerplate repeated per finding;
  - one channel when only one reader acts on the text; the same text on both only when both
    readers act on it, as with a missing-prerequisite notice;
  - one helper owns a message pattern several hooks send; each hook calls it instead of a copy.

This section moves no hook to a different event. The guard mods' context and rate-limit lines are a
[recorded exception](#recorded-exception-the-guard-mods-lines-and-telemetry-owner-approved-2026-10-03)
to the Frequency rule, and `rate-limit-guard`'s threshold line to the Phrasing rule.

- **Pointer**: for each channel's reader and phrasing, see
  <https://code.claude.com/docs/en/hooks#add-context-for-claude>,
  <https://code.claude.com/docs/en/hooks#json-output>, and the decision control sections
  <https://code.claude.com/docs/en/hooks#pretooluse-decision-control>,
  <https://code.claude.com/docs/en/hooks#posttooluse-decision-control>,
  <https://code.claude.com/docs/en/hooks#userpromptsubmit-decision-control> and
  <https://code.claude.com/docs/en/hooks#stop-decision-control>; for a mod's channels, see
  <https://code.claude.com/docs/en/plugins/mods/reference#prompts-and-what-claude-reads> and
  <https://code.claude.com/docs/en/plugins/mods/api#show-something-without-starting-a-turn>; for
  the model behavior behind the risk, see
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#mid-turn-user-messages-and-task-budgets>.
- **As of**: 2026-10-04
- **Recheck trigger**: one of those sections changes who reads a channel, how injected context
  should be phrased, or how the model treats text that arrives beside tool results.

### See what a hook or mod sent

For a settings hook's full output, follow
<https://code.claude.com/docs/en/hooks-guide#debug-techniques> and
<https://code.claude.com/docs/en/hooks#debug-hooks>; for the hook telemetry event, see
<https://code.claude.com/docs/en/monitoring-usage#hook-execution-complete-event>.

A mod writes every line it sends Claude to the debug log with `$.ui.log(text, { to: 'debug' })`,
carrying the exact text sent, so the debug log holds what the model read.

- **Pointer**: for the debug log and the call, see the links above and
  <https://code.claude.com/docs/en/plugins/mods/troubleshoot#read-the-debug-log>.
- **As of**: 2026-10-04
- **Recheck trigger**: one of those sections moves, or the mods API gains its own record of what a
  mod sent Claude.

## What this convention is not

- **Not a diagnosis of host-level `PostToolUse` dispatch failure.** When every matching
  `PostToolUse` ends `hook_cancelled` and no formatter runs, the three surfaces above never
  emit. [`docs/formatter-path-probes.md`](../../formatter-path-probes.md) holds the status and
  the recheck for that case, filed as
  [#3549](https://github.com/melodic-software/claude-code-plugins/issues/3549). This convention
  does not grow a timeout or a substitute channel for a hook that never ran.
- **Not a new telemetry schema.** The envelope shape is `hook-telemetry`'s concern; this doc only
  states the adoption requirement.
- **Not a blanket "add systemMessage everywhere" rule.** Scoped narrowly to the
  missing-prerequisite-skip case, the unrequested-content-mutation case, and the three-condition
  human-only-choice carve-out above; over-applying it to blocking paths or to advisory findings the
  model can act on is itself a conformance defect (redundant user noise, or misrouting
  agent-actionable content to the user channel).
- **Not a UI feature, but "no verbose surface exists" is the wrong reason.** Verbose surfaces do
  exist, and the hooks reference names one that carries background-hook output. Pointer: for that
  surface, see <https://code.claude.com/docs/en/hooks#how-async-hooks-execute>. As of: 2026-08-11.
  Alongside it are the `verbose` and `viewMode` settings, the `--verbose` flag,
  `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` for hook matcher counts, and `--include-hook-events` for
  the stream-json event feed.

  The rule this doc needs does not depend on what those surfaces are, only on what an author may
  assume: **every one of them is off unless the consumer turned it on, and none of them changes
  where a hook must put its message.** `Ctrl+O` is a keystroke the user presses; `--verbose` and
  `--include-hook-events` are launch flags; `verbose` and `viewMode` are settings; the debug log
  level is an environment variable. A plugin authored today cannot know which, if any, is active in
  the session its hook runs in, and a hook whose output lands only in a channel the consumer may
  never have enabled is not observable. So the rule stands unchanged, with `statusMessage` and
  `systemMessage` as the surfaces a fleet hook writes to, resting on **a plugin cannot assume the
  consumer's view state**, not on any claim about which surfaces exist.

  Recheck trigger: a Claude Code release that surfaces hook output on a channel active by default,
  or that adds a hook-output field addressed to the user or the model to the JSON output schema
  beyond the three in [the three surfaces](#the-three-surfaces). Either would make the assumption
  above false and reopen this bullet. A field addressed elsewhere does not fire it; see the firing
  record below.

  > **Trigger firing, 2026-09-05.** The second clause, as previously worded ("adds a hook-output
  > field to the JSON output schema beyond the three"), fired on `classifierContext`, recorded
  > under [Output caps](#output-caps-stated-by-the-reference). Re-derived from the same fetch: the
  > field is addressed to the auto-mode classifier, is read on no consumer view state, and carries
  > nothing to the user or the model, so the assumption this bullet rests on stands and the rule is
  > unchanged. The clause is narrowed above to the fields that could falsify it.

  > **Correction, 2026-08-11.** This bullet previously read "No native 'verbose hooks' toggle
  > exists in Claude Code," verified against a `hooks`-page fetch. The literal phrase "verbose
  > hooks" appears on no page, but the word `verbose` appears across at least 13 Claude Code
  > pages including four hook-related mentions on `hooks` itself. Absence from one page is not
  > absence. The negative was scoped to the page searched and stated about the product. See
  > [upstream-drift, "Reading the basis"](../upstream-drift/README.md#reading-the-basis-the-fetch-route):
  > a claim of the form "X does not exist" has to name the surfaces searched.
  >
  > The counts above illustrate that error and support no rule: nothing in this doc's rules
  > depends on how many pages carry the word. They are deliberately floored ("at least 13") and
  > need no recheck, since a count that only ever grows cannot falsify the point it illustrates. The
  > one fact here that the rules *do* rest on is the background-hook surface the pointer above
  > names, and it argues **for** the rule rather than against it, so its recheck trigger is the one
  > on the paragraph above.

## Conformance

Fleet audits check, per wired producer hook:

- Every `command`-type handler in its `hooks.json` declares a `statusMessage`.
- Every missing-prerequisite skip path emits a `systemMessage` (via `hook::require jq` or
  `hook::notice_once` + `hook::emit_skip_notice`), gated on a broad matcher so the user notice
  fires once per session and the model notice once per agent, with no renewal.
- Any `systemMessage` that is neither a prerequisite-skip notice nor a content-mutation notice
  satisfies all three carve-out conditions, or is the one owner-approved exception named below,
  and its model-channel counterpart asserts no operator presence. Not mechanically gated, but reviewed per hook. No settings hook in the fleet meets all three
  today: `context-guard`'s operator menu, the site that did, now comes from its mod as a transcript
  line (`$.ui.log`) and a toast (`$.ui.toast`), with a notice row only on surfaces other than the
  terminal, none of which reaches Claude, so it is no `systemMessage`.
  One site is admitted by owner-approved
  exception (#4679): `guardrails`' `block-hook-bypass.sh` operator-lever notice. That notice lists
  switches only the operator may flip (condition 1); stderr separately carries the verdict and the
  agent's remedy, names an operator option only as the operator's to set, and never says the
  operator has seen anything (condition 2 and the delivery rule). It fires once per session,
  which limits repetition but is not a state transition,
  so it does not satisfy condition 3 and is admitted by the exception. Every other call site is
  a prerequisite skip or a content-mutation notice, so a second one is a signal to re-read the three
  conditions rather than to follow the precedent.
- Every path on which the hook rewrote file content names what it changed on the user channel,
  bounded by a per-run cap with the remainder reported as a count. Not mechanically gated, but
  reviewed per hook. The adopting reference is `plugins/typos-format/hooks/typos-format.sh`.
- The hook emits the telemetry envelope for every **meaningful outcome**: a check that ran and
  produced a result (ok / blocked / skipped-for-cause). A pure inapplicability short-circuit
  (wrong tool type, excluded path, empty content, outside the project) that fires before any
  check logic runs carries no diagnostic information and does not need one. This matches how
  every current telemetry-emitting hook in the fleet is already shaped.
- Text a hook or mod sends either reader follows the frequency, phrasing and length rules in
  [Text a hook adds for the model](#text-a-hook-adds-for-the-model-frequency-and-phrasing). Not
  mechanically gated, but reviewed per hook. One exception is recorded below.
- A mod writes every line it sends Claude to the debug log, per
  [See what a hook or mod sent](#see-what-a-hook-or-mod-sent). The guard mods conform once
  melodic-software/claude-code-plugins#6312 lands.

`scripts/check-silent-skips.sh` mechanically enforces the second point for the `command -v`-gated
shapes it recognizes, **once its pending gate correction lands** (see the systemMessage section
above). A bare stderr write does not actually satisfy the doctrine (see the exit-code caveat
above), even though the gate does not yet reject it. After that correction, a
quiet skip needs a sanctioned helper call or an explicit `# silent-skip-ok:` annotation.

### Recorded exception: the guard mods' lines and telemetry (owner-approved, 2026-10-03)

`context-guard`'s and `rate-limit-guard`'s mods add lines to tool results and prompts about the
session's context and rate-limit windows, which the Frequency rule's "no countdown or budget line
after tool results" would otherwise bar. They are admitted on this shape, and only on it (the owner
amended the What bullet twice on 2026-10-04: dropping the standing-rule sentence, then admitting
`rate-limit-guard`'s one directive):

- **When.** One line per boundary crossing, one per approach margin (a set number of points before
  a boundary), and one restatement after a compaction, a resume, a `/branch`, a reload of the mod
  mid-session, or a `/clear`, only when the verdict is past the quiet one. Nothing on a call where
  no boundary moved.
- **What.** Each line names its plugin and a verdict worded as a fact. The verdict names no action,
  claims no authority and gives no order. `context-guard`'s boundary lines add that continuing is
  the user's call, and may be followed by the dumb-zone save note or an operator-configured
  `zones.json` action. `rate-limit-guard`'s lines carry the verdict only, except that the line at
  the threshold ends with one directive, `Keep working.`, the only order this exception admits on a
  context channel. The owner decided this on 2026-10-04: they rotate accounts by hand on the alerts,
  and an interactive session waits out a usage limit on its own
  (<https://code.claude.com/docs/en/interactive-mode#wait-for-a-usage-limit-to-reset>), so a line
  read as a cue to stop would end work the session can finish. The observed stumble: on
  2026-10-04 the owner saw sessions treat the earlier fact-only line, `at the 90% pause edge`, as a
  reason to stop. By default a line carries
  no raw count; the operator can add figures through the plugin's line-data option. The reading
  behind the verdict stays on the plugin's status tools.
- **Telemetry.** The guard mods emit an envelope only on a fire that acts: lines sent, an operator
  suggestion shown, a tool call denied. A fire that reached a decision and changed nothing emits
  none, which narrows the meaningful-outcome bullet above for these two producers.

The shape rests on two Anthropic pages: which models are told their remaining context, and how
often harness text after tool results may arrive. The guards send at most one line per boundary
per cycle.

- **Pointer**: for context awareness, see
  <https://platform.claude.com/docs/en/build-with-claude/context-windows#context-awareness>; for the
  countdown and the occasional reminder, see
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#mid-turn-user-messages-and-task-budgets>.
- **As of**: 2026-10-03
- **Recheck trigger**: the context-awareness section changes which models receive the injected
  tags, or the prompting guide changes how often harness text after tool results may arrive before
  the model treats it as an injection.
