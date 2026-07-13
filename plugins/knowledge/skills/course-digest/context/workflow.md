# Course Digest Workflow

Eight phases executed in order. Each phase produces artifacts consumed by subsequent phases.

**Critical ordering rule:** ALL context must be gathered before summarization begins. Module
summaries generated from transcripts alone are incomplete — they miss code syntax, visual
diagrams, repo patterns. Full sequence: Extract → Process Frames → Analyze Code
Repo → Validate → THEN Synthesize.

**Completeness markers:** Module summaries should note their context sources:

- `[transcript-only]` — generated without frames or code repo (acceptable for initial pass)
- `[transcript+frames]` — includes frame analysis (better)
- `[full-context]` — transcript + frames + code repo analysis (best)

## Phase 1: Discover

**Goal:** Extract complete course structure from the platform.

**Steps:**

1. Navigate to course URL using `navigate` tool
2. Read page to identify modules and lessons (use platform adapter for selectors)
3. For each module, extract:
   - Module title and position
   - Lesson titles, durations, URLs, completion status
4. Check for course-level resources:
   - Download button (course files)
   - GitHub repository link
   - Course description / prerequisites
5. Extract instructor name from **landing page** (JSON-LD `author` field or visible "Meet Your Instructor" section). Never guess — each platform hosts multiple instructors
6. Write `course.json` with full structure

**Output:** `course.json` — metadata + complete module/lesson tree

**Checkpoint:** Present course structure to user. Ask which modules to process (or confirm "all"). Only mandatory user interaction gate.

## Phase 2: Extract

**Goal:** Extract content from each lesson.

**Per lesson, in order:**

1. **Navigate** to lesson URL
2. **Transcript** — read from platform's transcript panel (adapter-specific). Save as `transcript.md` with timestamps preserved
3. **Screenshots** — capture frames per [screenshot strategy](../reference/screenshot-strategy.md). Only for lessons with visual content (code demos, slides, architecture diagrams). Save to `screenshots/` subdirectory
4. **Lesson notes** — check if platform provides written notes or supplementary text. Save as `notes.md` if available
5. **Code references** — extract any code shown in the lesson (from transcript context, screenshots, or linked resources). Save as `code-snippets.md`
6. **Progress** — update `course.json` with extraction status for this lesson

**Pacing:**

- Report progress every 5 lessons
- Save after every lesson (crash-safe)
- If transcript extraction fails for a lesson, log error and continue to next

**Output per lesson:** `transcript.md`, optional `screenshots/`, optional `notes.md`, optional `code-snippets.md`

## Phase 2b: Process Frames

**Goal:** Classify extracted frames, generate contact sheets, build manifests.

**Prerequisite:** Phase 2 must complete with `--extract-frames` for lessons with visual content.

**Steps (sequential):**

1. `node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" classify-frames.js --course-dir <path> --phase contact-sheets` — generate labeled thumbnail grids
2. `node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" classify-frames.js --course-dir <path> --phase dedup` — near-duplicate detection
3. `node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" generate-manifests.js --course-dir <path>` — curate frame sets per lesson
4. `node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" classify-frames.js --course-dir <path> --phase summary` — print frame inventory

**Output:** Contact sheets, dedup report, manifests per lesson.

**Note:** If frames not extracted (MCP course has 0 frames), skip this phase but note summaries will be `[transcript-only]`.

## Phase 2c-i: Download Course Resources

**Goal:** Download all referenced external resources (source code ZIPs, PDFs, SQL scripts,
Postman collections, etc.) so they're available locally for Phase 3 analysis.

**Prerequisite:** Phase 2 extraction must have produced `resources.json` files with download URLs.

**Steps:**

1. Scan all `resources.json` files for download URLs (hosted on CDN, not behind auth)
2. For each URL category:
   - **Source code ZIPs** → download to `code/downloads/` — replaces Phase 2c GitHub clone when no companion repo exists
   - **PDF slides** → download to `slides/` — referenced during visual analysis
   - **SQL scripts, Postman collections, OpenAPI specs** → download to `resources/` — referenced during code analysis
3. Verify downloads: check file sizes, validate ZIP integrity, confirm PDF readability
4. Build download manifest (`downloads.json`) mapping lesson → downloaded files

**Output:** `code/downloads/`, `slides/`, `resources/`, `downloads.json`

**Provider patterns:**

- **Dometrain**: "Download course files" button triggers ZIP download. GitHub repo link for code
- **Teachable**: Per-lesson download URLs in `resources.json` (`uploads.teachablecdn.com`). Often provides both "Initial" and "Final" ZIPs per coding lesson — delta between them shows exactly what the lesson teaches

**When a course has BOTH GitHub repo AND downloadable ZIPs** (like Teachable courses with per-lesson ZIPs):
use ZIPs for per-lesson code state, GitHub for final/latest state. ZIPs capture
code-at-recording-time; repo may have post-publication updates.

**Security note:** Downloaded files gitignored (`**/courses/**/code/*`, `**/courses/**/slides/*`,
`**/courses/**/resources/*`). Never commit third-party course resources to the repository.

