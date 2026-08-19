# Context guard — reader contract

The consumer-facing contract for the per-session context-window snapshots this plugin produces.
The writer is the plugin's `scripts/statusline-tee.sh`; `scripts/context-zone.sh` is the bundled
resolver over the same data. Readers are sibling-plugin sessions (e.g. an audit skill deciding
whether to dispatch deep work to a fresh subagent). An installed plugin cannot read a sibling
plugin's files at runtime, so **consumers inline the operable floor below verbatim** and cite this
file for provenance only.

**Inline-floor ownership:** THIS file owns the operable floor — the snapshot path pattern, the
staleness value, and the default zone bands. Inlined copies in consumers must stay
**byte-identical** to the values printed here; a consumer lane carries a drift check that
grep-matches its inlined values against this file.

## Operable floor (consumers inline these values verbatim)

- **Snapshot path pattern (fixed):** `~/.claude/context-guard/context/<session_id>.json`
- **Zones file (fixed path, optional):** `~/.claude/context-guard/zones.json`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale — treat
  the zone as **unknown** for that decision.
- **Default percentage bands (over `context_window.used_percentage`, uppers inclusive):**
  `smart` ≤ **50** < `acceptable` ≤ **75** < `dumb`. These shipped defaults apply only when
  `zones.json` is absent or malformed; when the file is present and valid, its bands win (see
  Zones below).
- **Default token bands (over occupancy = `total_input_tokens` + `total_output_tokens`, uppers
  inclusive, selected by window class — see "Occupancy and combination rule"):**
  window class **200000**: `smart` ≤ **100000** < `acceptable` ≤ **160000** < `dumb`;
  window class **1000000**: `smart` ≤ **200000** < `acceptable` ≤ **400000** < `dumb`.
- **Token-shape version floor (fixed):** the token shape is computable only when the snapshot's
  `cli_version` is present, purely numeric dotted, and **≥ 2.1.132** — the release from which the
  token fields mean current occupancy rather than cumulative session totals.
- **Combination rule (verbatim — consumers inline this sentence):** when both shapes are
  computable, the worse zone wins (conservative-min); when only one is computable, it stands
  alone; when neither is, the zone is unknown.
- **Evidence-degraded marker (fixed path, optional):**
  `~/.claude/context-guard/context/<session_id>.compacted` — presence means the session was
  compacted; treat it as evidence-degraded regardless of zone.
- **Zone vocabulary:** `smart` / `acceptable` / `dumb` / `unknown` — `unknown` is the conservative
  word; consumers treat it as "assume degraded".

## Snapshot file shape

One JSON object per session, rewritten atomically on every statusline refresh (temp file + rename —
a reader never sees torn JSON). Files are **per-session**, NOT machine-scope last-writer-wins:
concurrent sessions each own the file named by their `session_id`.

```json
{
  "captured_at": "2026-07-24T05:32:48Z",
  "session_id": "abc123",
  "cli_version": "2.1.218",
  "context_window": {
    "total_input_tokens": 15500,
    "total_output_tokens": 1200,
    "context_window_size": 200000,
    "used_percentage": 8,
    "remaining_percentage": 92,
    "current_usage": {
      "input_tokens": 8500,
      "output_tokens": 1200,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 2000
    }
  }
}
```

- `captured_at` — ISO-8601 UTC write time; always present. Drives the staleness rule.
- `session_id` — always present (the tee refuses to write without one); also the filename stem,
  sanitized to `[A-Za-z0-9_-]`.
