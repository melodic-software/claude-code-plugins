# Watch pipeline — full phase procedure

Read for the **watch action only** (and for `resume`, which re-enters it). The hub carries the
ordered phase spine; this file carries what each phase actually does. A `transcript` run needs
none of it. Binary criteria SSOT: `quality-gates.md`. Artifact enumeration: `output-contract.md`.
Phase-flow diagram: `workflow.md`.

- [Phase 0b — companion deep-dive](#phase-0b--companion-deep-dive)
- [CLI bootstrap](#cli-bootstrap)
- [Prerequisites gate](#prerequisites-gate)
- [Execution model — subagent fan-out](#execution-model--subagent-fan-out)
- [Watch checklist](#watch-checklist)
- [Phase 1 — vision planning](#phase-1--vision-planning)
- [Phase 2 — claim inventory](#phase-2--claim-inventory)
- [Phase 3 — staged deck harvest](#phase-3--staged-deck-harvest)
- [Phase 4 — vision absorption (three-pass)](#phase-4--vision-absorption-three-pass)
- [Phase 5 — high-volume advisory](#phase-5--high-volume-advisory)
- [Phase 6 — research stage](#phase-6--research-stage)
- [Phase 7 — synthesis](#phase-7--synthesis)
- [Phase 8 — interview handoff](#phase-8--interview-handoff)
- [Phase 9 — outcome verification](#phase-9--outcome-verification)
- [Frame selection pipeline (reference)](#frame-selection-pipeline-reference)

## Phase 0b — companion deep-dive

Runs **before** CLI bootstrap, when `source/companion-sources.md` exists. **SSOT:**
`companion-primary-sources.md`.

WebFetch companion URL(s) → subagent fan-out per section table → `source/companion-digest/<section-slug>.md`
plus hub `source/companion-digest/README.md` → `mark-phase <slice-dir> companion`. No surface
reads; use deep external research per section. Downstream phases frame against the digest (claim
inventory, research agenda, vision, synthesis).

On resume: if companion is unmarked, run 0b before vision even when CLI phases already exist.

## CLI bootstrap

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/run-watch.js "<url>" [--skip-research] [--target <repo>]
```

Pass an explicit `--target <repo>` through from the invoking `watch <url> --target <repo>` command
— it is recorded in `watch.json` (`state.target`) so an interrupted watch's `resume` recovers it
instead of re-asking (see [Phase 7](#phase-7--synthesis)).

Runs acquire (retry + throttle) → transcript → dynamic coverage watching → metadata link harvest.
Writes:

- `source/transcript.txt`
- `run-state/watch.json` — phase-map + `tempSession` paths
- `key-frames/selection.json` — temp frame/sheet paths (no bulk copy into repo)
- `key-frames/coverage-plan.json` — dynamic sampling plan
- `source/harvested-links.json`
- `run-state/continuation-prompt.md`

Bulk frames and working contact sheets stay in `tempSession` dirs (the sheets are additionally
snapshotted to `key-frames/contact-sheets/` for local disaster recovery — see
`output-contract.md`); re-run `run-watch.js` to regenerate bulk frames when temp expired.
`highVolume: true` in output → fan out vision subagents; no hard frame cap.

## Prerequisites gate

Before `watch` or `resume` when frames are needed:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/setup-deps.mjs"
```

STOP if the hub's pre-computed context shows MISSING for yt-dlp, ffmpeg, or ImageMagick. Cloud
agents without the media toolchain: fail closed — do not run watch.

## Execution model — subagent fan-out

After CLI bootstrap, parallelize like `/knowledge:course-digest` Phase 3:

| Wave | Agents | Output |
| --- | --- | --- |
| Parallel | Transcript agent | Claims + timestamps → `research/research-agenda.md` draft |
| Parallel | Visual agent | Contact-sheet triage → detail reads → `key-frames/visual-frames.md` + on-screen URLs |
| Parallel | Link/repo agent | WebFetch previews + `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" harvesting/analyze-harvested-repos.js <slice-dir>` when GitHub links exist |
| Sequential | Research fan-out | external research (standard or deep) per claim cluster → `RESEARCH.md` + `research/findings/` |
| Sequential | Synthesis agent | `recommendations/menu.md` + `recommendations/takeaways.md` (hub: `recommendations/README.md`) |
| Sequential | Interview handoff | `recommendations/interview.md` → offer `/planning:interview` for POC/full-slice picks |

Mark each phase in `watch.json` after the wave completes (idempotent — re-running an
already-marked phase is a no-op):

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/watch-state.js mark-phase <slice-dir> <phase>
```

Promote only via vision-gated decisions:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/vision-gated-promote.js "<slice-dir>"
```

(`promote-key-frames.js` remains for ad-hoc single copies — not the completion path.)

## Watch checklist

After CLI bootstrap (or on resume), materialize and maintain the slice checklist:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/init-watch-checklist.js "<slice-dir>"
```

Use `--force` to regenerate per-sheet rows after `contactSheetCount` changes. Tick `[ ]` → `[x]`
only with verification evidence (command exit code, artifact path, verify row). **Ordered
checkboxes:** `templates/watch-checklist.md` → slice `run-state/watch-checklist.md`.

Do not run `mark-phase` or set `status: complete` while the phase verify script fails.

## Phase 1 — vision planning

Before fan-out, write `key-frames/vision-plan.md` from deterministic signals plus a small
inspection sample:

- Inputs: `run-state/watch.json` (`contactSheetCount`, `densificationWindows`, `highVolume`,
  duration), `key-frames/coverage-plan.json`, `key-frames/selection.json`, transcript session
  boundaries
- Classify content: `conference-multi-session` | `single-talk` | `screencast` | `slide-talk`
- Segment long VODs by talk (welcome markers, agenda intros); assign triage scope per segment
  (full sheet vs spot-check vs escalation)
- Escalate scope when: a segment has ≥3 densification windows and &lt;1 promoted frame; the sample
  shows code/diagram cells; the transcript claims a demo/slide not yet captured
- Promotion targets: `code-or-diagram`, `on-screen-text`, `relevant-to-synthesis`; dedupe against
  transcript + prior research

## Phase 2 — claim inventory

Before the research agenda, write `research/claim-inventory.md`:

- Segment the transcript into sessions with timestamps
- Extract verifiable claims per segment (product names, version gates, metrics, comparisons) as
  tier-3 rows
- Derive `research/research-agenda.md` clusters from the inventory; do not jump to research without
  this landscape pass

## Phase 3 — staged deck harvest

Template: `templates/deck-inventory.md`; contract: `synthesis-contract.md`.

- **Pass A (before full vision fan-out):** type URLs in `harvested-links.json`
  (`deck` | `repo` | `doc` | `other`); fetch deck candidates from metadata/chapters →
  `source/decks/<session-slug>/` + `source/deck-inventory.md`
- **Pass 1 triage** includes deck inventory — a static slide covered by a fetched deck → `skip`
- **Pass B:** merge on-screen URLs from early sheets; fetch new decks; re-filter remaining sheets
- Other downloads → `source/attachments/<kind>/`; citations → `research/sources.md` (template:
  `templates/sources.md`)

## Phase 4 — vision absorption (three-pass)

Checklist: `watching/frame-triage-checklist.json`; **JSON SSOT** + rendered markdown.

- **Pass 1 — contact-sheet triage:** One subagent per sheet from `tempSession.contactSheetsDir`
  (or `key-frames/contact-sheets/`). Write `key-frames/triage/batches/sheet_NNN.json` (cells per
  `sheet-frame-index.json`). Merge:
  `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/merge-triage-json.js "<slice>"`;
  validate: `validate-triage-json.js`; render: `render-triage-log.js`.
- **Pass 2 — detail reads:** All `keep-detail` frames + transcript interleave
  (`key-frames/selection.json` timeline). Escalate text-dense frames to **1920×1080**.
- **Pass 3 — transcript alignment:** For each densification window in `coverage-plan.json`, confirm
  ≥1 promoted or logged frame; gaps → `key-frames/visual-gaps.md`.
- **On-screen URLs:** Merge into `source/harvested-links.json` via `mergeHarvestedLinks()`.
- **Promote:** Write `key-frames/promotion-decisions.json` (vision verdict per candidate PNG).
  Apply `vision-gated-promote.js`. Sparse synthesis OK; no quota filler.
- **Pre-promotion gate:** Read the actual PNG; reject deck-covered slides, talking-head,
  transcript-redundant, unreadable, mislabeled. See `synthesisPromotionBar` +
  `synthesis-contract.md`.
- **Post-promotion review:** One subagent reads every `frames/*.png`; write
  `key-frames/key-frame-quality-audit.json` (substantive `note` per frame, min 20 chars); render
  `render-quality-audit.js` + `render-key-frames-manifest.js`. **Delete** failures with
  `pass: false`.
- **Repair pass (when filename verify fails):**
  `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/repair-synthesis-promotions.js "<slice-dir>"`
  — semantic renames from `gapNote`, reject generic pipeline placeholders, fix forbidden sessions.

## Phase 5 — high-volume advisory

When `frameSelection.highVolume` is true, fan out vision subagents; do not truncate frames in temp.

**Context-cost fan-out trigger** (independent of `highVolume`) — Pass 2 accumulates a read-count:
every `keep-detail` frame escalated to 1920×1080 is a full-res Read that will not be reused after
the vision pass. When that count is high enough that the reads would flood main context —
context-flooding output you won't reuse — route to a per-sheet vision subagent returning **only
JSON** (triage rows), keeping the main watch context lean. The signal is deterministic (the skill
surfaces the read-count, mirroring the `highVolume` boolean shape); the *decide-to-delegate* is the
agent acting on that fact. Do not hard-force fan-out in a script — the agent may have context
reasons to process inline; the skill documents the threshold, the agent routes.

## Phase 6 — research stage

Default-on. Gate: `mark-phase <slice-dir> research` only after `check-research-complete.js` exits 0
and agenda clusters are `done` or `deferred`:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" evals/check-research-complete.js "<slice-dir>"
```

- `research/claim-inventory.md` must exist; draft or expand `research/research-agenda.md` with
  **claim clusters** mapped to inventory rows
- Per cluster: standard research, or deep external research when 3+ vendors/tools (template:
  `templates/research-cluster.md`)
- Write slice `RESEARCH.md` + optional `research/findings/*.md`
- Name each shard `research/findings/<cluster-topic-slug>.md` (e.g. `complex-types.md`) — the
  topic, not an opaque `RA1`/`RA2` ordinal; the agenda carries cluster ordering
- Each finding: author claim, consensus, staleness, promoted tier
- WebFetch top harvested URLs; `analyze-harvested-repos.js` clones to **temp only**

## Phase 7 — synthesis

Runs after the research gate. Template: `templates/synthesis-item.md`.

**Synthesis target resolution.** Every menu item and `templates/readme-journey.md`'s TLDR are
framed against one resolved target, never an implicit "the repo I'm in". Because
`templates/synthesis-item.md`'s **Target touchpoints** are grep-backed, the target must resolve to
a **local working tree on disk**, not merely a name. Rungs, in order:

1. Explicit `--target <repo>`, resolved to a local checkout of that repo
2. The consuming project (`CLAUDE_PROJECT_DIR`) when `watch` runs directly inside a repo, with no
   separate corpus session
3. Ask

An explicit `--target <repo>` with no local checkout (e.g. run from a separate corpus session where
that repo isn't cloned locally) does **not** resolve — stop and ask for its local checkout path
rather than falling through to `CLAUDE_PROJECT_DIR`, grepping the current directory, or inventing
touchpoint paths.

Whichever rung resolves it, record the target's **portable name** in `README.md`'s `**Target:**`
line — never the resolved checkout path, which is machine-local while `README.md` is a staged
artifact. That line is a record for readers and downstream consumers of a finished slice, not
resume state. An explicit `--target` passed at CLI bootstrap is separately recorded in `watch.json`
(`state.target`, the portable name only); on `resume`, check `state.target` / the continuation
prompt's "Synthesis target" section first — when set, reuse it and skip this resolution entirely;
when unset, run the rungs above.

This aligns with (but does not depend on) the `/knowledge:apply` design
(`docs/knowledge-integration-design.md`), which will eventually take over repo-fitting via its own
`--target` argument from a corpus session (auto-cloning the resolved repo); when that skill is
installed and built, prefer it for cross-repo fitting and treat this skill's menu as its input, not
a replacement.

Outputs:

- Materialize `recommendations/` from `templates/recommendations/` (hub README links all docs)
- `recommendations/menu.md` — categories:
  `immediate-takeaway` | `worth-investigating` | `poc-candidate` | `full-slice` | `no-go`; P0–P2 +
  consensus notes
- `recommendations/takeaways.md` — safe actions without further research
- `recommendations/questions.md` — open questions for the user
- Update `README.md` per `templates/readme-journey.md`
- **Offer an HTML view** — optionally render a self-contained HTML dashboard of the prioritized
  menu (markdown stays the tracked record); follow your project's HTML-vs-markdown convention when
  one exists
- **No auto-implement** — `/planning:interview` → `/planning:plan` → `/implementation:implement`
- **Ephemeral, target-bound deliverable** — `recommendations/**` is this skill's own terminal output
  for the resolved target, not a corpus-wide durable record; it is written fresh per watch and is
  expected to be superseded by `/knowledge:apply`'s report→diff→PR flow once that skill ships

## Phase 8 — interview handoff

Write `recommendations/interview.md` with the menu + *"Should we go further?"*; suggest
`/planning:interview` for POC/full-slice items.

## Phase 9 — outcome verification

Mandatory host verify script, before `status: complete`:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" evals/check-watch-outcomes.js "<slice-dir>" --write-report
```

Writes `verification/<ISO-basic>Z-watch-outcomes.md`. **Do not** mark the slice complete while this
exits non-zero. Long conferences (`conference-multi-session`, ≥4h) must meet the floors in
`quality-gates.md`. Verify script `triage-agentic-required` fails `selection-signals` / missing
model. Temp paths use `{tmp}` prefix (portable temp-session path serialization).

**Queue completion:** when this watch was started from `QUEUE.md`, set that row `complete` (or
`failed` if verify never passes), run `queue-claim.js release <n>`, and refresh the epic README
breakdown. Protocol: `watch-queue.md`.

## Frame selection pipeline (reference)

Deterministic stages in `watching/orchestrate-watching.js`:

1. ffprobe duration + `compute-coverage-plan.js` dynamic targets (no hard cap)
2. Scene-detect + phash dedup + stratified interval + cue-anchor extractions
   (`extract-anchor-frames.js`)
3. Transcript densification windows (`watching/densification.js`)
4. Contact-sheet batching for triage (`watching/timestamp-interleave.js`)

Standalone pipeline (when video + VTT already acquired):

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watching/run-watching-pipeline.js "<video-path>" "<vtt-path>"
```

Metadata-only link harvest:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" harvesting/run-harvest.js "<info-json-path>"
```
