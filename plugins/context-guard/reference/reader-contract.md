# Context guard: reader contract

## Contents

- [Operable floor (consumers inline these values verbatim)](#operable-floor-consumers-inline-these-values-verbatim)
- [Snapshot file shape](#snapshot-file-shape)
- [Capability detection (fail-open)](#capability-detection-fail-open)
- [Occupancy and combination rule](#occupancy-and-combination-rule)
- [Zone-crossing hooks (first shipped consumer)](#zone-crossing-hooks-first-shipped-consumer)
- [Evidence-degraded marker](#evidence-degraded-marker)
- [Zone is not a compaction indicator](#zone-is-not-a-compaction-indicator)
- [Zones (machine-scope tuning, optional)](#zones-machine-scope-tuning-optional)
- [Session-id discovery (how a consumer learns its own id)](#session-id-discovery-how-a-consumer-learns-its-own-id)
- [Idle sessions](#idle-sessions)
- [Cloud and headless sessions (`unknown` is structural)](#cloud-and-headless-sessions-unknown-is-structural)
- [Invariants and boundaries](#invariants-and-boundaries)
- [Consumers](#consumers)

The consumer-facing contract for the per-session context-window snapshots this plugin produces.
The writer is the plugin's module (`hooks/register.tsx`, a Claude Code mod), which writes through
`lib/write-snapshot.mjs`; the statusline tee `scripts/statusline-tee.sh` writes the same file where
it is still wired. `scripts/context-zone.sh` is the bundled resolver over the same data. Readers are sibling-plugin sessions (e.g. an audit skill deciding
whether to dispatch deep work to a fresh subagent). An installed plugin cannot read a sibling
plugin's files at runtime, so **consumers inline the operable floor below verbatim** and cite this
file for provenance only.

**Inline-floor ownership:** this file owns the operable floor: the snapshot path pattern, the
staleness value, and the default zone bands. Inlined copies in consumers must stay
**byte-identical** to the values printed here; a consumer lane carries a drift check that
grep-matches its inlined values against this file.

**Recheck trigger for every dated record in this file:** re-read the record's pointer, re-derive
the decision, and re-date the record when any of these change. The statusline stdin schema,
meaning the `context_window` field names, the `used_percentage` formula, and the top-level
`version` field. The auto-compact trigger,
meaning whether a default threshold is published as a number, and which models and environments
compact before the model's context limit. The four surfaces in the tunable table below
(`autoCompactWindow`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`,
`autoCompactEnabled`), including their units, ranges, and precedence. The skills substitution table
that documents `${CLAUDE_SESSION_ID}`. The published statements about how a 1M window behaves
across its length, which the band rationale cites when it declines a folklore number. The cloud and
headless finding, meaning whether a configured statusline runs in those environments and which
fields hook stdin carries. A release note touching the status line, compaction, settings, or skills
is the usual way one of the first four moves; a prompting-guide revision or a change to the hooks
page moves the last two. The empirical stamps, the transcript-history check and the cloud and
headless measurements, are re-run rather than re-read, on the same triggers. These stamps are probe
results with a date, not standing facts.

## Operable floor (consumers inline these values verbatim)

- **Snapshot path pattern (fixed):** `~/.claude/context-guard/context/<session_id>.json`
- **Zones file (fixed path, optional):** `~/.claude/context-guard/zones.json`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale. Treat
  the zone as **unknown** for that decision.
- **Default percentage bands (over `context_window.used_percentage`, uppers inclusive):**
  `smart` ≤ **50** < `acceptable` ≤ **75** < `dumb`. These shipped defaults apply only when
  `zones.json` is absent or malformed; when the file is present and valid, its bands win (see
  Zones below).
- **Default token bands (over occupancy = `total_input_tokens` + `total_output_tokens`, uppers
  inclusive, selected by window class as described under "Occupancy and combination rule"):**
  window class **200000**: `smart` ≤ **100000** < `acceptable` ≤ **160000** < `dumb`;
  window class **1000000**: `smart` ≤ **200000** < `acceptable` ≤ **400000** < `dumb`.
- **Token-shape version floor (fixed):** the token shape is computable only when the snapshot's
  `cli_version` is present, purely numeric dotted, and **≥ 2.1.132**, the release from which the
  token fields mean current occupancy rather than cumulative session totals.
- **Combination rule (verbatim, consumers inline this sentence):** when both shapes are
  computable, the worse zone wins (conservative-min); when only one is computable, it stands
  alone; when neither is, the zone is unknown.
- **Evidence-degraded marker (fixed path, optional):**
  `~/.claude/context-guard/context/<session_id>.compacted`. Presence means the session was
  compacted; treat it as evidence-degraded regardless of zone.
- **Zone vocabulary:** `smart` / `acceptable` / `dumb` / `unknown`. `unknown` is the conservative
  word; consumers treat it as "assume degraded".

## Snapshot file shape

One JSON object per session, rewritten atomically on every statusline refresh (temp file + rename,
so a reader never sees torn JSON). Files are **per-session**, not machine-scope last-writer-wins:
concurrent sessions each own the file named by their `session_id`.

```json
{
  "captured_at": "2026-07-24T05:32:48Z",
  "session_id": "abc123",
  "cli_version": "2.1.218",
  "context_window": {
    "total_input_tokens": 42000,
    "total_output_tokens": 3100,
    "context_window_size": 200000,
    "used_percentage": 21,
    "remaining_percentage": 79,
    "current_usage": {
      "input_tokens": 6000,
      "output_tokens": 3100,
      "cache_creation_input_tokens": 9000,
      "cache_read_input_tokens": 27000
    }
  }
}
```

- `captured_at`: ISO-8601 UTC write time; always present. Drives the staleness rule. A refresh
  whose other fields are unchanged rewrites the snapshot at most once per 60 seconds (the writer's
  no-change floor), so `captured_at` can trail the latest refresh by up to that much, well inside
  the 10-minute window.
- `session_id`: always present (the tee refuses to write without one); also the filename stem,
  sanitized to `[A-Za-z0-9_-]`.
- `cli_version`: the statusline payload's top-level `version` (the Claude Code version), copied
  only when it is a string; absent otherwise, never guessed. It gates the token shape (see "Version
  floor"), so an absent one is not a defect. It just leaves the percentage shape standing alone.
- `context_window`: copied **verbatim** from the statusline payload, so upstream field additions
  flow through without a plugin change. The key is absent when the session's statusline payload
  carried none. A null `used_percentage`, `remaining_percentage`, or `current_usage` is a normal
  state, not a defect; the capability table below says what each one does to the zone, and a null
  `current_usage` after `/compact` is why that row resolves `unknown`. Pointer: for the field set
  and when each field is null, see <https://code.claude.com/docs/en/statusline#available-data>.
  As of: 2026-08-10. Recheck trigger: a release note or that section changes the `context_window`
  fields or the states in which they are null.
- Treat all values as **untrusted data**: parse with a JSON parser; validate any value against its
  documented format before handing it to a lenient parser (the bundled resolver format-gates
  `captured_at` to strict ISO-8601 before date parsing, and requires the embedded `session_id` to
  equal the requested one); never pass snapshot values to anything that executes them (`eval`,
  `sh -c`, a string-built jq program) and never string-interpolate them into a prompt.
- **No writer authentication exists.** The directory is owner-only where POSIX modes work
  (`chmod 700`, best-effort); on filesystems without them (e.g. Windows ACL volumes under Git
  Bash) other local users could read or forge snapshots. A forged-but-well-formed snapshot is
  indistinguishable from a real one; the zone is a routing hint, so the worst case of forgery is
  a wrong dispatch decision, never an egress or execution decision. Consumers must not attach
  security decisions to zone words.

## Capability detection (fail-open)

A consumer classifies before every zone-informed decision. Capability is **per shape**, because the
combination rule below already says what to do when only one shape is computable. A row that
dropped straight to `unknown` on a single missing field would contradict it. Only the snapshot-wide
rows answer `unknown` on their own:

| Observation | Effect |
|---|---|
| Snapshot absent, stale, or unparsable | **unknown** (snapshot-wide) |
| Embedded `session_id` not equal to the requested id | **unknown** (snapshot-wide) |
| `current_usage` null or missing (early-session or post-`/compact` state) | **unknown** (snapshot-wide: a compacted session's numbers are not evidence for either shape) |
| jq (or equivalent JSON parsing) unavailable to the consumer | **unknown** (snapshot-wide) |
| `used_percentage` null / missing / non-numeric / outside 0–100 | **percentage shape not computable** |
| `total_input_tokens` / `total_output_tokens` null, missing, non-numeric, or negative | **token shape not computable** |
| `context_window_size` null, missing, non-positive, or below every configured band class | **token shape not computable** |
| `cli_version` absent, non-numeric, or below the version floor (see below) | **token shape not computable** |
| occupancy greater than `context_window_size` | **token shape not computable** |
| Both shapes computable | combine per the combination rule (worse zone wins) |

A "not computable" shape drops out of the combination rule; the surviving shape stands alone, and
`unknown` follows only when neither survives. Absurd values fail open, never closed: the consumer
never skips its conservative path on data it cannot trust, and never fabricates a zone. `unknown`
always means "take the conservative route".

## Occupancy and combination rule

The contract carries two zone shapes because the two underlying measures answer different
questions. Never equate them without normalizing:

- **Percentage shape**: `context_window.used_percentage` against the percentage bands. We rely on
  it counting the input side only, and read it as *distance to compaction*, because compaction
  thresholds key off the same accounting. Pointer: for how the percentage is computed, see
  <https://code.claude.com/docs/en/statusline#context-window-fields>. As of: 2026-07-26. Recheck
  trigger: that section changes the `used_percentage` formula.
- **Token shape**: **occupancy**, defined as `total_input_tokens + total_output_tokens`, against
  the window-class token bands. Occupancy counts both directions because both occupy the window,
  and we treat quality loss as tracking **absolute tokens in context, not window fraction**. It
  answers *distance to quality loss*. That is also why the token bands are absolute numbers
  selected by window class rather than percentages: 50% of a 1M window is a materially different
  cognitive state than 50% of a 200k window. Pointer: for the degradation evidence, see the Chroma
  context-rot report, <https://research.trychroma.com/context-rot>. As of: 2026-10-01. Recheck
  trigger: Chroma revises or withdraws the report, or a newer study finds degradation tracking
  window fraction.

**Window-class selection:** use the band row whose class key is the **largest one ≤
`context_window_size`**. A window smaller than every configured class has no row, so the token
shape is then not computable (never borrow a larger class's looser bands).

**Combination rule (consumers inline this sentence verbatim):** when both shapes are computable,
the worse zone wins (conservative-min); when only one is computable, it stands alone; when
neither is, the zone is unknown. Rationale: the two shapes disagree exactly when one measure has
information the other lacks (a deep-but-cache-heavy window, a small window near compaction), and
a routing hint must degrade toward caution, never toward optimism.

**Version floor:** `total_input_tokens` / `total_output_tokens` mean *current context occupancy*
only since Claude Code **2.1.132**. Before that they were cumulative session totals, which would
misfire the token bands badly. Cumulative semantics are **not observable from the numbers**: a
cumulative 170k in a 200k window is a perfectly plausible current occupancy, sits inside the
window, and resolves `dumb` while the live context may be smart-zone. So the token shape requires
an explicit version signal: the snapshot's `cli_version`, which the tee copies from the
statusline payload's top-level `version` field, the Claude Code version (Pointer:
<https://code.claude.com/docs/en/statusline#available-data>. As of: 2026-08-10. Recheck trigger:
that section renames or drops the `version` field). **The token shape is computable only when
`cli_version` is present, purely numeric dotted, and ≥ 2.1.132**; absent, malformed, or older
leaves the percentage shape to stand alone.

> **Source of the 2.1.132 floor.** We do not trust `total_input_tokens` /
> `total_output_tokens` as current occupancy below Claude Code 2.1.132, the release whose
> changelog entry names the statusline token-count fix.
>
> - **Pointer**: [Changelog 2.1.132](https://code.claude.com/docs/en/changelog#2-1-132); for the
>   fields' present meaning, <https://code.claude.com/docs/en/statusline#context-window-fields>.
> - **As of**: 2026-10-01
> - **Recheck trigger**: any change that relaxes the floor, or the changelog entry moves or is reworded.

**Plausibility guard (independent, retained):** **occupancy greater than `context_window_size`
also marks the token shape not-computable**. That is corrupt or forged data, and it catches what
a version field cannot (there is no writer authentication, so `cli_version` is untrusted like
every other snapshot value). The bundled resolver implements both gates.

**Band provenance:** all shipped band numbers are **declared judgment defaults with named
anchors**, not benchmark-derived constants. The 1M row's anchor is an informal range a named staff
member gave and hedged as task-dependent; the 200k row is declared judgment near practitioner
folklore values, but deliberately below them. Both rows carry equally low confidence;
`zones.json` is the correction path, and the numeric agreement of the 200k row's percentage
translation with the shipped 50/75 percentage defaults is coincidence, not validation.

## Zone-crossing hooks (first shipped consumer)

The plugin's module (`hooks/register.tsx`, a Claude Code mod; Claude Code 2.1.287 or later) is the
first shipped consumer. It decides from the live session's figures, the same ones it writes to the
snapshot, through a TypeScript copy of the resolver's band function; the shared fixture
`scripts/context-zone.fixtures.mjs` (generated from the repo's `lib/context-zone.fixtures.mjs`)
holds the two resolvers to the same word and notices. Where mods cannot load (see the setup
skill's module check), none of the following runs except the PostCompact marker.

- **Zone lines** (on each tool result of the main conversation and each prompt): on a transition
  into a zone worse than any this session has already reported, report the crossing on **two
  channels with two audiences**. The **model channel** (the `context` a `tool.call` or
  `prompt.submit` hook adds) carries the zone word and a counter-steer worded as facts with their
  source: the reading is a measurement rather than an instruction, degradation shows in the work
  itself and never in a zone word, and continuation is the operator's call. In `dumb` it also
  carries the save-state note, labelled as the dumb zone's default. A line carries no figure
  unless `zone_line_data` adds one (percent, tokens, window), and never a session id. Beside the
  crossings the module sends one approach line per boundary per cycle (`approach_margin`
  percentage points before it), one line per `thresholds` entry passed, the verdict restated once
  after a compaction (not a `precompute` one) and after an in-process resume, and, on a reload or a
  worker respawn (a load with earlier turns), the verdict only when it is past `smart`. After
  `/clear` it sends nothing: the new session starts in `smart`. Lines go to the main conversation
  only, never to a subagent. In `operator` report mode a turn a person typed holds the lines and
  offers them as the prompt box's suggestion plus a band notice when the turn ends; headless,
  loop, schedule and notification turns get the lines either way. The **operator channel** (a
  transcript line Claude does not read, and a band notice) carries the same crossing plus the
  continuation menu that is the human's call
  to make (continue / `/compact` / `/clear` / handoff-then-`/clear`, with a hand-written resume
  note as the standalone-install fallback). The menu does not say which option fits when: it says
  to route the next step with `/session-flow:workflow` (if installed). Without session-flow, we
  send the operator to the docs section on a filling context and restate none of it. Pointer: for
  what to do when the context fills up, see
  <https://code.claude.com/docs/en/context-window#when-your-context-fills-up>. As of: 2026-10-02.
  Recheck trigger: that section is renamed, moved or removed. **Neither the menu nor the router
   pointer ever reaches the model channel.** A menu injected into
  model context manufactures the model's own initiative to stop, summarize, or hand off. That is a
  live finding under the instruction-audit catalog's I23 (`harness-config`, `reference/criteria.md`),
  whose Remediate clause prescribes exactly this shape: state the counter-steer plainly, and where
  the harness must surface a budget, pair it with a reassurance rather than with an exit menu. The
  measurement decides only *when to ask*; the model still decides whether to stop. The model
  channel states that continuation is the operator's call, never that the operator has seen the
  menu. No documented hook behavior tells a hook whether an operator is present, so a delivery
  claim would be a fact the hook cannot know. Silent while the zone is unchanged, improving, or
  `unknown`. **Hysteresis**: the gate is the worst zone already *reported*, not the zone last
  *seen*. That marker decays only when the session returns to `smart`, the bottom of the ladder.
  Occupancy does not climb monotonically, so a session sitting on a band edge crosses it
  repeatedly; without the rule each re-crossing reads as a fresh transition and re-injects the
  guidance block. A `/clear` needs no rule: it starts a new session id, hence a fresh baseline.
  The rule is a declared judgment default, on the same footing as the bands above and with the
  same provenance status. **The property**: within one arming cycle each
  zone is announced at most once, and only a return to `smart` opens a new cycle. A genuine
  recovery followed by a relapse therefore re-injects exactly once for the band it relapses into,
  from any armed band. **The residual**: at the `smart`/`acceptable` edge a flap and a full recovery are the
  same observation, so a session oscillating there re-announces `acceptable` once per down-up cycle;
  the hook sees one word per observation, never the occupancy behind it, and separating those two
  cases needs a numeric deadband or a dwell the single-observation recovery could not survive.
- **Blocking gate** (in the module, when `zone_hook_mode` is `blocking` or `zones.json` sets a
  `block` action): denies new `Write|Edit|NotebookEdit|Agent|Workflow` calls in the blocked zone
  past a small grace budget. In a turn a person typed the block applies; in headless, loop,
  schedule and notification turns only a compacted session is blocked, unless
  `zone_block_unattended` is `same-as-typed`. Fail-open on `unknown`; handoff-path writes,
  read-only tools, Bash, and Skill invocations are never gated, so a durable handoff is always
  writable. Leaving the blocked zone, an `unknown` reading and a compaction each reset the budget.
- **PostCompact marker** (a settings hook, so it runs where mods are off): writes the
  evidence-degraded marker file (below).
- **Both zone consumers honor the marker**: when the marker exists, or the module saw the
  compaction itself, the lines and the blocking gate treat the session's effective zone as
  **dumb** regardless of the resolved word, including a green post-compaction reading and
  including `unknown`. That implements this contract's own "evidence-degraded regardless of zone"
  rule, so the marker is never write-only.
- **Status tool** `mcp__context-guard__status`: returns the session's latest figures (the last API
  response's), its zone, whether the evidence is degraded, the bands in force and the gate state,
  as JSON. A zone lookup for a session that has the module loaded; it has no switch.

Module state (last-seen zone, armed rank, gate counter) lives in the module's memory, per session
id; it is plugin-private and not part of this contract. The module adds no new snapshot
semantics. For the mods API it uses, see <https://code.claude.com/docs/en/plugins/mods/overview>.
As of: 2026-10-03, Claude Code 2.1.288. Recheck trigger: that page or its events reference changes
`tool.call`, `prompt.submit` or `session.compact`.

## Evidence-degraded marker

`~/.claude/context-guard/context/<session_id>.compacted`, written by the PostCompact hook,
last-write-wins per session:

```json
{ "compacted_at": "2026-07-26T12:00:00Z", "trigger": "auto", "hook_event_name": "PostCompact" }
```

`trigger` is `manual` | `auto` | `unknown`. **Presence alone is the signal**: a consumer that
finds the marker treats the session as evidence-degraded regardless of a green zone (see the next
section for why). Consumers should not gate on `compacted_at` freshness. Compaction's evidence
loss does not expire with time in the same session. The marker is part of this contract's
documented interface (fixed path, same character-class and trust rules as snapshots); it closes
the documented gap
that the snapshot alone cannot reveal compaction. Housekeeping: the writer hook prunes sibling
markers older than 14 days on each write, the same cutoff the tee applies to snapshots, far
above any live session's horizon, so a marker is never deleted out from under the session it
describes.

**Do not differentiate on `trigger`.** Evidence degradation is trigger-independent: the marker's
rationale is that the evidence is already gone from the model-visible context, which holds
identically for a steered `/compact` and an auto-compact. Consumers therefore treat all three
values the same, and that sameness is deliberate, not an omission. The writer
(`hooks/post-compact-mark.sh`) records the field and writes the marker unconditionally: a hook
cannot observe intent, and a marker written conditionally stops being evidence, so there is no
boundary-timed carve-out.

## Zone is not a compaction indicator

A compacted session's `used_percentage` **resets downward** while the evidence in its
conversational context is already gone. A consumer that knows its session was compacted (or
summarized by the harness) must treat the session as **evidence-degraded regardless of zone**,
including a green `smart` reading. The snapshot cannot tell you compaction happened; only the
session itself can know.

**No published default auto-compaction threshold grounds the bands.** With no window configured,
compaction fires at or near the model's context limit; the cases that fire earlier depend on the
model, the window it runs with, and the environment. For the current thresholds, see
[Claude Code model config, "Default auto-compact thresholds"](https://code.claude.com/docs/en/model-config#default-auto-compact-thresholds).
**As of:** 2026-09-30, the one number that section publishes, for native 1M windows, sits above
the shipped `dumb` band, so it does not disturb the margin that the bands-below-the-trigger rule
protects, the way a lowered window does. **Recheck trigger:** that section is renamed or removed,
or publishes a default at or below the `dumb` band's lower edge. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
implies a percentage default that no page publishes as a number; for that variable, see
[Claude Code environment variables](https://code.claude.com/docs/en/env-vars). The empirical
check (2026-07-24, execution session): no auto-compact event exists in the producing machine's
entire transcript history; the largest session ran to 308k total input tokens uncompacted on a
1M-class window. So the shipped bands keep the provenance stated under "Band provenance" above,
with a declared margin: if compaction triggers at 90% or above, the dumb band leads it by 15
points or more. The trigger is **model- and environment-dependent**, so no single band set is
correct everywhere; `zones.json` is the correction path if compaction is ever observed earlier.

Two adjacent decisions. We read the statusline percentage as of the last API response, not the
next request, so it can trail `/context`. With auto-compact turned off, the dumb band is the
*only* tripwire, so it matters strictly more, never less.

- **Pointer**: for how the statusline percentage relates to `/context`, see
  <https://code.claude.com/docs/en/statusline#troubleshooting>; for turning auto-compact off, see
  <https://code.claude.com/docs/en/settings-reference#autocompactenabled>.
- **As of**: 2026-09-28
- **Recheck trigger**: a release note or either section changes when the percentage is computed or
  what turning auto-compact off does.

### The trigger has no documented threshold, but it is operator-tunable

No *default* threshold is published as a number (above), yet the point at which auto-compact fires
is a configured value the operator can read and set. **Four** surfaces govern it. Each row states
what this plugin relies on; the pointer holds the units, ranges, forms, and precedence.

| Surface | Kind | What this plugin relies on | Pointer |
|---|---|---|---|
| `autoCompactWindow` | `settings.json` key | A token count that moves the trigger. Unset gives no number we can read, so we never assume one. Normalize it into the percentage shape before comparing (below). | [settings-reference: `autoCompactWindow`](https://code.claude.com/docs/en/settings-reference#autocompactwindow); [model-config: Set the auto-compact window](https://code.claude.com/docs/en/model-config#set-the-auto-compact-window) |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | environment variable | Read as the effective window whenever it is set, ahead of the setting, the command, and the flag. | [env-vars: Variables](https://code.claude.com/docs/en/env-vars#variables) |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | environment variable | Read as able only to move the trigger earlier, never later. | [env-vars: Variables](https://code.claude.com/docs/en/env-vars#variables) |
| `autoCompactEnabled` / `DISABLE_AUTO_COMPACT` | `settings.json` key / environment variable | Either one turning auto-compact off leaves the dumb band as the only tripwire. We treated `DISABLE_COMPACT` as unconfirmed by docs: it came from our 2026-08-17 probe of the shipped binary's strings (v2.1.233) and was absent from the env-vars page on 2026-08-19. | [settings-reference: `autoCompactEnabled`](https://code.claude.com/docs/en/settings-reference#autocompactenabled); [env-vars: Variables](https://code.claude.com/docs/en/env-vars#variables) |

We read a configured window above the model's context window as the model's window: it extends
nothing.

- **Pointer**: per row above.
- **As of**: 2026-08-19
- **Recheck trigger**: a release note or one of those sections changes a surface's units, range,
  precedence, or the set of surfaces itself.

**Normalize before comparing: the trigger is not in occupancy.** The two zone shapes answer
different questions and must never be equated (see "Occupancy and combination rule"), and the
trigger belongs to the **percentage** shape's accounting, not the token shape's: `used_percentage`
is input-token-based and answers *distance to compaction*, while the token bands measure
**occupancy** (`total_input_tokens + total_output_tokens`) and answer *distance to quality loss*.
A configured window is a fill threshold, so compare it against the percentage shape and let the
occupancy bands move independently.

One consequence matters enough to state on its own: we read `used_percentage` as a share of the
whole window the model offers, so after the auto-compact window is lowered, **we never read the
percentage as a forecast of when compaction will run**. A consumer reading only the percentage
will not see the trigger coming. Pointer: for the `CLAUDE_CODE_AUTO_COMPACT_WINDOW` row, see
<https://code.claude.com/docs/en/env-vars#variables>. As of: 2026-08-19. Recheck trigger: that row
changes what the percentage is measured against.

**Tune bands below the effective trigger, never above it.** Whatever the trigger resolves to on a
machine, the `dumb` band should be reached first. A zone reading exists so the session arrives at a
boundary decision while that decision is still being made deliberately, through the operator menu
above. If auto-compact fires first, the harness has already made a lossy choice
on the session's behalf and the boundary was reached too late. Auto-compact offers no steering
hook, so a firing is best read diagnostically: **it means the boundary was missed**, not that the
window was managed. Lowering the window moves the trigger, so the bands in `zones.json` must move
with it, normalized into the percentage shape. A 400000-token window on a 1M-class model puts the
trigger at **40% of the full window**, which is *inside* the shipped `smart` band (≤ 50), so
auto-compact would fire while every zone still reads green. Keeping bands below that trigger means
pulling the percentage bands under 40, not comparing 400000 against the same-looking `dumb`
occupancy number. Those two 400000s are different quantities.

That diagnostic reading is adopted; the prescription that usually travels with it is not. **Leave
auto-compact enabled.** Disabling it is a defensible operator choice on an attended machine, but it
is not this plugin's guidance: unattended cloud and autonomous sessions have no human at the
boundary, and for them a degraded continuation beats a hard stall at the window. The shipped ladder
is instrumentation, not prohibition: observable zones, then advisory injection, then an opt-in
blocking gate with a grace budget, with auto-compact remaining the last-resort safety net beneath
all of it (as-of 2026-08-17).

**On folklore numbers.** The auto-compact window figure in the vendored Boris playbook, §64, is a
widely-cited practitioner anchor. We record it as a **named anchor, never an adopted number**: its
calibration predates the 1M-window models these sessions run on, and we do not treat its
context-degradation premise as holding on them. A lowered window remains a legitimate cost and
compaction-timing choice on its own terms.

- **Pointer**: for the practitioner figure, see `/playbooks:boris` §64 ("Lower Your Auto-Compact
  Threshold"); for the current models' context windows, see
  [Latest models comparison](https://platform.claude.com/docs/en/about-claude/models/overview#latest-models-comparison).
- **As of**: 2026-10-01
- **Recheck trigger**: the session models' context window changes, or §64's figure changes.

## Prompt-cache miss cause

The statusline payload's `prompt_cache.last_miss_cause` names why the last cache miss happened.
`plugins/context-guard/scripts/prompt-cache-cause.py` reads that object from a statusline JSON
payload and prints the cause names. The tee snapshot still copies `context_window` and does not
copy `prompt_cache`; pass the live payload to the script. The script prints whatever cause names
`last_miss_cause.causes` carries, with no fixed list of its own, and prints `null` when the object
is null. Pointer: for the object and its cause names, see
<https://code.claude.com/docs/en/statusline#last-miss-cause>. As of: 2026-09-28. Recheck trigger:
that section renames the object or its cause names.

## Zones (machine-scope tuning, optional)

`~/.claude/context-guard/zones.json` is the single source of truth for band tuning on a machine.
The operator's own statusline display may read the same file, which eliminates band drift between
what the human sees and what consumers decide on. Zones say *where you are*; consumers decide
*what to do*.

```json
{
  "smart_max_used_percentage": 50,
  "acceptable_max_used_percentage": 75,
  "token_bands": {
    "200000": { "smart_max_tokens": 100000, "acceptable_max_tokens": 160000 },
    "1000000": { "smart_max_tokens": 200000, "acceptable_max_tokens": 400000 }
  }
}
```

Validity is **per shape, independently**:

- **Percentage keys:** both values numeric, `0 < smart_max < acceptable_max ≤ 100`. Malformed
  (unparsable file, non-numeric, inverted, out of range, or the keys simply absent from an
  otherwise-parsable file) → shipped percentage defaults with a visible stderr notice from the
  resolver.
- **`token_bands` (optional):** when present, an object whose every key is a decimal window-class
  string and every value carries numeric `smart_max_tokens` and `acceptable_max_tokens` with
  `0 < smart < acceptable ≤ class`. Malformed as a whole → shipped token bands with its own
  visible stderr notice. **Absent is zero-config** (shipped token bands, silently): a
  percentage-only file is valid.

Unrecognized keys are permitted and preserved (the setup skill's `apply` seeds/refreshes this
file idempotently; the resolver only reads it).

**The module's keys (optional).** The module reads three more keys; the resolver ignores them, and
an absent or invalid one means its default, so a file without them keeps working:

```json
{
  "approach_margin": 5,
  "actions": {
    "acceptable": { "action": "none" },
    "dumb": { "action": "save-state" }
  },
  "thresholds": [{ "at_percent": 60, "action": "handoff" }]
}
```

- `approach_margin`: percentage points before each boundary (each zone edge and each threshold)
  for the one approach line; a number from 0 (no approach lines) to below 100. Default 5. Where a
  token band edge sits below the percentage edge, that boundary's approach line comes the same
  points of the window early in tokens (50000 tokens at 5 on a 1000000-token window); with no
  known window size there is no token-shape approach line.
- `actions.<zone>`: `action` is `none`, `save-state`, `handoff` or `block`; optional `text`
  replaces the default wording. The action's sentence appears at that zone's crossing and
  restatement, never on an approach line, labelled "operator setting for the <zone> zone".
  Defaults: `none` everywhere except `save-state` at `dumb`. `block` arms the gate in that zone.
  An action set for `dumb` takes the place of `zone_hook_mode: blocking` there.
- `thresholds`: extra boundaries at a percentage that is not a zone edge (`at_percent`, 0 to
  100), each with an `action` and optional `text`; each fires once per cycle like a zone
  boundary and has its own approach line. A `block` threshold arms the gate once passed.

**Consumers read `zones.json` directly** (it is a shared data file): under plugin cache isolation a
consumer cannot invoke this plugin's `context-zone.sh`, so it re-implements the band lookup:
file present and valid → its bands; absent or malformed → the inlined default bands above. The
byte-identity rule covers the inlined defaults only.

Resolver invocation (for same-plugin or path-provisioned callers):

```bash
bash "<plugin-root>/scripts/context-zone.sh" <session_id>   # prints one zone word
```

## Session-id discovery (how a consumer learns its own id)

A skill learns its session id via the **`${CLAUDE_SESSION_ID}` substitution** in skill markdown
content. The skill body interpolates it into the snapshot path directly. Pointer:
<https://code.claude.com/docs/en/skills#available-string-substitutions>. As of: 2026-08-10.
Recheck trigger: that table renames or drops `${CLAUDE_SESSION_ID}`.

**Fallback:** when the substitution is unavailable (older Claude Code, non-skill context, or the
literal string `${CLAUDE_SESSION_ID}` survives unexpanded), the consumer must not guess a session
id. It takes the **unknown/conservative path** exactly as if the snapshot were absent.

## Idle sessions

The statusline only refreshes on activity: a live-but-idle session's snapshot goes stale by the
10-minute rule and resolves `unknown` until the next interaction refreshes it. That is correct
fail-open behavior, not a bug. An idle session asking for a zone gets a fresh snapshot within one
statusline refresh of waking. The writer's stale-file pruning cutoff (14 days) is deliberately far
above the staleness window, so idle sessions' files are never deleted out from under them.

## Cloud and headless sessions (`unknown` is structural)

The single capture channel is the statusline tee, so **a session that never runs a statusline has
no instrument at all**. No snapshot is ever written for it, and this contract resolves `unknown`
for that session permanently. Cloud and headless sessions are that case by default: no `statusLine`
is configured there, and configuring one does not help. Measured 2026-08-21 in both, a `statusLine`
written into the session's own user settings was never invoked.

This is not a degraded install and not a missing dependency. It is the absence of the only
documented surface that **delivers per-session context-window occupancy to a local writer**: as of
**2026-08-21**, our channel inventory found no hook event whose stdin reports the main session's
window; the one token-bearing hook payload describes a *subagent's* request. Two
other channels do carry live occupancy for the running session, the OpenTelemetry
`claude_code.api_request` log event and the session transcript, and neither can be turned into a
snapshot; `reference/cloud-headless-capture.md` records why in full. That file is the writer-side
channel inventory: every channel checked, its live URL, the date read, what it does and does not
carry, and what would have to change upstream. Re-check it when Claude Code's hooks, statusline,
settings or telemetry reference changes; the finding is dated, not permanent.

**What a consumer must do.** Nothing changes about the resolution rules. `unknown` still means
take the conservative route. What changes is how a consumer *reports* it:

- Report `unknown` in such a session as **"no instrument in this environment"**, never as a defect,
  a broken install, or a reason to ask the operator to fix something.
- **Never synthesize a zone from another source.** Each reachable near-substitute requires
  inventing or trusting something the channel does not supply: the OpenTelemetry
  `claude_code.api_request` event carries live per-session token counts but no window size and no
  local sink, so a zone from it needs a fabricated denominator; the session transcript reachable
  through the documented `transcript_path` hook field carries the right numbers behind an entry
  format we do not treat as a stable interface, where a field can keep its name and stop meaning
  full-context occupancy with nothing to detect it; and the OpenTelemetry token metric is
  a cumulative counter, not occupancy. A wrong zone is strictly worse than `unknown`: `unknown`
  routes to the conservative path, while a misread occupancy can read `smart` on a nearly full
  window.
- **`unknown` carries no direction.** It is not evidence of a full window and not evidence of an
  empty one. A consumer that wants a fork or handoff trigger in an environment with no instrument
  must drive it from something else, either an explicit operator request or an observation it
  makes itself, and must not present that trigger as instrument-backed.

**Telling structural absence from breakage.** Both print `unknown`, and the discriminator is on the
writer side: the statusline runs only where a `statusLine` command is configured *and* the
environment is one that runs it. Read `statusLine` from every scope that can carry it: user
`~/.claude/settings.json`, project `.claude/settings.json`, local `.claude/settings.local.json`,
and managed settings, where `statusLine` is also a valid key.

- **No `statusLine` in any scope** is structural, and offering statusline wiring as the remediation
  is wrong in an environment that runs no statusline.
- **A `statusLine` configured but the status line disabled** is also structural, and the
  remediation is policy or trust rather than wiring. Check `disableAllHooks`,
  `allowManagedHooksOnly`, and folder trust before anything else: either key, or an untrusted
  folder, can disable or narrow the status line with no warning, so this state looks exactly like
  a broken install unless it is checked first. The dated record for both settings keys is
  `cloud-headless-capture.md`, branch 3 of "Distinguishing structural absence from breakage".
- **A `statusLine` configured, not disabled, in an environment that does not run a statusline**
  (cloud, headless `claude -p`, other terminal-less) is also structural: the command exists, is
  not policy-disabled, and is still never invoked (the measurement above). Report as "no
  instrument in this environment", never as a defect.
- **A `statusLine` configured, not disabled, in an environment that runs a statusline, and no
  fresh snapshot** is a real defect (wiring, installed shim, or `jq`). Invoke
  `/context-guard:setup` via the Skill tool with `check` for the diagnosis.

## Invariants and boundaries

- **Per-session semantics.** One file per session id; no cross-session last-writer-wins collapse.
  Concurrent sessions never contend on the same target (atomic rename protects same-session
  refresh races).
- **Fixed paths, deliberately outside `${CLAUDE_PLUGIN_DATA}`.** The contract directory
  `~/.claude/context-guard/` is a documented cross-plugin artifact location: sibling-plugin
  sessions read it by the documented path. `${CLAUDE_PLUGIN_DATA}` resolves per-plugin-identity
  and would hide that directory from every consumer.
- **No shipped Monitor config.** Consumers that want write-triggered re-evaluation arm their own
  session Monitor on their snapshot path. The plugin ships no `experimental.monitors` entry.
  Monitors is an experimental Claude Code component, and this plugin takes no dependency on one
  until it stabilizes.
- **Fixed staleness constant.** The 10-minute value is a contract constant, deliberately not
  configurable: cross-plugin consumers inline the documented value, so a per-user override would
  silently split writer and readers. Band numbers are the one tunable, via `zones.json`, which
  display and consumers share.

## Consumers

- The plugin's own module (first shipped consumer, see "Zone-crossing hooks"), and through it the
  `mcp__context-guard__status` tool, which any session with the module loaded can call as its
  zone lookup.
- The `plugin-quality` audit skill (context-gate: zone-informed dispatch and evidence-flush
  decisions, conservative on `unknown`). It resolves the zone through a generated copy
  of this plugin's `scripts/context-zone.sh`. Its co-located `zones-inline-drift.test.sh` lane,
  which runs in the repo's plugin-gate CI job, checks that resolver copy and the evidence-degraded
  marker path in its skill body against the values this file prints. That the copy matches
  its canonical, `lib/context-zone.sh`, is a separate gate, `scripts/sync-shared-copies.sh --check`.
