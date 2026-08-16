# Output contract and artifact landing

Where slice artifacts land (the work root and its `library_dir` seam) and what a finished slice
must contain (the authoritative artifact enumeration). Read before writing slice artifacts, before
staging a slice, and when grading a finished watch.

- [Work root resolution](#work-root-resolution)
- [Agent-written artifacts share the same root](#agent-written-artifacts-share-the-same-root)
- [Retention posture](#retention-posture)
- [Output contract](#output-contract)

## Work root resolution

Every extraction command in this skill runs through `run.mjs`, and each writes its
`.work/<watch-epic>/…` artifacts under a work root resolved by `resolveWorkRoot()`. That root
honors the knowledge plugin's personal `library_dir` user-configuration seam, substituted into
this skill's content as `${user_config.library_dir}`:

- **Non-default** — when `${user_config.library_dir}` is a non-empty value other than the
  repo-root default `.` (and not an unexpanded `${user_config.library_dir}` token), pass it as a
  **leading** `--work-root` flag on **every** `run.mjs` invocation in this skill:

  ```bash
  node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" --work-root "${CLAUDE_PROJECT_DIR}/${user_config.library_dir}" <script.js> [args…]
  ```

  `run.mjs` forwards it to the extraction child as an environment variable (a double-quoted CLI
  arg is cross-platform; an inline `VAR=… node` prefix is bash-only and fails under PowerShell).
  When `library_dir` is already absolute, pass it directly and drop the `${CLAUDE_PROJECT_DIR}/`
  prefix. Two further **portable value forms** keep a machine-varying root out of stored
  configuration (a literal machine path in a settings value is what the guardrails hardcoded-path
  check exists to block): a leading `~` (home-relative, e.g. `~/knowledge-corpus`) and an
  environment-variable reference `${NAME}` or `%NAME%` (e.g. `${KNOWLEDGE_CORPUS_DIR}`, pointing
  at an OS user environment variable that holds the machine-specific root). Treat both like the
  absolute case — no `${CLAUDE_PROJECT_DIR}/` prefix — and pass the value verbatim in **single
  quotes** (literal in both bash and PowerShell), e.g. `--work-root '${KNOWLEDGE_CORPUS_DIR}'`:
  the launcher expands `~` and the variable reference itself and exits loudly on an unset
  variable, whereas shell-level expansion would silently substitute an empty string. This applies
  to **all** run-script sites — `run-transcript.js`, `preflight-metadata.js`, `queue-claim.js`,
  `run-watch.js`, `watch-state.js`, `vision-gated-promote.js`, `init-watch-checklist.js`,
  `analyze-harvested-repos.js`, `check-research-complete.js`, `check-watch-outcomes.js`, and
  `run-resume.js` — not only the first.

- **Default / unset** — when `${user_config.library_dir}` is `.`, empty, or still an unexpanded
  token, invoke `run.mjs` **without** `--work-root`. `resolveWorkRoot()` falls back to
  `${CLAUDE_PROJECT_DIR}` (then `process.cwd()`), landing artifacts at the consuming repo root.

The `setup-deps.mjs` install step is exempt — it installs node dependencies into
`${CLAUDE_PLUGIN_DATA}`, not the work root.

`run.mjs` translates `--work-root` into `VIDEO_DIGEST_WORK_ROOT` — the variable
`resolveWorkRoot()` reads before the fallbacks above. Every extraction variable lives in that
`VIDEO_DIGEST_` namespace; each one's pre-rename `YOUTUBE_` spelling is still honored, warning
once per process, and the new name wins when both are set.

**Scope of the seam.** `library_dir` relocates the work *root*; it does not reshape the
`<watch-epic>/<video-slug>/` sub-path itself. A consumer whose own convention lands source
material at a differently-shaped path (for example `sources/<type>/<slug>/`) does not get that
shape from this skill today — land under `library_dir` as-written and re-lay-out by hand, or fork
the sub-path in your own automation. Templating the sub-path shape is a tracked follow-up, not yet
built; this skill's contract is root relocation only.

## Agent-written artifacts share the same root

**Do not split the slice.** Every `.work/<watch-epic>/…` path in this skill and its `context/`
files is relative to this same resolved work root, not always the repo root. That includes the
paths you materialize by hand — the `mkdir -p .work/<watch-epic>/claims` and `QUEUE.md`
copy/append steps, the `claims/*.json` stubs, and every agent-authored slice artifact in the
Output contract below.

When `${user_config.library_dir}` is non-default, write them all under
`${CLAUDE_PROJECT_DIR}/${user_config.library_dir}/.work/<watch-epic>/…` so the queue table, its
concurrency claims, and the `--work-root` script output share one root; a split root would let
`queue list` / `watch` read claims from a different directory than the table being edited. For the
portable value forms, resolve the root **once** before writing anything — `~` is the home
directory; an env-var reference reads via `printenv NAME` (bash) or `$env:NAME` (PowerShell) — and
use that resolved absolute root for every agent-written path, matching what the launcher resolves
for the scripts. Default / unset → repo-root `.work/<watch-epic>/…` as written.

**Carve-out from the topic-docs convention.** This skill's `.work/` root is formally carved out of
the marketplace topic-docs convention
(<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>):
the work root resolves through the knowledge plugin's own `library_dir` seam, not the concern
file's `memory_dir`; slug conformance is form-only (kebab-case `[a-z0-9-]`, ≤ 40 chars,
Windows-reserved base names take an `-x` suffix); and nested `<epic>/<slug>/` sub-slices are
sanctioned. Unlike the convention's never-committed memory tier, this skill writes no root `*`
`.gitignore` of its own: its slice artifacts are the durable substrate, staged and committed per
the table below — **provided the resolved work root is not itself gitignored**. That precondition
is not automatic. Because the default work root and the convention's default `memory_dir` both
resolve to repo-root `.work/`, a consumer that *also* adopts the topic-docs convention self-ignores
that shared root (a `.gitignore` containing `*`), leaving these slices local until the work root is
moved off it (e.g. a non-default `library_dir`); the skill does not force-add.

## Retention posture

Video download, bulk frames, working contact sheets, and shallow git clones use the OS temp
directory — durable artifacts live under `.work/<watch-epic>/<video-slug>/`.

One contact-sheet exception: `snapshot-bootstrap.js` copies the sheets into the slice at
`key-frames/contact-sheets/*.jpg` as a **local disaster-recovery snapshot** — durable on disk (it
survives `tempSession` cleanup, so recovering the sheets does not require re-running acquisition)
but gitignored, so it is never committed. `snapshot-bootstrap.js` writes a per-directory
`.gitignore` (`*.jpg`) into that directory, so staging a committable slice never sweeps them in.

That never-committed handling is a fixed, non-configurable part of this contract: a consumer that
wants the source video, bulk frames, or contact sheets retained as a **committed**, re-runnable
substrate (rather than regenerable temp state or a gitignored local snapshot) does not get that
from this skill today — a documented, LFS-aware retention path is a tracked follow-up, not yet
built.

## Output contract

Per video-digest slice. This is the **single authoritative enumeration** of every produced
artifact — the contract a fresh watch is graded against. `quality-gates.md` phase/criterion tables
point at this table for the lane + staged verdict; do not re-enumerate staging there.

**KIND** — `SOURCE` (acquired / harvested input), `METADATA` (script-emitted machine state),
`DELIVERABLE` (agent-authored synthesis). **Producer** — `script` (a deterministic `extraction/`
writer materializes it, often from agent-authored JSON facts) or `agent` (authored inline by the
watching/research/synthesis agent).

Vision and key-frame rows apply to results that carry video. A 0-video source result (see
`../reference/sources/x.md`) produces a text-only digest: the `key-frames/` lane is absent and the
slice is graded on the source, research, and recommendations lanes alone.

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
| `recommendations/interview.md` | recommendations | yes | DELIVERABLE | agent (end-of-watch `/planning:interview` prompt) |
| `verification/<ISO-basic>Z-watch-outcomes.md` | verification | yes | METADATA | script (`check-watch-outcomes.js --write-report`) |
| `run-state/watch.json` | run-state | yes | METADATA | script (`watch-state.js`; phase-map + `tempSession`) |
| `run-state/watch-checklist.md` | run-state | yes | METADATA | script (`init-watch-checklist.js` from template) |
| `run-state/continuation-prompt.md` | run-state | yes | METADATA | script (`watch-state.js`; session handoff) |
| `media/frames/`, `media/contact-sheets/` | (OS temp) | **never in repo** | — | OS temp only |
| `*.vtt`, `video.*` | (OS temp) | no | SOURCE | OS temp — regenerable |

**Source identity and provenance add no rows to this table** — every landed field rides inside an
artifact already listed:

- `sourceUrl` — a `run-state/watch.json` field, and the only place source identity lives. Source
  is never a directory level.
- `transcriptDegradation` — recorded in the `run-state/watch.json` phase map (transcript phase)
  and echoed on CLI output.
- X blocked delegations — the refused outbound link is harvested, so it lands in
  `source/harvested-links.json`; the acquire phase detail carries the count.
- X snowflake-aliasing flag (`source:snowflakeAliasing`) — acquisition-envelope only. **No slice
  artifact persists it**, so it is unreadable after the run. Whether that is acceptable or a gap
  worth a row is a live question, not a settled one.