- `cli_version` — the statusline payload's top-level `version` (the Claude Code version), copied
  only when it is a string; absent otherwise, never guessed. It gates the token shape (see "Version
  floor"), so an absent one is not a defect — it just leaves the percentage shape standing alone.
- `context_window` — copied **verbatim** from the statusline stdin schema
  (<https://code.claude.com/docs/en/statusline>, verified 2026-08-10), so upstream field additions
  flow through without a plugin change. The key is absent when the session's statusline payload
  carried none. Null states are upstream-documented and normal: `used_percentage` /
  `remaining_percentage` may be `null` early in a session; `current_usage` is `null` before the
  first API call **and again immediately after `/compact`** until the next response repopulates it.
- Treat all values as **untrusted data**: parse with a JSON parser; validate any value against its
  documented format BEFORE handing it to a lenient parser (the bundled resolver format-gates
  `captured_at` to strict ISO-8601 before date parsing, and requires the embedded `session_id` to
  equal the requested one); never pass snapshot values to anything that executes them (`eval`,
  `sh -c`, a string-built jq program) and never string-interpolate them into a prompt.
- **No writer authentication exists.** The directory is owner-only where POSIX modes work
  (`chmod 700`, best-effort); on filesystems without them (e.g. Windows ACL volumes under Git
  Bash) other local users could read or forge snapshots. A forged-but-well-formed snapshot is
  indistinguishable from a real one; the zone is a ROUTING hint, so the worst case of forgery is
  a wrong dispatch decision, never an egress or execution decision — consumers must not attach
  security decisions to zone words.

## Capability detection (fail-open)

A consumer classifies before every zone-informed decision. Capability is **per shape**, because the
combination rule below already says what to do when only one shape is computable — a row that
dropped straight to `unknown` on a single missing field would contradict it. Only the snapshot-wide
rows answer `unknown` on their own:

| Observation | Effect |
|---|---|
| Snapshot absent, stale, or unparsable | **unknown** (snapshot-wide) |
| Embedded `session_id` not equal to the requested id | **unknown** (snapshot-wide) |
| `current_usage` null or missing (early-session or post-`/compact` state) | **unknown** (snapshot-wide — a compacted session's numbers are not evidence for either shape) |
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

The contract carries TWO zone shapes because the two underlying measures answer different
questions — never equate them without normalizing:

- **Percentage shape** — `context_window.used_percentage` against the percentage bands. Upstream
  computes it from **input tokens only** (`input_tokens + cache_creation_input_tokens +
  cache_read_input_tokens`, no output — statusline doc, verified 2026-07-26). It answers
  *distance to compaction*, because compaction thresholds key off the same accounting.
- **Token shape** — **occupancy**, defined as `total_input_tokens + total_output_tokens`, against
  the window-class token bands. Occupancy counts both directions because both occupy the window,
  and the degradation evidence (Chroma context-rot report) tracks **absolute tokens in context,
  not window fraction**. It answers *distance to quality loss*. That is also why the token bands
  are absolute numbers selected by window class rather than percentages: 50% of a 1M window is a
  materially different cognitive state than 50% of a 200k window. Cite a system card here only by
  name and section — an unnamed one was withdrawn from this clause as unresolvable (0.4.5).

**Window-class selection:** use the band row whose class key is the **largest one ≤
`context_window_size`**. A window smaller than every configured class has no row — the token
shape is then not computable (never borrow a larger class's looser bands).

**Combination rule (consumers inline this sentence verbatim):** when both shapes are computable,
the worse zone wins (conservative-min); when only one is computable, it stands alone; when
neither is, the zone is unknown. Rationale: the two shapes disagree exactly when one measure has
information the other lacks (a deep-but-cache-heavy window, a small window near compaction), and
a routing hint must degrade toward caution, never toward optimism.

**Version floor:** `total_input_tokens` / `total_output_tokens` mean *current context occupancy*
only since Claude Code **2.1.132** — before that they were cumulative session totals, which would
misfire the token bands badly. Cumulative semantics are **not observable from the numbers**: a
cumulative 170k in a 200k window is a perfectly plausible current occupancy, sits inside the
window, and resolves `dumb` while the live context may be smart-zone. So the token shape requires
an explicit version signal — the snapshot's `cli_version`, which the tee copies from the
statusline payload's top-level `version` field (Claude Code version — statusline doc, verified
2026-08-10). **The token shape is computable only when `cli_version` is present, purely numeric
dotted, and ≥ 2.1.132**; absent, malformed, or older leaves the percentage shape to stand alone.

> **Sourcing status of the 2.1.132 floor (re-checked 2026-08-10).** This doc previously quoted the
> statusline page as saying "Before v2.1.132 these were cumulative session totals". That sentence is
> **no longer on the page**: the current text states only the present-tense semantics this floor
> depends on — "Token counts currently in the context window, from the most recent API response"
> and "**Combined totals** (`total_input_tokens`, `total_output_tokens`): tokens currently in the
> context window". The historical note and the version number are gone with it. The floor is
> therefore a **retained claim with no current upstream source** — a conservative lower bound kept
> deliberately, not doc-backed. It stays because dropping it can only *widen* which payloads the
> token shape trusts, and the failure it guards is silent; re-source it before any change that
> relaxes it. The verbatim quote was re-checked against the complete raw page
> (`https://code.claude.com/docs/en/statusline.md`), not a summarized fetch, so this is a real
> removal rather than a truncated read.

**Plausibility guard (independent, retained):** **occupancy greater than `context_window_size`
also marks the token shape not-computable** — that is corrupt or forged data, and it catches what
a version field cannot (there is no writer authentication, so `cli_version` is untrusted like
every other snapshot value). The bundled resolver implements both gates.

**Percentage-key retirement trigger:** the percentage vocabulary is retained because it answers a
question the token shape cannot (distance to compaction) and because shipped consumers inline its
floor today. It retires when no shipped consumer inlines the percentage floor any longer —
recorded here so back-compat alone never makes the second vocabulary permanent.

**Band provenance:** all shipped band numbers are **declared judgment defaults with named
anchors** (issue #1475 carries the full provenance table), not benchmark-derived constants. The
1M row's anchor is a named-staff informal range (self-hedged "highly task-dependent"); the 200k
row is declared judgment near — but deliberately below — practitioner folklore values. Both rows
carry equally low confidence; `zones.json` is the correction path, and the numeric agreement of
the 200k row's percentage translation with the shipped 50/75 percentage defaults is coincidence,
not validation.

## Zone-crossing hooks (first shipped consumer)

Since 0.4.0 the plugin itself ships hooks over its own seam — the first shipped consumer:

- **Advisory injection** (`PostToolBatch` + `UserPromptSubmit`): on a transition into a zone worse
  than any this session has already reported, report the crossing on **two channels with two
  audiences** (the 0.5.0 audience split). The **model channel** (`additionalContext`) carries the
  determination and a counter-steer — the reading is a measurement rather than an instruction, real
  degradation shows up in the model's own output and never in a zone word, and the model is told to
  keep working the task in hand — plus, in `dumb`, a note to write each expensive conclusion to a
  durable note against a short compaction distance. The **operator channel** (`systemMessage`)
  carries the same crossing plus the continuation menu that is the human's call to make (continue /
  `/clear` / handoff-then-`/clear`, with a hand-written resume note as the standalone-install
  fallback / `/compact`) and the presence-gated pointer to `session-flow:workflow`'s router.
  **Neither the menu nor the router pointer ever reaches the model channel.** A menu injected into
  model context manufactures the model's own initiative to stop, summarize, or hand off — a live
  finding under the instruction-audit catalog's I23 (`claude-config`, `reference/criteria.md`),
  whose Remediate clause prescribes exactly this shape: state the counter-steer plainly, and where
  the harness must surface a budget, pair it with a reassurance rather than with an exit menu. The
  measurement decides only *when to ask*; the model still decides whether to stop. The model
  channel states that continuation is the operator's CALL, never that the operator has SEEN the
  menu — no documented hook behavior tells a hook whether an operator is present, so a delivery
  claim would be a fact the hook cannot know. Silent while the zone is unchanged, improving, or
  `unknown`. **Hysteresis** (since 0.7.0): the gate is
  the worst zone already *reported*, not the zone last *seen*. That marker decays only when the
  session returns to `smart` — the bottom of the ladder (**since 0.7.2**; 0.7.0 asked instead for an
  improvement of at least two ranks, which no band but `dumb` could ever satisfy, so a session that
  armed at `acceptable` could never re-arm, and 0.7.1 replaced that delta with a three-observation
  dwell for one version — see the CHANGELOG for why the dwell did not survive). Occupancy does not
  climb monotonically, so a session
  sitting on a band edge crosses it repeatedly; without the rule each re-crossing read as a fresh
  transition and re-injected the guidance block. A `/clear` needs no rule: it starts a new session
  id, hence a fresh baseline. The rule is a declared judgment default, on the same footing as the
  bands above and with the same provenance status. **The property**: within one arming cycle each
  zone is announced at most once, and only a return to `smart` opens a new cycle — so a genuine
  recovery followed by a relapse re-injects exactly once for the band it relapses into, from any
  armed band. **The residual**: at the `smart`/`acceptable` edge a flap and a full recovery are the
  same observation, so a session oscillating there re-announces `acceptable` once per down-up cycle;
  the hook sees one word per observation, never the occupancy behind it, and separating those two
  cases needs a numeric deadband or a dwell the single-observation recovery could not survive.
- **Blocking gate** (`PreToolUse`, only when the `zone_hook_mode` userConfig option is
  `blocking`): denies new `Write|Edit|NotebookEdit|Agent|Workflow` calls on a **fresh dumb-zone
  snapshot** past a small grace budget. Fail-open on `unknown`; handoff-path writes, read-only
  tools, Bash, and Skill invocations are never gated, so a durable handoff is always writable.
- **PostCompact marker**: writes the evidence-degraded marker file (below) and re-arms the
  blocking gate's grace budget (compaction opens a fresh window — a fresh budget, not a disarmed
  gate).
- **Both zone consumers honor the marker**: when the marker exists, the injection hook and the
  blocking gate treat the session's effective zone as **dumb** regardless of the resolved word —
  including a green post-compaction reading and including `unknown` — implementing this
  contract's own "evidence-degraded regardless of zone" rule so the marker is never write-only.

Hook state (last-seen zone, gate counters) lives under `${CLAUDE_PLUGIN_DATA}` — plugin-private,
NOT part of this contract. The hooks consume the seam through the same resolver consumers
re-implement; they add no new snapshot semantics.

## Evidence-degraded marker

`~/.claude/context-guard/context/<session_id>.compacted` — written by the PostCompact hook,
last-write-wins per session:

```json
{ "compacted_at": "2026-07-26T12:00:00Z", "trigger": "auto", "hook_event_name": "PostCompact" }
```

`trigger` is `manual` | `auto` | `unknown`. **Presence alone is the signal**: a consumer that
finds the marker treats the session as evidence-degraded regardless of a green zone (see the next
section for why). Consumers should not gate on `compacted_at` freshness — compaction's evidence
loss does not expire with time in the same session. The marker is part of this contract's seam
(fixed path, same character-class and trust rules as snapshots); it closes the documented gap
that the snapshot alone cannot reveal compaction. Housekeeping: the writer hook prunes sibling
markers older than 14 days on each write — the same cutoff the tee applies to snapshots, far
above any live session's horizon, so a marker is never deleted out from under the session it
describes.

**Do not differentiate on `trigger` — the field is recorded for a future decision, not a current
one.** Evidence degradation is trigger-independent: the marker's rationale is that the evidence is
already gone from the model-visible context, which holds identically for a steered `/compact` and
an auto-compact. Consumers therefore treat all three values the same, and that sameness is
deliberate, not an omission. The field is captured anyway (`hooks/post-compact-mark.sh`) so the
stance is falsifiable: it is the observable for a **track-on-event** condition recorded in
[`docs/upstream/aihero-course.md`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/upstream/aihero-course.md)
lane 3 — revisit consumer differentiation ONLY on real evidence that steered, boundary-timed
compactions preserve enough to grade work on, never on the intuition that a steered summary must
be better. A hook cannot observe intent, and a marker written conditionally stops being evidence,
so there is no boundary-timed carve-out in the writer either (as-of 2026-08-17).

## Zone is NOT a compaction indicator

A compacted session's `used_percentage` **resets downward** while the evidence in its
conversational context is already gone. A consumer that knows its session was compacted (or
summarized by the harness) must treat the session as **evidence-degraded regardless of zone** —
including a green `smart` reading. The snapshot cannot tell you compaction happened; only the
session itself can know.

**No official auto-compaction threshold exists to ground the bands on.** Verified 2026-07-23
(how-Claude-Code-works, context-window, settings `autoCompactEnabled`, costs pages) and re-verified
2026-08-10 (costs + statusline pages): the docs say only that compaction triggers "when approaching
context limits". The empirical check (2026-07-24, execution session): no auto-compact event exists
in the producing machine's entire transcript history — the largest session ran to 308k total input
tokens uncompacted on a 1M-class window — so the shipped bands are **declared judgment defaults**
with a declared margin (if compaction triggers at ≥ 90% as its phrasing implies, the dumb band
leads it by ≥ 15 points), not doc-derived constants. `zones.json` is the correction path if
compaction is ever observed earlier.

*Refinement, verified 2026-08-19 (model-config, "Default auto-compact thresholds"):* the docs are
now more specific than "when approaching context limits" — with no window configured, compaction
fires **at the model's context limit**, with enumerated exceptions that fire earlier (cloud
sessions compact as the conversation *approaches* the limit; Sonnet 4.6 / Opus 4.6 without extended
context, and Opus 4.8 / Opus 5 running on a 200K window, compact at the 200K boundary; a
`CLAUDE_CODE_DISABLE_1M_CONTEXT=1` session on a native-1M model likewise; an unrecognized model ID
compacts at whatever window Claude Code assumes for it). A *percentage* default is implied by
`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`'s "values above the default percentage are ignored" but is still
not published as a number — so the conclusion is unchanged: the bands remain declared judgment
defaults. What this does change is that the trigger is **model- and environment-dependent**, so no
single band set is correct everywhere.

Two adjacent caveats, same fetch: the doc warns the statusline percentage "may differ from
`/context` output due to when each is calculated" — the value is as-of the last API response, not
the next request; and with `autoCompactEnabled: false` no compaction ever fires (the session hard
-stops at the window instead), which makes the dumb band the *only* tripwire — strictly more
load-bearing, never less.

### The trigger has no documented threshold, but it IS operator-tunable

No *default* threshold is published as a number (above), yet the point at which auto-compact fires
is a configured value the operator can read and set. **Four** surfaces govern it. Verified
2026-08-17 against two independent pools — the official
[settings reference](https://code.claude.com/docs/en/settings) and the shipped binary's own schema
strings (v2.1.233) — and re-verified 2026-08-19 against the live settings,
[env-vars](https://code.claude.com/docs/en/env-vars), and
[model-config](https://code.claude.com/docs/en/model-config) pages:

| Surface | Kind | What it does |
|---|---|---|
| `autoCompactWindow` | `settings.json` key | How full the window gets before auto-compact fires, **in tokens, `100000` to `1000000`** (binary schema: `.int().min(1e5).max(1e6).optional()`). **No numeric default** — unset means a window tuned for the model, deliberately not published as a number. Written by the `/autocompact` command; the `--autocompact` flag sets it for one launch and, unlike the command, is not preempted by a higher-priority settings scope. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | environment variable | Same units and range; **highest precedence** — overrides the command, the flag, and the setting while set. **Accepts a plain integer only**: the command and flag take `500k` / `1M` / a bare `500` meaning thousands, but the variable reads `500k` as `500` and clamps to the 100K minimum. |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | environment variable | Sets the **percentage (1–100) of the auto-compact window** at which compaction triggers. **Can only lower the threshold** — values above the default percentage are ignored. Applies only in sessions that compact *before* the model's context limit, and to subagents as well as the main conversation. |
| `autoCompactEnabled` / `DISABLE_AUTO_COMPACT` | `settings.json` key (default `true`, shown in `/config` as **Auto-compact**) / environment variable | Turns auto-compact off entirely. (`DISABLE_COMPACT`, which disables *all* compaction including `/compact`, comes from the 2026-08-17 binary-strings pool; it is not listed on the env-vars page as of 2026-08-19 — treat it as unconfirmed by docs.) |

Claude Code caps the window at the model's actual context window, so a configured value above it
does not extend anything.

**Normalize before comparing — the trigger is not in occupancy.** The two zone shapes answer
different questions and must never be equated (see "Occupancy and combination rule"), and the
trigger belongs to the **percentage** shape's accounting, not the token shape's: `used_percentage`
is input-token-based and answers *distance to compaction*, while the token bands measure
**occupancy** (`total_input_tokens + total_output_tokens`) and answer *distance to quality loss*.
A configured window is a fill threshold, so compare it against the percentage shape and let the
occupancy bands move independently.

One consequence is load-bearing enough to state on its own, and it is the docs' own warning
(env-vars, verified 2026-08-19): **`used_percentage` always measures against the model's full
context window**, so once the auto-compact window is lowered, *the percentage no longer indicates
when compaction will run*. A consumer reading only the percentage will not see the trigger coming.

**Tune bands BELOW the effective trigger, never above it.** Whatever the trigger resolves to on a
machine, the `dumb` band should be reached first. A zone reading exists so the session arrives at a
boundary decision — finish the phase, `/clear`, write a handoff — while that decision is still
being made deliberately; if auto-compact fires first, the harness has already made a lossy choice
on the session's behalf and the boundary was reached too late. Auto-compact offers no steering
hook, so a firing is best read diagnostically: **it means the boundary was missed**, not that the
window was managed. Lowering the window moves the trigger, so the bands in `zones.json` must move
with it — normalized into the percentage shape. A 400000-token window on a 1M-class model puts the
trigger at **40% of the full window**, which is *inside* the shipped `smart` band (≤ 50): auto-
compact would fire while every zone still reads green. Keeping bands below that trigger means
pulling the percentage bands under 40, not comparing 400000 against the same-looking `dumb`
occupancy number — those two 400000s are different quantities.

That diagnostic reading is adopted; the prescription that usually travels with it is not. **Leave
auto-compact enabled.** Disabling it is a defensible operator choice on an attended machine, but it
is not this plugin's guidance: unattended cloud and autonomous sessions have no human at the
boundary, and for them a degraded continuation beats a hard stall at the window. The shipped ladder
is instrumentation, not prohibition — observable zones, then advisory injection, then an opt-in
blocking gate with a grace budget — with auto-compact remaining the last-resort safety net beneath
all of it (as-of 2026-08-17).

**On folklore numbers.** A widely-cited practitioner anchor — the vendored Boris playbook, §64,
attributing the compromise to Thariq — reports context rot setting in around 300–400k tokens on
1M-context models and suggests `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`. Recorded here as a **named
anchor, never an adopted number**, and it comes with its own amendment: that calibration is
Opus 4.7-era, and the Opus 5 prompting guide (verified 2026-08-08) states the 1M window's
instruction following, tool calling, and reasoning "stay consistent throughout the window", which
removes the degradation premise for that specific figure. A lowered window remains a legitimate
cost and compaction-timing choice on its own terms. The bands this contract ships stay declared
judgment defaults; `zones.json` is the tuning path.

## Zones (machine-scope tuning, optional)

`~/.claude/context-guard/zones.json` — the single source of truth for band tuning on a machine.
The operator's own statusline display MAY read the same file, which eliminates band drift between
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
  (unparsable file, non-numeric, inverted, out of range) → shipped percentage defaults with a
  visible stderr notice from the resolver (unchanged v1 behavior, including when the keys are
  simply absent from an otherwise-parsable file).
- **`token_bands` (optional):** when present, an object whose every key is a decimal window-class
  string and every value carries numeric `smart_max_tokens` and `acceptable_max_tokens` with
  `0 < smart < acceptable ≤ class`. Malformed as a whole → shipped token bands with its own
  visible stderr notice. **Absent is zero-config** (shipped token bands, silently) — a v1
  percentage-only file keeps working unchanged.

Unrecognized keys are permitted and preserved (the setup skill's `apply` seeds/refreshes this
file idempotently; the resolver only reads it).

**Consumers read `zones.json` directly** (it is a data seam): under plugin cache isolation a
consumer cannot invoke this plugin's `context-zone.sh`, so it re-implements the band lookup —
file present and valid → its bands; absent or malformed → the inlined default bands above. The
byte-identity rule covers the inlined defaults only.

Resolver invocation (for same-plugin or path-provisioned callers):

```bash
bash "<plugin-root>/scripts/context-zone.sh" <session_id>   # prints one zone word
```

## Session-id discovery (how a consumer learns its own id)

A skill learns its session id via the **`${CLAUDE_SESSION_ID}` substitution** in skill markdown
content (<https://code.claude.com/docs/en/skills>, substitution table, verified 2026-08-10). The
skill body interpolates it into the snapshot path directly.

**Fallback:** when the substitution is unavailable (older Claude Code, non-skill context, or the
literal string `${CLAUDE_SESSION_ID}` survives unexpanded), the consumer must NOT guess a session
id — it takes the **unknown/conservative path** exactly as if the snapshot were absent.

## Idle sessions

The statusline only refreshes on activity: a live-but-idle session's snapshot goes stale by the
10-minute rule and resolves `unknown` until the next interaction refreshes it. That is correct
fail-open behavior, not a bug — an idle session asking for a zone gets a fresh snapshot within one
statusline refresh of waking. The writer's stale-file pruning cutoff (14 days) is deliberately far
above the staleness window, so idle sessions' files are never deleted out from under them.

## Invariants and boundaries

- **Per-session semantics.** One file per session id; no cross-session last-writer-wins collapse.
  Concurrent sessions never contend on the same target (atomic rename protects same-session
  refresh races).
- **Fixed paths, deliberately outside `${CLAUDE_PLUGIN_DATA}`.** The contract directory
  `~/.claude/context-guard/` is a documented cross-plugin artifact seam: sibling-plugin sessions
  read it by the documented path. `${CLAUDE_PLUGIN_DATA}` resolves per-plugin-identity and would
  hide the seam from every consumer.
- **No shipped Monitor config.** Consumers that want write-triggered re-evaluation arm their own
  session Monitor on their snapshot path. The plugin ships no `experimental.monitors` entry —
  Monitors is an experimental Claude Code component, and this plugin takes no dependency on one
  until it stabilizes.
- **Fixed staleness constant.** The 10-minute value is a contract constant, deliberately not
  configurable: cross-plugin consumers inline the documented value, so a per-user override would
  silently split writer and readers. Band NUMBERS are the one tunable — via `zones.json`, which
  display and consumers share.

## Consumers

- The plugin's own zone-crossing hooks (first shipped consumer — see "Zone-crossing hooks").
- The `plugin-quality` audit skill (context-gate: zone-informed dispatch and evidence-flush
  decisions, conservative on `unknown`). Its inlined floor values are drift-checked against this
  file by its co-located `zones-inline-drift.test.sh` lane, which runs in the repo's plugin-gate
  CI job.