## Phase 2c-ii: Analyze Code Repo

**Goal:** Clone or analyze the course's companion code repository and retain source
for Phase 3 code exploration.

**Prerequisite:** `course.json` must have `resources.githubUrl` OR Phase 2c-i must have
downloaded source code ZIPs. If neither exists, skip.

**Steps (GitHub repo path):**

1. `node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" analyze-code-repo.js --course-dir <path>` — clone to temp, detect structure, write metadata
2. Clone again to `code/repo/` for Phase 3 access: `git clone --depth 1 --single-branch <url> code/repo/`
3. Review `code/analysis.json` for repo structure (per-section vs single-state)
4. Build section-to-module mapping table — which repo sections correspond to which course modules
5. For per-section repos: section diffs show what code changed module-to-module

**Steps (ZIP-only path — no GitHub repo):**

1. Extract "Final" ZIP (latest complete state) to `code/repo/` for Phase 3 access
2. If per-lesson Initial/Final ZIPs exist, extract each Final to `code/repo/{module-slug}/`
3. Analyze project structure: detect .sln, .csproj, frameworks, NuGet packages
4. Write `code/analysis.json` with structure findings
5. Build section-to-module mapping from ZIP naming conventions (e.g., "02.4 - Lesson Title")

**Output:** `code/analysis.json`, `code/README.md`, `code/repo/` (gitignored, local only)

**Security note:** Never commit `code/repo/` — may contain third-party copyrighted code.
Gitignore pattern `**/courses/**/code/*` blocks everything except `analysis.json` and `README.md`.
Verify clone URLs are clean public URLs — never embed PATs or tokens in `course.json`.

**Freshness caveat:** Course companion repos may be updated after publication — authors sometimes
fix bugs, update packages, or refactor code post-recording. When Phase 3 finds discrepancies
between transcript and code, classify as:

- **Post-publication update** (likely) — newer package versions, renamed properties, added features
- **Recording-time bug** (possible) — logic errors, missing implementations
- **Intentional simplification** (possible) — transcript describes ideal, code takes shortcuts

Check repo's git log (`git log --oneline -20`) and last commit date against course
publication date to assess which discrepancies are updates vs original issues. Note: `--depth 1`
clones lose history — if freshness matters, clone without `--depth` for investigation phase
only, then discard.

## Phase 2d: Validate

**Goal:** Check extraction artifact quality before analysis begins.

**Prerequisite:** Phases 2-2c complete.

**Steps:**

1. `node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" validate-extraction.js --course-dir <path>` — run all quality checks
2. Review `validation-report.json` — fix any FAIL items before proceeding
3. On re-runs: compare against previous `validation-report.json` for regressions

**Output:** `validation-report.json` (serves as baseline for future runs)

**Quality gate:** Exit code 1 from validator means extraction has issues. Fix before summarizing.

## Phase 3: Synthesize

**Goal:** Produce per-module summaries combining all three knowledge modalities into a unified
analysis. A `[full-context]` summary is NOT just transcripts with metadata — it synthesizes what
the instructor says, what's shown on screen, what the actual code does.

**Three modalities (all required for `[full-context]`):**

| Modality | Source | What it captures |
|----------|--------|-----------------|
| Audio/transcript | `transcript.md` per lesson | Instructor explanations, arguments, verbal emphasis, things said but not shown |
| Visual/frames | Frame PNGs + `manifest.json` | Code on screen, architecture diagrams, slides, terminal output, UI demos |
| Code/repo | `code/repo/<section>/` source files | Actual implementation patterns, DI setup, project structure, what the code DOES vs what the instructor SAYS it does |

**Multi-agent approach per module:**

Each module gets parallel agents, then a synthesis pass:

1. **Transcript agent** — reads all `transcript.md` files for the module. Extracts concepts,
   arguments, anti-patterns, tools mentioned, lesson structure
2. **Visual agent** — views actual frame images (PNGs from `screenshots/`) and contact sheets.
   Reads code shown on screen, identifies architecture diagrams, captures visual content not
   described in the transcript. Use Read tool on images for multimodal analysis
3. **Code exploration agent(s)** — reads actual source files from matching `code/repo/`
   section(s). Understands implementation: `Program.cs`, tool classes, DI registration,
   project references, Dockerfiles. For larger sections, use multiple agents to divide and conquer
4. **Synthesis agent** — takes outputs from agents 1-3 and existing `module-summary.md`
   (if any). Produces final combined summary noting where modalities agree, disagree, or
   complement each other

**Agent sizing guidance:**

| Module type | Agents needed | Rationale |
|-------------|--------------|-----------|
| Conceptual (no code section) | 2 (transcript + visual) | No code to explore |
| Small code section (<20 files) | 3 (transcript + visual + 1 code) | Single agent covers the code |
| Large code section (20+ files) | 4+ (transcript + visual + N code) | Split code exploration by concern |
| Multi-section module | 3+ per section | Each repo section gets its own code agent |

**Section-to-module mapping (established in Phase 2c):**

Build this table during Phase 2c. Example from per-section repo:

