---
name: youtube-digest
description: "Watch YouTube videos, extract transcripts, harvest links, research claims, and synthesize repo-applicability recommendations. Use when: 'youtube', '/youtube-digest', 'watch this YouTube video', 'transcript for YouTube', user shares a youtube.com or youtu.be URL for a single public video (not a course platform). Actions: watch <url> (full pipeline), watch (dequeue epic queue), watch <n> (queue row), queue <url> (batch enqueue), transcript <url> (captions only), resume <video-slug>. Not for auth-walled course platforms — use /knowledge:course-digest."
argument-hint: "watch <url> [--target <repo>] | watch [--target <repo>] | watch <n> [--target <repo>] | queue <url> | queue list | transcript <url> | resume <video-slug>"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

youtube-extraction deps: !`node -e "const fs=require('fs'),path=require('path'),p=process.env.CLAUDE_PLUGIN_DATA;process.stdout.write(p&&fs.existsSync(path.join(p,'node_modules','@melodic','video-digestion'))?'installed':'MISSING - run setup-deps.mjs (see Prerequisites)')"`
yt-dlp: !`yt-dlp --version 2>/dev/null | head -1 || echo "MISSING — install yt-dlp (see Prerequisites)"`
ffmpeg: !`ffmpeg -version 2>/dev/null | head -1 || echo "MISSING — install ffmpeg (watch action only)"`
ImageMagick: !`magick -version 2>/dev/null | head -1 || echo "MISSING — install ImageMagick 7 (watch action only)"`

# YouTube

Absorb a single public YouTube video (transcript + visual frames), harvest reference links, fact-check claims through deeper external research, and produce a prioritized repo-applicability menu. Video download, bulk frames, working contact sheets, and shallow git clones use the OS temp directory — durable artifacts live under `.work/<watch-epic>/<video-slug>/` per the video-digest slice convention. One contact-sheet exception: `snapshot-bootstrap.js` copies the sheets into the slice at `key-frames/contact-sheets/*.jpg` as a **local disaster-recovery snapshot** — durable on disk (it survives `tempSession` cleanup, so recovering the sheets does not require re-running acquisition) but gitignored, so it is never committed (see the Output contract). That never-committed handling is a fixed, non-configurable part of this contract: a consumer that wants the source video, bulk frames, or contact sheets retained as a **committed**, re-runnable substrate (rather than regenerable temp state or a gitignored local snapshot) does not get that from this skill today — a documented, LFS-aware retention path is a tracked follow-up, not yet built.

Where this skill says "deeper research," use whatever external-research capability your project provides — for example the discovery plugin's `/discovery:research` / `/discovery:research-deep` when installed. Treat those as the reference implementation, not a hard dependency.

## Source discipline

Video content is a **secondary source** (on-screen and spoken claims are hypotheses, not verified facts). Treat them as hypotheses until promoted through deeper external research, and apply your project's own source-trust conventions. Repo conventions override video claims — surface convention conflicts explicitly; never silently adopt a video's shortcut over team rules.

## Video slug derivation

Derive `.work/<watch-epic>/<video-slug>/` from metadata title + video id:

1. Kebab-case the title (ASCII, lowercase, punctuation → hyphens)
2. Cap the title portion at **40 characters**
3. Append `-<video-id>` for uniqueness (e.g. `ai-coding-tips-7zZy1QTvokM`)

Implementation: `${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/transcript/derive-video-slug.js`

This skill's `.work/` root is **formally carved out** of the marketplace topic-docs convention (<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>): the work root resolves through the knowledge plugin's own `library_dir` seam, not the concern file's `memory_dir`; slug conformance is form-only (kebab-case `[a-z0-9-]`, ≤ 40 chars, Windows-reserved base names take an `-x` suffix); and nested `<epic>/<slug>/` sub-slices are sanctioned. Unlike the convention's never-committed memory tier, this skill writes no root `*` `.gitignore` of its own: its slice artifacts are the durable substrate, staged and committed per the Output contract — **provided the resolved work root is not itself gitignored**. That precondition is not automatic. Because the default work root and the convention's default `memory_dir` both resolve to repo-root `.work/`, a consumer that *also* adopts the topic-docs convention self-ignores that shared root (a `.gitignore` containing `*`), leaving these slices local until the work root is moved off it (e.g. a non-default `library_dir`); the skill does not force-add. The contact-sheet JPGs stay out of git in either case: `snapshot-bootstrap.js` writes a per-directory `.gitignore` (`*.jpg`) into `key-frames/contact-sheets/`, so staging a committable slice never sweeps them in.

