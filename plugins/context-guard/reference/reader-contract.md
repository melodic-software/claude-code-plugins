# Context guard: reader contract

## Contents

- [Operable floor (consumers inline these values verbatim)](#operable-floor-consumers-inline-these-values-verbatim)
- [Snapshot file shape](#snapshot-file-shape)
- [Capability detection (fail-open)](#capability-detection-fail-open)
- [Occupancy and combination rule](#occupancy-and-combination-rule)
- [The module (first shipped consumer)](#the-module-first-shipped-consumer)
- [Evidence-degraded marker](#evidence-degraded-marker)
- [Zone is not a compaction indicator](#zone-is-not-a-compaction-indicator)
- [Zones (machine-scope tuning, optional)](#zones-machine-scope-tuning-optional)
- [Session-id discovery (how a consumer learns its own id)](#session-id-discovery-how-a-consumer-learns-its-own-id)
- [Idle sessions](#idle-sessions)
- [Sessions with no writer (`unknown` is structural)](#sessions-with-no-writer-unknown-is-structural)
- [Invariants and boundaries](#invariants-and-boundaries)
- [Consumers](#consumers)

The consumer-facing contract for the per-session context-window snapshots this plugin produces.
The writer is the plugin's module (`hooks/register.tsx`, a Claude Code mod), which writes through
`lib/write-snapshot.mjs` in interactive, `-p` and `--bg` sessions alike.
`scripts/context-zone.sh` is the bundled resolver over the same data. Readers are sibling-plugin sessions (e.g. an audit skill deciding
whether to dispatch deep work to a fresh subagent). An installed plugin cannot read a sibling
plugin's files at runtime, so **consumers inline the operable floor below verbatim** and cite this
file for provenance only.

**Inline-floor ownership:** this file owns the operable floor: the snapshot path pattern, the
staleness value, and the default zone bands. Inlined copies in consumers must stay
**byte-identical** to the values printed here; a consumer lane carries a drift check that
grep-matches its inlined values against this file.

**Recheck trigger for every dated record in this file:** re-read the record's pointer, re-derive
the decision, and re-date the record when any of these change. The status line's documented
`context_window` fields, whose names and meanings the snapshot keeps, including the
`used_percentage` formula, and the session usage and version the mods API reports, which the
module maps onto them. The auto-compact trigger,
meaning how the published default thresholds relate to the bands, and which models and environments
compact before the model's context limit. The surfaces in the tunable table below
(`autoCompactWindow` at top level, per model, and per subagent, `/autocompact`, `--autocompact`,
`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `autoCompactEnabled`),
including their units, ranges, and precedence. The skills substitution table
that documents `${CLAUDE_SESSION_ID}`. The published statements about how a 1M window behaves
across its length, which the band rationale cites when it declines a folklore number. Where mods
run, which decides where a snapshot can be written at all. A release note touching the status
line, mods, compaction, settings, or skills is the usual way one of the first four moves; a
prompting-guide revision or a change to the mods overview moves the last two. The empirical stamps,
the transcript-history check and the capture measurements, are re-run rather than re-read, on the
same triggers. These stamps are probe results with a date, not standing facts.

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
  window class **200000**: `smart` ≤ **100000** < `acceptable` ≤ **150000** < `dumb`;
  window class **1000000**: `smart` ≤ **128000** < `acceptable` ≤ **500000** < `dumb`.
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

One JSON object per session, rewritten atomically by the module (temp file + rename, so a reader
never sees torn JSON). Files are **per-session**, not machine-scope last-writer-wins: concurrent
sessions each own the file named by their `session_id`.

The module writes after every tool call, at each measurement after a response, from a 15-second
timer that runs only while a turn runs, and when the session ends. Each write runs
`node lib/write-snapshot.mjs`, so where `node` is missing or the module cannot start a process,
nothing is written and readers read `unknown`, as with no file.

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

- `captured_at`: ISO-8601 UTC write time; always present. Drives the staleness rule. A write
  whose other fields are unchanged since the last one happens at most once per 60 seconds (the
  writer's no-change floor), and the timer ticks every 15 seconds, so during a turn `captured_at`
  trails the latest reading by up to 75 seconds, well inside the 10-minute window.
- `session_id`: always present; also the filename stem. The module writes only for an id of
  `[A-Za-z0-9_-]`, and an id outside that class gets no file.
- `cli_version`: the Claude Code version the session reports, present only when it is a
  non-empty string; absent otherwise, never guessed. It gates the token shape (see "Version
  floor"), so an absent one is not a defect. It just leaves the percentage shape standing alone.
- `context_window`: always present, built from the session's live usage in the status line's field
  names and meanings: `total_input_tokens` and `total_output_tokens` (absent before the session's
  first response), `context_window_size`, `used_percentage`, `remaining_percentage` and
  `current_usage`. A field the status line adds later does not appear here until the module maps
  it. A null `used_percentage`, `remaining_percentage`, or `current_usage` is a normal
  state, not a defect; the capability table below says what each one does to the zone, and a null
  `current_usage` after `/compact` is why that row resolves `unknown`. A body with null figures
  never replaces a file that has them. Pointer: for the field meanings and when each field is
  null, see <https://code.claude.com/docs/en/statusline#available-data>.
  As of: 2026-10-03. Recheck trigger: a release note or that section changes the `context_window`
  fields or the states in which they are null.
- **File modes and siblings.** The snapshot file is owner-only (`0600`) and the directory `0700`
  where POSIX modes work. For each write the writer creates a lock file,
  `.<session_id>.json.lock`, and removes it when the write ends; one is left behind only when that
  removal fails, and the next write steals it once it is 60 seconds old. It writes through a temp
  file, `.<session_id>.json.tmp.w<pid>-<hex>`, removed after the rename. A `.<session_id>.json.last` file is one that versions before 0.11.0
  left behind; the writer's hourly prune deletes it, and every lock file, after 14 days. Readers
  read only `<session_id>.json` and `<session_id>.compacted` and ignore every file whose name
  starts with a dot.
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
  cognitive state than 50% of a 200k window. This is a declared judgment: no published study
  compares absolute tokens with window fraction, and Anthropic publishes no context-quality
  threshold. As of: 2026-10-04. Recheck trigger: Anthropic publishes a context-quality threshold,
  or a study compares the two.

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
an explicit version signal: the snapshot's `cli_version`, the Claude Code version the session
reports to the module (Pointer: `$.session.version()` in
<https://code.claude.com/docs/en/plugins/mods/reference#mods-api-methods>. As of: 2026-10-03,
Claude Code 2.1.288. Recheck trigger: that table renames or drops the method). **The token shape is computable only when
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

**Band provenance:** the shipped token bands are **declared judgment**, not benchmark-derived
constants. Anthropic publishes no per-length long-context scores for Claude Opus 5.5, Sonnet 5.5
or Fable 5.1: their system cards report one aggregate ProgramBench score each, an agentic task
whose episodes run up to the full 1M window. The published per-length data is retrieval and graph
traversal, not agentic work, and no study we found links those scores to agentic task quality. On
GraphWalks BFS, run by Google at max reasoning and published with Gemini 4 Argon, Opus 5.5 scores
90.6% up to 128K and 66.8% from 256K to 1M, and Fable 5.1 91.4% and 65.0%. On Context Arena's
8-needle MRCR (max effort), Claude Opus 5 scores 0.913 at 128K, 0.656 at 256K and 0.425 at 512K,
and Claude Sonnet 5 0.529, 0.522 and 0.320. The 1M row's `smart` edge, 128000, is the last length
at which those current-model scores are still near their best. Its `acceptable` edge, 500000,
sits below 512K, the first MRCR length at which both Claude rows score under one half. Between
the two, scores sag without a measured cliff, so a reading there is `acceptable`, not `dumb`: an
`acceptable` edge of 250000 read `dumb` at 26% of a 1M window on no evidence for current models
or agentic work (#6644). The 200k row's `acceptable` edge, 150000, sits at
the top of the practitioner consensus of about 125-150K. `zones.json` is the correction path, and
the numeric agreement of the 200k row's percentage translation with the shipped 50/75 percentage
defaults is coincidence, not validation.

- **Pointer**: when re-deriving a 1M band edge, fetch live:
  [Context Arena, 8 needles](https://contextarena.ai/api/needle-summary?needles=8), the Claude
  Opus 5 and Claude Sonnet 5 rows; [Gemini models](https://deepmind.google/models/gemini), the
  Gemini 4 Argon table's Opus 5.5 and Fable 5.1 GraphWalks BFS rows; the absence of per-length data, the
  [Opus 5.5 system card](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf)
  section 8.10 and the [Fable 5.1 system card](https://www-cdn.anthropic.com/0339e6a7c5c7b87f5c07798616dc32c215d14235/Claude%20Fable%205.1%20&%20Claude%20Mythos%205.1%20System%20Card.pdf)
  section 8.11. For the 200k row, correlate with [AI Hero, "Smart Zone"](https://www.aihero.dev/ai-coding-dictionary/smart-zone)
  and [Geoffrey Huntley, "Ralph"](https://ghuntley.com/ralph/); no docs page covers where quality
  degrades on a 200K window as of 2026-10-04.
- **As of**: 2026-10-09
- **Recheck trigger**: Opus 5.5, Fable 5.1 or Sonnet 5.5 appear on Context Arena; Google's table
  splits the 256K-1M GraphWalks bin; a new or revised
  Anthropic system card publishes per-length scores; or a docs page starts covering where quality degrades on a 200K window, at which point the
  200k row's pointer moves there.

## The module (first shipped consumer)

The plugin's module (`hooks/register.tsx`, a Claude Code mod; Claude Code 2.1.287 or later) is the
first shipped consumer. It decides from the live session's figures, the same ones it writes to the
snapshot, through a TypeScript copy of the resolver's band function; the shared fixture
`scripts/context-zone.fixtures.mjs` (generated from the repo's `lib/context-zone.fixtures.mjs`)
holds the two resolvers to the same word and notices. Where mods cannot load (see the setup
skill's module check), none of the following runs except the PostCompact marker.

- **Zone lines** (on each tool result of the main conversation and each prompt): on a transition
  into a zone worse than any this session has already reported, report the crossing on **two
  channels with two audiences**. The **model channel** (the `context` a `tool.call` or
  `prompt.submit` hook adds) carries facts only, never an instruction: by default the zone word and its rank of three. A
  line carries no figure unless `zone_line_data` adds one (percent, tokens, window); it never
  carries a session id. Beside the
  crossings the module sends one approach line per boundary per cycle (`approach_margin`
  percentage points before it), one line per `thresholds` entry passed, and the verdict restated
  once, only when it is past `smart`, after a compaction (not a `precompute` one), after an
  in-process resume, and on a reload or a worker respawn (a load with earlier turns). Each line
  sent, and each gate denial, is also written as sent to the debug log. Lines due
  at one carrier: a crossing or restatement recorded before a pending restatement merges into it;
  a crossing recorded after it is the newer verdict and replaces it. After
  `/clear` it sends nothing: the new session starts in `smart`. Lines go to the main conversation
  only, never to a subagent. In `operator` report mode a turn a person typed holds the lines and
  offers them as the prompt box's suggestion plus a notice row when the turn ends; headless,
  loop, schedule and notification turns get the lines either way. The **operator channel** (a
  transcript line Claude does not read and a toast, plus a notice row on every surface but the
  terminal, where a toast may not show) carries the same crossing plus the continuation menu that
  is the human's call to make (continue / `/compact` / `/clear` / `/session-flow:handoff` then
  `/clear`), at the reading that saw the crossing rather than at the carrier that takes Claude's
  line (a measurement, a tool call, a prompt, or a `/context-guard` or status-tool read), and not
  for a first reading already past `smart`, which has no earlier zone to name. A crossing already
  shown in an unattended turn is not offered again as a typed turn's suggestion. The
  transcript line ends `more: /context-guard`. `/context-guard` replies with the verdict, its
  figures and the settings in force only, because a command's reply is stored as a transcript row
  Claude reads; it writes the router pointer and the docs link as a separate transcript line
  Claude does not read. The menu does not say which option fits when, so that line says to route
  the next step with `/session-flow:workflow` (if installed). Without session-flow, we send the
  operator to the docs section on a filling context and restate none of it. Pointer: for the
  command reply reaching the model and `$.ui.log` not, see the `CommandRunResult`, `CommandOutput`
  and `ui.log` doc comments in the build's `claude-code/index.d.ts` types. As of: 2026-10-04.
  Recheck trigger: either doc comment changes what the model reads. Pointer: for what to do when the context fills up, see
  <https://code.claude.com/docs/en/context-window#when-your-context-fills-up>. As of: 2026-10-04.
  Recheck trigger: that section is renamed, moved or removed. **Neither the menu nor the router
  pointer ever reaches the model channel.** A menu injected into
  model context manufactures the model's own initiative to stop, summarize, or hand off. That is a
  live finding under I23 of `/harness-config:audit-instructions`. By default the module sends the
  verdict and any operator-configured `zones.json` action, and nothing that tells the model what
  to do: no save-state or handoff advice, no reassurance, no counter-steer rule about what a zone
  means. The model decides what to do with the facts; `/session-flow:workflow` and the user's own
  instructions own handoff and compaction guidance. The model
  channel never says the user has seen the menu. No documented hook behavior tells a hook whether an operator is present, so a delivery
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
  response's), its zone, whether the evidence is degraded, the bands in force (the token edges of
  the session's window class as `smart_max_tokens` and `acceptable_max_tokens`, `null` when the
  token shape is not computable) and the gate state, as JSON. A zone lookup for a session that has the module loaded; it has no switch.

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
markers older than 14 days on each write, the same cutoff the snapshot writer applies, far
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

**The defaults are published by the docs, and we state none of them here.** The default threshold
depends on the model, the window it runs with, and the environment, so the docs table is where it is
published and we keep no figure of our own; it is a documentation pointer, not something read at run time. For the current thresholds, see
[Claude Code model config, "Default auto-compact thresholds"](https://code.claude.com/docs/en/model-config#default-auto-compact-thresholds).
**As of:** 2026-10-10, our rule is that the shipped `dumb` band must sit below the default trigger
the table gives for the model in use, which the bands-below-the-trigger rule below protects.
**Recheck trigger:** that section is renamed or removed, or publishes a default at or below the
`dumb` band's lower edge. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
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

### The trigger is operator-tunable

The docs publish the default thresholds (pointer above), and the point at which auto-compact fires
is a configured value the operator can read and set. Several surfaces govern it. Each row states
what this plugin relies on; the pointer holds the units, ranges, and forms. Rows marked observed
were run on Claude Code 2.1.296 on 2026-10-10 in a throwaway config directory; the rest follow the
docs or the Claude Code changelog.

| Surface | Kind | What this plugin relies on | Pointer |
|---|---|---|---|
| `autoCompactWindow` | `settings.json` key | A token count that moves the trigger. When unset, the default comes from the docs' default-thresholds table (pointer above), and we state no figure. Normalize it into the percentage shape before comparing (below). | [settings-reference: `autoCompactWindow`](https://code.claude.com/docs/en/settings-reference#autocompactwindow); [model-config: Set the auto-compact window](https://code.claude.com/docs/en/model-config#set-the-auto-compact-window) |
| `modelSettings.<model id>.autoCompactWindow` | `settings.json` key, per model | A saved per-model window (Claude Code 2.1.288). Observed 2026-10-10 on 2.1.296: wins over the top-level `autoCompactWindow` in the same file, and a project-scope top-level key still beats a user-scope per-model value. Per docs, not observed: a managed-settings window holds even after `/autocompact` saves a value. Not observed: on models other than Opus. | [model-config: Set the auto-compact window](https://code.claude.com/docs/en/model-config#set-the-auto-compact-window) |
| `/autocompact [auto\|<tokens>]` | slash command | Writes the per-model value above at user scope. Observed 2026-10-10 on 2.1.296: runs under `-p`, and with no argument prints the effective window and its source (settings or the environment variable). Per docs, interactively it opens a dialog showing the current window. Docs for the command: [commands](https://code.claude.com/docs/en/commands). | [model-config: Set the auto-compact window](https://code.claude.com/docs/en/model-config#set-the-auto-compact-window) |
| `--autocompact <tokens>` | CLI flag | Observed 2026-10-10 on 2.1.296: beats the settings keys above and loses to `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. | [cli-reference: CLI flags](https://code.claude.com/docs/en/cli-reference#cli-flags) |
| `autoCompactWindow` | subagent frontmatter | A subagent can carry its own window (Claude Code 2.1.296). Per the changelog only; the docs are silent and we did not probe it, so we read it as unconfirmed and never assume a subagent shares the session's trigger. | [Claude Code changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | environment variable | Read as the effective window whenever it is set, ahead of the setting, the command, and the flag. Observed 2026-10-10 on 2.1.296: beats `--autocompact`. | [env-vars: Variables](https://code.claude.com/docs/en/env-vars#variables) |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | environment variable | Read as able only to move the trigger earlier, never later. | [env-vars: Variables](https://code.claude.com/docs/en/env-vars#variables) |
| `autoCompactEnabled` / `DISABLE_AUTO_COMPACT` | `settings.json` key / environment variable | Either one turning auto-compact off leaves the dumb band as the only tripwire. We treated `DISABLE_COMPACT` as unconfirmed by docs: it came from our 2026-08-17 probe of the shipped binary's strings (v2.1.233) and was absent from the env-vars page on 2026-08-19. | [settings-reference: `autoCompactEnabled`](https://code.claude.com/docs/en/settings-reference#autocompactenabled); [env-vars: Variables](https://code.claude.com/docs/en/env-vars#variables) |

We read a configured window above the model's context window as the model's window: it extends
nothing.

Precedence, highest first, for the session's own window: `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, then
`--autocompact`, then project-scope settings, then the user-scope per-model value over the user-scope
top-level key. Every step in that order is observed. Managed settings are per docs, not observed:
a managed window holds even after `/autocompact` saves a value, and managed settings do not
override `--autocompact`. To see the effective window rather than derive it, run `/autocompact`
with no argument: observed under `-p` to print the value and its source, and per docs a dialog
when interactive.

- **Pointer**: per row above.
- **As of**: 2026-10-10
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
trigger at **40% of the full window**, which is *inside* the shipped percentage `smart` band
(≤ 50), so the percentage shape still reads smart when auto-compact fires, and the token shape,
which decides the zone there, reads `acceptable`: neither shipped shape reaches `dumb` first. Keeping the percentage bands below that trigger means pulling them under 40, not
comparing 400000 against the token bands' occupancy edges, which measure a different quantity.

That diagnostic reading is adopted; the prescription that usually travels with it is not. **Leave
auto-compact enabled.** Disabling it is a defensible operator choice on an attended machine, but it
is not this plugin's guidance: unattended cloud and autonomous sessions have no human at the
boundary, and for them a degraded continuation beats a hard stall at the window. The shipped ladder
is instrumentation, not prohibition: observable zones, then advisory injection, then an opt-in
blocking gate with a grace budget, with auto-compact remaining the last-resort safety net beneath
all of it (as-of 2026-08-17; recheck when Claude Code removes the auto-compact setting or changes
what it does at the window).

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
payload and prints the cause names. The snapshot carries `context_window` only, never
`prompt_cache`; pass the live payload to the script. The script prints whatever cause names
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
    "200000": { "smart_max_tokens": 100000, "acceptable_max_tokens": 150000 },
    "1000000": { "smart_max_tokens": 128000, "acceptable_max_tokens": 500000 }
  }
}
```

Validity is **per shape, independently**:

- **Percentage keys:** both values numeric, `0 < smart_max < acceptable_max ≤ 100`. Malformed
  (unparsable file, not an object, non-numeric, inverted, out of range, one key without the
  other, or both absent from an object holding a key outside `token_bands`, `actions`,
  `approach_margin` and `thresholds`) → shipped percentage defaults with a visible stderr notice
  from the resolver. An object with neither key and only those four keys keeps the shipped
  percentage defaults silently.
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
  replaces the default wording, which names the action (`block`'s describes the gate). The
  action's sentence appears at that zone's crossing and
  restatement, never on an approach line, labeled "operator setting for the <zone> zone".
  Default: `none` everywhere. `block` arms the gate in that zone.
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

The module writes only while something happens: after a tool call, after a response, during a
turn and at the session's end. A live-but-idle session's snapshot therefore goes stale by the
10-minute rule and resolves `unknown` until the next turn writes it again. That is correct
fail-open behavior, not a bug. An idle session asking for a zone gets a fresh snapshot from its
next tool call, which the question itself usually is. A session that has ended keeps its last real
reading on disk until it ages out. The writer's stale-file pruning cutoff (14 days) is deliberately
far above the staleness window, so idle sessions' files are never deleted out from under them.

## Sessions with no writer (`unknown` is structural)

The single capture channel is the module, so **a session where the module does not run has no
instrument at all**. No snapshot is written for it, and this contract resolves `unknown` for that
session permanently. The module runs in interactive, `-p`, SDK and `--bg` sessions alike; it does
not run:

- **In a WSL session of the Desktop app**, where plugins are not available.
- **Where mods are off**: Claude Code older than 2.1.287, `disableAllHooks`, `--bare`,
  `--safe-mode`, an organization's `allowManagedModsOnly`, mods switched off remotely, or after the
  hooks worker crashed. The PostCompact marker, a settings hook, still runs there wherever
  settings hooks do.
- **Where the plugin is not enabled** for the session, for example a project that disables it in
  `enabledPlugins`, or a cloud session the plugin does not reach. A cloud session that does load
  the plugin runs its hooks, per the table at the pointer below; no run of this plugin in a cloud
  session has been made.

- **Pointer**: [mods overview: where mods run](https://code.claude.com/docs/en/plugins/mods/overview#where-mods-run)
  and [turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: that table changes a row, or that section changes what stops a mod.

This is not a degraded install and not a missing dependency. Before the module, the only writer
was a statusline tee, and `reference/cloud-headless-capture.md` records the channel inventory made
then: every channel checked, its live URL, the date read, what it does and does not carry, and why
the OpenTelemetry `claude_code.api_request` event and the session transcript, which do carry live
occupancy, still cannot supply a snapshot.

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
writer side: whether the module runs in the session. A session with the module loaded has the
`mcp__context-guard__status` tool in its own tool list (deferred names included).

- **The tool is absent** (the module does not run here, or a policy refused its tool): structural.
  Report "no instrument in this environment" or "mods off", and never offer a fix the session
  cannot apply.
- **The tool is present, and after a tool call there is still no fresh snapshot**: a real defect,
  usually a missing `node` or an unwritable `~/.claude/context-guard/context/`. Run
  `/context-guard:check` for what the session can check itself (`node`, `jq`, whether the mod
  loads), and ask the operator to run `/context-guard:setup check`, which is user-only, for the
  rest of the diagnosis.
- **The tool is present and answers**: its zone is the module's live reading, and a consumer may
  use it in place of the file.

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

- The plugin's own module (first shipped consumer, see "The module"), and through it the
  `mcp__context-guard__status` tool, which any session with the module loaded can call as its
  zone lookup.
- The `plugin-quality` audit skill (context-gate: zone-informed dispatch and evidence-flush
  decisions, conservative on `unknown`). It resolves the zone through a generated copy
  of this plugin's `scripts/context-zone.sh`. Its co-located `zones-inline-drift.test.sh` lane,
  which runs in the repo's plugin-gate CI job, checks that resolver copy and the evidence-degraded
  marker path in its skill body against the values this file prints. That the copy matches
  its canonical, `lib/context-zone.sh`, is a separate gate, `scripts/sync-shared-copies.sh --check`.