```
| Repo Section              | Module | Lessons |
|---------------------------|--------|---------|
| 01-mcp-server-stdio       | M4     | L3      |
| 04-chat-agent             | M5     | L4      |
| 06-mcp-server-authenticated | M6   | L3-L5   |
```

**Per module, identify:**

- Core concepts taught (with lesson references)
- Code patterns demonstrated (from transcripts AND actual code AND visual frames)
- Discrepancies between what's said, shown, and coded (these are high-value findings)
- Best practices advocated
- Anti-patterns warned against
- Tools/libraries/frameworks mentioned (verify versions against current stable)
- Note context level: `[transcript-only]`, `[transcript+frames]`, or `[full-context]`

**Output per module:** `module-summary.md`

## Phase 4: Analyze

**Goal:** Produce course-level synthesis.

1. Read all module summaries
2. Identify cross-cutting themes spanning multiple modules
3. Assess instructor's overall philosophy and approach
4. Note any contradictions or tensions between recommendations
5. Write `analysis/course-summary.md`

**Output:** `analysis/course-summary.md`

## Phase 5: Recommend

**Goal:** Map course learnings to THIS repository. Primary deliverable.

1. Read `course-summary.md` + all module summaries
2. Read repository's CLAUDE.md, `.claude/rules/`, key architecture files
3. For each course concept, evaluate:
   - Does our repo already implement this? (skip if yes)
   - Relevant to our tech stack and architecture?
   - What would adoption look like concretely?
   - Effort/impact ratio?
4. Categorize recommendations using [analysis template](../reference/analysis-template.md):
   - CLAUDE.md / `.claude/rules/` rule candidates
   - Skill candidates (new `/skill-name` opportunities)
   - Architecture pattern changes
   - Testing practice improvements
   - CI/CD improvements
   - `/work-items` items
5. Write `analysis/repo-candidates.md` and `analysis/action-items.md`

**Output:** `analysis/repo-candidates.md`, `analysis/action-items.md`

## Phase 6: Store (continuous)

Runs throughout all phases — not a separate step. See [storage-schema.md](storage-schema.md) for complete directory structure.

**Rules:**

- Write artifacts as they're produced — don't buffer
- Update `course.json` status after each lesson/module
- All paths relative to `data/courses/<slug>/`

## Resuming

When invoked with `/knowledge:course-digest resume <slug>`:

1. Read `course.json` to find extraction status
2. Skip lessons already marked as extracted
3. Continue from the first un-extracted lesson
4. If all lessons are extracted, skip to Phase 2b (Process Frames) or Phase 3 (Synthesize)

## Execution model: sequential vs parallel

**Bot detection constraint:** All browser-based extraction (Phase 2) MUST be sequential. Dometrain and
similar platforms rate-limit and detect automated access. Navigate no faster than ~2 seconds between
lessons. Do NOT parallelize DOM interactions, browser contexts, lesson navigation.

**What can run in parallel:**

| Phase | Parallelizable? | Reason |
|-------|----------------|--------|
| 1 (Discover) | No | Single browser session, sequential navigation |
| 2 (Extract) | No | Sequential lesson navigation, bot detection risk |
| 2b (Process Frames) | Partially | Contact sheets + dedup are CPU-bound, can parallelize across modules |
| 2c (Code Repo) | Yes | Git clone + analysis is independent of browser state |
| 2d (Validate) | Yes | Pure filesystem analysis, no browser |
| 3 (Synthesize) | **Yes** | Per-module summaries are independent — no DOM interaction, pure LLM |
| 4 (Analyze) | No | Depends on all module summaries |
| 5 (Recommend) | No | Depends on course summary |

**Optimal pacing for Phase 2:**

- Navigate between lessons at ~1.5-2s intervals (current default via `page.waitForTimeout(1500)`)
- Faster navigation risks bot detection and session invalidation
- Slower is unnecessary — the platform serves pages in <1s

**Long-running extraction strategy:**

- 45-lesson course: ~90 min for transcripts, ~30+ min for frames
- Use `nohup` pattern for unattended runs (see SKILL.md)
- Monitor via `tail -20 extraction.log` and `run-report.json`

## Freshness verification (Phase 5 prerequisite)

**Before integrating any action item from `repo-candidates.md` into the repository:**

1. **Run `/explore`** on relevant codebase area — verify current state matches what the
   action item assumes. Codebase may have changed since course was digested
2. **Run `/research`** on specific library/framework/pattern — verify recommendation is
   current. Course content has a recorded-at date but no guarantee of currency:
   - NuGet/npm package versions may have changed (pre-release → stable, or breaking changes)
   - Framework APIs may have evolved
   - Best practices may have shifted
3. **Flag stale recommendations** in `action-items.md` with `⚠ STALE` marker if `/research`
   reveals recommendation is outdated

**Example:** MCP course references `ModelContextProtocol` NuGet packages that were pre-release
at recording time. Before using recommended patterns, verify current stable version via
`/research` or `mcp__nuget__get_latest_package_version`.

**Rule:** Course content is a starting point for research, not a final answer. Every action item
gets `/explore` + `/research` verification AT TIME OF INTEGRATION, not at digest time.