## Artifact landing (work root)

Every extraction command in this skill runs through `run.mjs`, and each writes its `.work/<watch-epic>/…` artifacts under a work root resolved by `resolveWorkRoot()`. That root honors the knowledge plugin's personal `library_dir` user-configuration seam, substituted into this skill's content as `${user_config.library_dir}`:

- **Non-default** — when `${user_config.library_dir}` is a non-empty value other than the repo-root default `.` (and not an unexpanded `${user_config.library_dir}` token), pass it as a **leading** `--work-root` flag on **every** `run.mjs` invocation in this skill:

  ```bash
  node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" --work-root "${CLAUDE_PROJECT_DIR}/${user_config.library_dir}" <script.js> [args…]
  ```

  `run.mjs` forwards it to the extraction child as `YOUTUBE_WORK_ROOT` (a double-quoted CLI arg is cross-platform; an inline `YOUTUBE_WORK_ROOT=… node` prefix is bash-only and fails under PowerShell). When `library_dir` is already absolute, pass it directly and drop the `${CLAUDE_PROJECT_DIR}/` prefix. Two further **portable value forms** keep a machine-varying root out of stored configuration (a literal machine path in a settings value is what the guardrails hardcoded-path check exists to block): a leading `~` (home-relative, e.g. `~/knowledge-corpus`) and an environment-variable reference `${NAME}` or `%NAME%` (e.g. `${KNOWLEDGE_CORPUS_DIR}`, pointing at an OS user environment variable that holds the machine-specific root). Treat both like the absolute case — no `${CLAUDE_PROJECT_DIR}/` prefix — and pass the value verbatim in **single quotes** (literal in both bash and PowerShell), e.g. `--work-root '${KNOWLEDGE_CORPUS_DIR}'`: the launcher expands `~` and the variable reference itself and exits loudly on an unset variable, whereas shell-level expansion would silently substitute an empty string. This applies to **all** the run-script sites below — `run-transcript.js`, `preflight-metadata.js`, `queue-claim.js`, `run-watch.js`, `watch-state.js`, `vision-gated-promote.js`, `init-watch-checklist.js`, `analyze-harvested-repos.js`, `check-research-complete.js`, `check-watch-outcomes.js`, and `run-resume.js` — not only the first.

- **Default / unset** — when `${user_config.library_dir}` is `.`, empty, or still an unexpanded token, invoke `run.mjs` **without** `--work-root`. `resolveWorkRoot()` falls back to `${CLAUDE_PROJECT_DIR}` (then `process.cwd()`), landing artifacts at the consuming repo root.

**Agent-written artifacts share the same root — do not split the slice.** Every `.work/<watch-epic>/…` path in this skill and its `context/` files is relative to this same resolved work root, not always the repo root. That includes the paths you materialize by hand — the `mkdir -p .work/<watch-epic>/claims` and `QUEUE.md` copy/append steps under **Queue action**, the `claims/*.json` stubs, and every agent-authored slice artifact in the **Output contract**. When `${user_config.library_dir}` is non-default, write them all under `${CLAUDE_PROJECT_DIR}/${user_config.library_dir}/.work/<watch-epic>/…` so the queue table, its concurrency claims, and the `--work-root` script output share one root; a split root would let `queue list` / `watch` read claims from a different directory than the table being edited. For the portable value forms, resolve the root **once** before writing anything — `~` is the home directory; an env-var reference reads via `printenv NAME` (bash) or `$env:NAME` (PowerShell) — and use that resolved absolute root for every agent-written path, matching what the launcher resolves for the scripts. Default / unset → repo-root `.work/<watch-epic>/…` as written.

The `setup-deps.mjs` install step is exempt — it installs node dependencies into `${CLAUDE_PLUGIN_DATA}`, not the work root.

**Scope of the seam.** `library_dir` relocates the work *root*; it does not reshape the `<watch-epic>/<video-slug>/` sub-path itself. A consumer whose own convention lands source material at a differently-shaped path (for example `sources/<type>/<slug>/`) does not get that shape from this skill today — land under `library_dir` as-written and re-lay-out by hand, or fork the sub-path in your own automation. Templating the sub-path shape is a tracked follow-up, not yet built; this skill's contract is root relocation only.

## yt-dlp & throttle overrides

Four more personal `userConfig` options tune YouTube acquisition. Each is wired the **same** cross-platform way as `--work-root` — a leading, double-quoted flag on the `run.mjs` invocation that the launcher forwards to the extraction child as an environment variable (these env vars are internal plumbing, not a channel to set by hand). Apply the **same guard** as `library_dir`: pass a flag only when its option holds a non-empty value other than the option default, and not still an unexpanded `${user_config.…}` token; otherwise omit it and the pipeline keeps its built-in default. All are leading and order-independent, so they combine with `--work-root` in any order:

| Option | Flag | Pass when | Effect |
|---|---|---|---|
| `${user_config.yt_dlp_js_runtimes}` | `--js-runtimes "<value>"` | set and not the default `node` | `off` omits yt-dlp's `--js-runtimes`; any other value selects that runtime |
| `${user_config.yt_dlp_cookies_file}` | `--cookies-file "<value>"` | non-empty | authenticated acquisition from a Netscape cookies.txt (never commit it) |
| `${user_config.yt_dlp_cookies_from_browser}` | `--cookies-from-browser "<value>"` | non-empty | forces one browser's cookies instead of the automatic platform-ordered fallback; a cookies file wins over it |
| `${user_config.max_concurrent_acquires}` | `--max-concurrent-acquires "<value>"` | set and not the default `1` | caps concurrent acquisitions (1–3); higher increases HTTP 429 risk |

Example combining a non-default library dir with a forced cookie source (unset options contribute no flag):

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" \
  --work-root "${CLAUDE_PROJECT_DIR}/${user_config.library_dir}" \
  --cookies-from-browser "${user_config.yt_dlp_cookies_from_browser}" \
  <script.js> [args…]
```

## Action router

| Action | Status | Behavior |
| --- | --- | --- |
| `queue <url> [url...]` | **Active** | Append URLs to epic `.work/<watch-epic>/QUEUE.md`; dedupe by `video-id`. |
| `queue list` | **Active** | Show `QUEUE.md` table + active `claims/*.json` stubs. |
| `transcript <url>` | **Active** | Captions only — no video download. Runs acquisition + transcript pipeline. |
| `watch` | **Active** | Dequeue first `pending` queue row (FIFO) — claim stub → bootstrap → full skill pipeline. |
| `watch <n>` | **Active** | Dequeue queue row `#n` only (parallel path across terminals). |
| `watch <url>` | **Active** | Full pipeline: ≤1080p download → frame selection → vision absorption → link harvest → research agenda → repo-applicability synthesis. |
| `resume <video-slug>` | **Active** | Continue interrupted watch from `watch.json` phase-map state in `.work/<watch-epic>/<video-slug>/`. |

`--target <repo>` is an optional modifier on any `watch` form (not a dispatchable action of its own) — see "Synthesis target resolution".

**Queue SSOT:** `context/watch-queue.md`. Template: `templates/queue.md`.

## Transcript action

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" transcript/run-transcript.js "<youtube-url>"
```

Pipeline:

1. **Acquire** — yt-dlp in transcript mode (captions + info JSON + comments; `--skip-download`)
2. **Caption ladder** — manual EN → auto EN → auto-translate EN → STOP + surface if exhausted
3. **Clean** — auto-caption dedup when the selected rung is auto-generated
4. **Parse** — WebVTT → `[M:SS]` paragraph `transcript.txt`
5. **Write** — `.work/<watch-epic>/<video-slug>/transcript.txt` + `README.md` stub (journey template: `templates/readme-journey.md`)

Caption acquisition flags (see `acquisition/build-yt-dlp-args.js`): `--write-subs --write-auto-subs --sub-langs "en.*,-live_chat" --sub-format vtt`.

## Queue action

Epic queue at `.work/<watch-epic>/QUEUE.md` batches URLs before watch (canonical epic dir: `youtube-watch`). **Claim stub first, table second** — see `context/watch-queue.md`.

### Materialize queue

On first `queue` use:

1. `mkdir -p .work/<watch-epic>/claims`
2. Copy `templates/queue.md` → `.work/<watch-epic>/QUEUE.md` if missing
3. **Preflight each URL** (validate + fetch title/channel — see below), then append rows with next `#` index (do not renumber existing rows)

Dedupe on add: `extractVideoId` from `${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/acquisition/acquire.js` — skip URLs whose `video-id` already appears in the table.

### Companion primary sources (optional at queue)

When the operator supplies companion URL(s) with queue intent, record before watch — **SSOT:** `context/companion-primary-sources.md`. Template: `templates/companion-source-brief.md`.

1. After preflight `enqueue`, derive `video-slug` from `displayTitle` + `videoId`.
2. Write `.work/<watch-epic>/<video-slug>/source/companion-sources.md` (section fan-out table + integration checklist).
3. Pre-fill `slug` on the `QUEUE.md` row; `notes` → `companion — source/companion-sources.md`.

### Preflight (validate + metadata)

Run before appending so a human or agent reading the queue sees what each row is without opening the URL, and dead links never enter the queue:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" acquisition/preflight-metadata.js "<url>" ["<url>"...]
```

Routes through the same `spawnYtDlpWithAuthFallback` path as acquisition (bot-checked videos are not falsely rejected). Per-URL JSON `action`/`status` decides enqueue-vs-reject and fills the `title` + `channel` columns — full decision table in `context/watch-queue.md` "Preflight (every `queue` add)".

### `queue list`

Read `QUEUE.md` and run:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/queue-claim.js list
```

Show which rows have active claim files.

### Dequeue (`watch` or `watch <n>`)

1. **Stale reclaim (optional):** `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/queue-claim.js stale-check` — reset abandoned `in_progress` rows to `pending` when claim files are older than 7 days.
2. **Pick row:** `watch` → first `pending` in `#` order; `watch <n>` → row `#n` must be `pending` or resumable `in_progress` you own.
3. **Exclusive claim** (before editing `QUEUE.md`):

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/queue-claim.js claim <n> [--video-id <id>]
```

Exit code `2` = row taken — for FIFO, try next `pending`; for `watch <n>`, stop with a clear message.

1. Set row `status` → `in_progress` in `QUEUE.md`.
2. Run **Watch action** below with the row URL (or `run-resume.js` when slice exists and phases remain).
3. On verify script exit 0 → row `complete`; on abort → `failed` + one-line `notes`.
4. **Release claim:** `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/queue-claim.js release <n>`

**Parallel terminals:** prefer `watch 2` / `watch 4` in separate sessions — not two auto-`watch` on the same row.

## Watch action

Phase-flow overview (mermaid diagram + phase summary table): `context/workflow.md`.

### Companion deep-dive (Phase 0b — before CLI bootstrap)

When `source/companion-sources.md` exists: run Phase 0b **before** `run-watch.js`. **SSOT:** `context/companion-primary-sources.md`.

WebFetch companion URL(s) → subagent fan-out per section table → `source/companion-digest/<section-slug>.md` + hub `source/companion-digest/README.md` → `mark-phase <slice-dir> companion`. No surface reads; use deep external research per section. Downstream phases frame against the digest (claim inventory, research agenda, vision, synthesis).

On resume: if companion unmarked, run 0b before vision even when CLI phases exist.

### CLI bootstrap (deterministic stages)

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/run-watch.js "<youtube-url>" [--skip-research]
```

Runs acquire (retry + throttle) → transcript → dynamic coverage watching → metadata link harvest. Writes:

- `.work/<watch-epic>/<video-slug>/source/transcript.txt`
- `.work/<watch-epic>/<video-slug>/run-state/watch.json` — phase-map + `tempSession` paths
- `.work/<watch-epic>/<video-slug>/key-frames/selection.json` — temp frame/sheet paths (no bulk copy into repo)
- `.work/<watch-epic>/<video-slug>/key-frames/coverage-plan.json` — dynamic sampling plan
- `.work/<watch-epic>/<video-slug>/source/harvested-links.json`
- `.work/<watch-epic>/<video-slug>/run-state/continuation-prompt.md`

Bulk frames and working contact sheets stay in `tempSession` dirs (the sheets are additionally snapshotted to `key-frames/contact-sheets/` for local disaster recovery — see the Output contract); re-run `run-watch.js` to regenerate bulk frames when temp expired. `highVolume: true` in output → fan out vision subagents; no hard frame cap.

### Prerequisites gate (watch / resume)

Before `watch` or `resume` when frames are needed:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/setup-deps.mjs"
```

STOP if pre-computed context shows MISSING for yt-dlp, ffmpeg, or ImageMagick — install them per the Prerequisites section below. Cloud agents without the media toolchain: fail closed — do not run watch.

### Execution model (subagent fan-out)

After CLI bootstrap, parallelize like `/knowledge:course-digest` Phase 3:

| Wave | Agents | Output |
| --- | --- | --- |
| Parallel | Transcript agent | Claims + timestamps → `research/research-agenda.md` draft |
| Parallel | Visual agent | Contact-sheet triage → detail reads → `key-frames/visual-frames.md` + on-screen URLs |
| Parallel | Link/repo agent | WebFetch previews + `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" harvesting/analyze-harvested-repos.js <slice-dir>` when GitHub links exist |
| Sequential | Research fan-out | external research (standard or deep) per claim cluster → `RESEARCH.md` + `research/findings/` |
| Sequential | Synthesis agent | `recommendations/menu.md` + `recommendations/takeaways.md` (hub: `recommendations/README.md`) |
| Sequential | Interview handoff | `recommendations/interview.md` → offer `/interview` for POC/full-slice picks |

Mark each phase in `watch.json` via `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/watch-state.js mark-phase <slice-dir> <phase>` after the wave completes (idempotent — re-running an already-marked phase is a no-op). Promote only via vision-gated decisions:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/vision-gated-promote.js "<slice-dir>"
```

(`promote-key-frames.js` remains for ad-hoc single copies — not the completion path.)

### Watch checklist (mandatory)

After CLI bootstrap (or on resume), materialize and maintain the slice checklist:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/init-watch-checklist.js "<slice-dir>"
```

Use `--force` to regenerate per-sheet rows after `contactSheetCount` changes. Tick `[ ]` → `[x]` only with verification evidence (command exit code, artifact path, verify row). **Binary criteria SSOT:** `context/quality-gates.md`. **Ordered checkboxes:** `templates/watch-checklist.md` → slice `run-state/watch-checklist.md`.

Do not run `mark-phase` (`watch-state.js mark-phase`) or set `status: complete` while the phase verify script fails.

### Skill protocol (vision + research + synthesis)

After CLI bootstrap (or on resume), execute these phases in the skill session (mirror checklist phases 2–9):

1. **Vision planning (before fan-out)** — write `key-frames/vision-plan.md` from deterministic signals + a small inspection sample:
   - Inputs: `run-state/watch.json` (`contactSheetCount`, `densificationWindows`, `highVolume`, duration), `key-frames/coverage-plan.json`, `key-frames/selection.json`, transcript session boundaries
   - Classify content: `conference-multi-session` | `single-talk` | `screencast` | `slide-talk`
   - Segment long VODs by talk (welcome markers, agenda intros); assign triage scope per segment (full sheet vs spot-check vs escalation)
   - Escalate scope when: segment has ≥3 densification windows and &lt;1 promoted frame; sample shows code/diagram cells; transcript claims a demo/slide not yet captured
   - Promotion targets: `code-or-diagram`, `on-screen-text`, `relevant-to-synthesis`; dedupe against transcript + prior research

0b. **Claim inventory (before research agenda)** — write `research/claim-inventory.md`:

- Segment transcript into sessions with timestamps
- Extract verifiable claims per segment (product names, version gates, metrics, comparisons) as tier-3 rows
- Derive `research/research-agenda.md` clusters from the inventory; do not jump to research without this landscape pass

0c. **Staged deck harvest** — template: `templates/deck-inventory.md`; contract: `context/synthesis-contract.md`

- **Pass A (before full vision fan-out):** type URLs in `harvested-links.json` (`deck` | `repo` | `doc` | `other`); fetch deck candidates from metadata/chapters → `source/decks/<session-slug>/` + `source/deck-inventory.md`
- **Pass 1 triage** includes deck inventory — static slides covered by fetched deck → `skip`
- **Pass B:** merge on-screen URLs from early sheets; fetch new decks; re-filter remaining sheets
- Other downloads → `source/attachments/<kind>/`; citations → `research/sources.md` (template: `templates/sources.md`)

1. **Vision absorption (three-pass)** — contact-sheet triage → detail reads → transcript alignment → vision-gated promote + audit. Full per-pass procedure (JSON SSOT, scripts, promotion gates): `context/watch-pipeline.md`.

2. **High-volume advisory** — when `frameSelection.highVolume` is true, fan out vision subagents; do not truncate frames in temp.

   **Context-cost fan-out trigger** (independent of `highVolume`) — Pass 2 accumulates a read-count: every `keep-detail` frame escalated to 1920×1080 is a full-res Read that will not be reused after the vision pass. When that count is high enough that the reads would flood main context — context-flooding output you won't reuse — route to a per-sheet vision subagent returning **only JSON** (triage rows), keeping the main watch context lean. The signal is deterministic (the skill surfaces the read-count, mirroring the `highVolume` boolean shape); the *decide-to-delegate* is the agent acting on that fact. Do not hard-force fan-out in a script — the agent may have context reasons to process inline; the skill documents the threshold, the agent routes.

3. **Research stage (default-on)** — gate: `mark-phase <slice-dir> research` only after `check-research-complete.js` exits 0 and agenda clusters are `done` or `deferred`:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" evals/check-research-complete.js "<slice-dir>"
```

- `research/claim-inventory.md` must exist; draft or expand `research/research-agenda.md` with **claim clusters** mapped to inventory rows
- Per cluster: standard research, or deep external research when 3+ vendors/tools (template: `templates/research-cluster.md`)
- Write slice `RESEARCH.md` + optional `research/findings/*.md`
- Name each shard `research/findings/<cluster-topic-slug>.md` (e.g. `complex-types.md`) — the topic, not an opaque `RA1`/`RA2` ordinal; the agenda carries cluster ordering
- Each finding: author claim, consensus, staleness, promoted tier
- WebFetch top harvested URLs; `analyze-harvested-repos.js` clones to **temp only**

1. **Synthesis** (after research gate) — template: `templates/synthesis-item.md`

   **Synthesis target resolution** — every menu item and `templates/readme-journey.md`'s TLDR are framed against one resolved target, never an implicit "the repo I'm in". Because `templates/synthesis-item.md`'s **Target touchpoints** are grep-backed, the target must resolve to a **local working tree on disk**, not merely a name: explicit `--target <repo>`, resolved to a local checkout of that repo → the consuming project (`CLAUDE_PROJECT_DIR`) when `watch` runs directly inside a repo, with no separate corpus session → ask. An explicit `--target <repo>` that has no local checkout (e.g. run from a separate corpus session where that repo isn't cloned locally) does **not** resolve — stop and ask for its local checkout path rather than falling through to `CLAUDE_PROJECT_DIR`, grepping the current directory, or inventing touchpoint paths. Whichever rung resolves it, record the target's **portable name** in `README.md`'s `**Target:**` line (`templates/readme-journey.md`) — never the resolved checkout path, which is machine-local and `README.md` is a staged artifact per the Output contract. That line is a record for readers and downstream consumers of a finished slice, not resume state: the resolved tree path is session-local, and the name lands at synthesis, so a `resume` interrupted before then has nothing recorded and simply re-runs the rungs above — asking again when none resolves. Persisting the resolved target at watch start (`WatchState` plus the continuation prompt) so `resume` recovers it without asking is a tracked follow-up, not yet built. This aligns with (but does not depend on) the `/knowledge:apply` design (`docs/knowledge-integration-design.md`), which will eventually take over repo-fitting via its own `--target` argument from a corpus session (auto-cloning the resolved repo); when that skill is installed and built, prefer it for cross-repo fitting and treat this skill's menu as its input, not a replacement.

   - Materialize `recommendations/` from `templates/recommendations/` (hub README links all docs)
   - `recommendations/menu.md` — categories: `immediate-takeaway` | `worth-investigating` | `poc-candidate` | `full-slice` | `no-go`; P0–P2 + consensus notes
   - `recommendations/takeaways.md` — safe actions without further research
   - `recommendations/questions.md` — open questions for the user
   - Update `README.md` per `templates/readme-journey.md`
   - **Offer an HTML view** — optionally render a self-contained HTML dashboard of the prioritized recommendations menu (markdown stays the tracked record); follow your project's HTML-vs-markdown convention when one exists.
   - **No auto-implement** — `/interview` → `/planning:plan` → `/implement`
   - **Ephemeral, target-bound deliverable** — `recommendations/**` is this skill's own terminal output for the resolved target, not a corpus-wide durable record; it is written fresh per watch and is expected to be superseded by `/knowledge:apply`'s report→diff→PR flow once that skill ships

2. **Interview handoff** — write `recommendations/interview.md` with menu + *"Should we go further?"*; suggest `/interview` for POC/full-slice items.

3. **Phase markers** — after each skill phase, update `run-state/watch.json` via `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/watch-state.js mark-phase <slice-dir> <phase>`.

4. **Outcome verification (before `status: complete`)** — mandatory host verify script:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" evals/check-watch-outcomes.js "<slice-dir>" --write-report
```

Writes `verification/<ISO-basic>Z-watch-outcomes.md`. **Do not** mark the slice complete while this exits non-zero. Long conferences (`conference-multi-session`, ≥4h) must meet floors in `context/quality-gates.md`. Verify script `triage-agentic-required` fails `selection-signals` / missing model. Temp paths use `{tmp}` prefix (portable temp-session path serialization).

**Queue completion:** When this watch was started from `QUEUE.md`, set that row `complete` (or `failed` if verify never passes), run `queue-claim.js release <n>`, and refresh epic README breakdown.

### Frame selection pipeline (reference)

Deterministic frame-selection stages (`orchestrate-watching.js`), the standalone pipeline command, and metadata-only link harvest: `context/watch-pipeline.md`.

## Resume action

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/run-resume.js "<video-slug>"
```

Reads `.work/<watch-epic>/<video-slug>/watch.json`, identifies the next incomplete phase (`acquire` → `transcript` → `watching` → `vision` → `harvest` → `research` → `synthesis`), refreshes `continuation-prompt.md`, and emits a copy/paste-ready continuation prompt. When `tempSession` paths are missing, re-run `run-watch.js` before vision.

**Handoff ritual** (context pressure or session end):

1. Update `watch.json` phase markers with timestamps
2. Write `continuation-prompt.md` (completed phases, next phase, frame-selection state, known issues)
3. Tell the user: *"Session state saved. Run `/knowledge:youtube-digest resume <video-slug>` to continue."*

## Output contract

Per video-digest slice. This is the **single authoritative enumeration** of every produced artifact — the contract a fresh watch is graded against. `context/quality-gates.md` phase/criterion tables point at this table for the lane + staged verdict; do not re-enumerate staging there.

**KIND** — `SOURCE` (acquired / harvested input), `METADATA` (script-emitted machine state), `DELIVERABLE` (agent-authored synthesis). **Producer** — `script` (a deterministic `extraction/` writer materializes it, often from agent-authored JSON facts) or `agent` (authored inline by the watching/research/synthesis agent).

| Artifact | Lane | Staged | KIND | Producer |
| --- | --- | --- | --- | --- |
| `README.md` | root | yes | DELIVERABLE | agent (`templates/readme-journey.md`) |
| `RESEARCH.md` | root | yes | DELIVERABLE | agent (external research synthesis; required before research phase done) |
| `source/transcript.txt` | source | yes | SOURCE | script (`write-transcript.js`) |
| `source/harvested-links.json` | source | yes | SOURCE | script (`run-harvest.js`; on-screen links merged by agent during vision) |
| `source/harvested-repo-analysis.json` | source | yes (optional) | METADATA | script (`analyze-harvested-repos.js`; temp clone) |
| `source/deck-inventory.md` | source | yes (optional) | SOURCE | agent (deck fetch log; decks under `source/decks/`) |
| `source/companion-sources.md` | source | yes (optional) | SOURCE | agent (queue-time brief; `templates/companion-source-brief.md`) |
| `source/companion-digest/README.md` | source | yes (optional) | DELIVERABLE | agent (hub linking section digests) |
| `source/companion-digest/<section-slug>.md` | source | yes (optional) | DELIVERABLE | agent (per-section deep-dive; Phase 0b fan-out) |
| `research/claim-inventory.md` | research | yes | DELIVERABLE | agent (claim landscape; sessions + boundaries) |
| `research/research-agenda.md` | research | yes | DELIVERABLE | agent (claim clusters + status) |
| `research/findings/<topic>.md` | research | yes (optional) | DELIVERABLE | agent (per-cluster shards, topic-named) |
| `research/sources.md` | research | yes (optional) | DELIVERABLE | agent (`templates/sources.md`; decks/repos cited) |
| `key-frames/selection.json` | key-frames | yes | METADATA | script (`write-watching-manifest.js`; temp paths + timestamps) |
| `key-frames/coverage-plan.json` | key-frames | yes | METADATA | script (`write-watching-manifest.js`; dynamic sampling plan) |
| `key-frames/sheet-frame-index.json` | key-frames | yes | METADATA | script (`export-sheet-frame-index.js`) |
| `key-frames/vision-plan.md` | key-frames | yes | DELIVERABLE | agent (content class + segments + triage scope) |
| `key-frames/triage/batches/sheet_NNN.json` | key-frames | yes | DELIVERABLE | agent (per-sheet vision verdicts; one subagent per sheet) |
| `key-frames/triage/manifest.json` | key-frames | yes | METADATA | script (`merge-triage-json.js` over batches) |
| `key-frames/frame-triage-log.md` | key-frames | yes | METADATA | script (`render-triage-log.js` from manifest) |
| `key-frames/visual-frames.md` | key-frames | yes | METADATA | script (`rebuild-visual-frames.js`; pass-2 detail log) |
| `key-frames/visual-gaps.md` | key-frames | yes (optional) | METADATA | script (`expand-visual-gaps.js`; densification windows without frames) |
| `key-frames/promotion-decisions.json` | key-frames | yes | DELIVERABLE | agent (vision verdict per candidate PNG) |
| `key-frames/promotion-map.json` | key-frames | yes | METADATA | script (`vision-gated-promote.js`; name map + traceability) |
| `key-frames/key-frames-manifest.md` | key-frames | yes | METADATA | script (`render-key-frames-manifest.js`) |
| `key-frames/key-frame-quality-audit.json` | key-frames | yes | DELIVERABLE | agent (post-promotion per-frame `note`, min 20 chars) |
| `key-frames/key-frame-quality-audit.md` | key-frames | yes | METADATA | script (`render-quality-audit.js` from JSON) |
| `key-frames/frames/**` | key-frames | yes | DELIVERABLE | script (`vision-gated-promote.js`; curated frames only) |
| `key-frames/contact-sheets/snapshot-meta.json` | key-frames | yes | METADATA | script (`snapshot-bootstrap.js`; `{tmp}`-tokenized `sourceDir`) |
| `key-frames/contact-sheets/*.jpg` | key-frames | **never in git** | METADATA | script (`snapshot-bootstrap.js`; local DR snapshot, gitignored) |
| `recommendations/README.md` | recommendations | yes | DELIVERABLE | agent (hub — links menu, takeaways, questions, interview) |
| `recommendations/menu.md` | recommendations | yes | DELIVERABLE | agent (prioritized repo-applicability menu) |
| `recommendations/takeaways.md` | recommendations | yes | DELIVERABLE | agent (safe quick actions) |
| `recommendations/questions.md` | recommendations | yes | DELIVERABLE | agent (open questions) |
| `recommendations/interview.md` | recommendations | yes | DELIVERABLE | agent (end-of-watch `/interview` prompt) |
| `verification/<ISO-basic>Z-watch-outcomes.md` | verification | yes | METADATA | script (`check-watch-outcomes.js --write-report`) |
| `run-state/watch.json` | run-state | yes | METADATA | script (`watch-state.js`; phase-map + `tempSession`) |
| `run-state/watch-checklist.md` | run-state | yes | METADATA | script (`init-watch-checklist.js` from template) |
| `run-state/continuation-prompt.md` | run-state | yes | METADATA | script (`watch-state.js`; session handoff) |
| `media/frames/`, `media/contact-sheets/` | (OS temp) | **never in repo** | — | OS temp only |
| `*.vtt`, `video.*` | (OS temp) | no | SOURCE | OS temp — regenerable |

## Gotchas

Observed failure modes — recovery detail in `context/gotchas.md`: YouTube bot/sign-in cookie fallback, HTTP 429 backoff + concurrency cap, temp-session expiry (re-run `run-watch.js` before vision), cloud-agent media-toolchain fail-closed, retired `watch-progress.json`.

## Prerequisites

Verify before starting (stop and route to fix path on failure):

1. **youtube-extraction deps** — `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/setup-deps.mjs"`. Installs the pipeline's node dependencies into `${CLAUDE_PLUGIN_DATA}` (persists across plugin updates); idempotent — safe to re-run, and re-run after a plugin update.
2. **yt-dlp** — required for all actions. Floor **2026.6**. Install: `winget install yt-dlp.yt-dlp` (Windows), `brew install yt-dlp` (macOS), `pip install -U yt-dlp` or distro package (Linux). Acquisition throttling + bot-check cookie fallback: `## Gotchas`
   - **JS runtime:** `--js-runtimes node` by default (set the `yt_dlp_js_runtimes` option to `off` to omit)
3. **ffmpeg** — required for `watch` only (scene-detect frame extraction). Floor 7.1+.
4. **ImageMagick 7** — required for `watch` only (contact sheets). `magick -version`

If any prerequisite fails, stop and inform the user. Re-run `setup-deps.mjs` for the node dependencies; the media binaries (yt-dlp, ffmpeg, ImageMagick) are OS-level installs via your platform's package manager per the commands above.

## Eval fixtures

Driver video: `https://www.youtube.com/watch?v=7zZy1QTvokM` — slug `stop-prompting-claude-use-karpathy-s-met-7zZy1QTvokM`.

| File | Role |
| --- | --- |
| `evals/evals.json` | Skill behavior + driver golden eval cases |
| `evals/fixtures/driver-video-goldens.json` | Q&A bank (≥1 `frame_only` question) |

Manual variation smoke-test backlog (code screencast / slide talk / talking-head / mixed — tracking only, not a graded fixture): `reference/variation-matrix-backlog.json`.

D9 starting defaults: `${CLAUDE_PLUGIN_ROOT}/vendor/video-digestion/TUNING.md`. Retune after first host watch.
