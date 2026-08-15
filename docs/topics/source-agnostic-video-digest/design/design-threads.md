# Design threads — source-adapter contract

Status vocabulary: **RESOLVED** (decision made) · **directional** (direction agreed, details
deferred) · **OPEN** (awaiting decision) · **TAGGED-DEFERRED** (deferred with a research tag).

The `/planning:design-handoff` gate FAILs on any thread that is OPEN and untagged.

Threads inherited as already-settled are recorded in `inherited-decisions.md`. Line-budget
arithmetic is in `hub-split-budget.md`.

**Recommendations marked `[research-pending]` are provisional.** Five external-research topics and
one full local exploration are in flight specifically to test them; the user's standing instruction
is that incumbent structure is never itself a justification, so any recommendation whose only
support is "this is how the repo already does it" is held open until that evidence lands.

## Frontier ordering

| Round | Threads | Blocked by |
|-------|---------|------------|
| 1 | T1 adapter-home · T2a description-rewrite · T2b skill-rename · **A1 epic-dir + queue partition** · **A2 published config namespace** · T3 contract-shape (now includes dispatch) · T6 multi-media-posture · T7 spoke-topology · T10 x-read-coupling | — |
| 2 | T4 adapter-method-set · T11 error-taxonomy | T1, T3 |
| 3 | T5 transcript-source-posture · T9 test-seam-posture | T4 |

**A1 and T2b are decoupled** under A1's reframed recommendation (parameterize the epic, default to
the existing literal): the skill's display name and the on-disk default become independent, so a
rename never touches a consumer's `.work/` tree. The coupling would return only if A1 were resolved
by picking a different hardcoded literal — which is the framing the reframe rejects.

---

## T1 — adapter-home

**Status:** **RESOLVED — (a) `youtube-digest/extraction/adapters/`** (under user delegation,
2026-08-15, "proceed as you think is best"). Deciding rationale: the correctness argument below —
the two contracts are different abstractions, `vendor/` holds source-agnostic primitives only —
not the joint-ownership process cost.

Where the adapter contract and per-source adapters live.

| Option | Tradeoff |
|--------|----------|
| **(a) `youtube-digest/extraction/adapters/`** | Local to the single-video lane; zero blast radius on `course-digest` |
| **(b) `vendor/video-digestion/`** | The shared kernel — but its exports map has no adapter surface, and its README declares joint ownership |
| **(c) new sibling shared package** | Unjustified today — one consumer |

**Recommendation: (a).** The load-bearing argument is **correctness, not process**: the two
contracts are different abstractions.

**Premise corrected — an earlier version of this thread claimed "every method in `course-digest`'s
contract takes a Playwright `page`". That is false.** Measured against
`adapter-contract.js:16-28`: **8 of 12** declared methods take a `page`, and of the **five
`REQUIRED_METHODS`, three do** (`extractTranscript`, `extractHlsUrl`, `detectResources`, `:16-18`)
while **two do not** (`deriveLandingUrl`, `buildLessonUrl`, `:19-20`). `authenticate` and
`validateConfig` are also page-free.

**The conclusion survives on the corrected premise:** *most* of the required surface is page-centric,
and a contract whose majority assumes a browser page does not transfer to a URL/yt-dlp lane. But the
correction has a concrete consequence — **three signatures need re-deriving, not five**. The two
URL-building methods are already technology-neutral and are the part of the incumbent contract worth
carrying across. The vendor package's joint-ownership rule ("changing it means exercising both
consumers") is a real cost but is a *process* cost and must not be the argument.

**Positive rule to record so this is not relitigated:** `vendor/` holds source-agnostic primitives
with no knowledge of where media comes from; acquisition and adapters live in the consuming skill's
`extraction/` tree.

## T2a — description rewrite

**Status:** **RESOLVED** (under user delegation, 2026-08-15) — ship the widened description with
the feature, in the `xlsx` shape: literal host enumeration (`youtube.com`, `youtu.be`, `x.com`,
`twitter.com`), natural-language triggers, and an explicit `Do NOT` clause preserving the
`course-digest` boundary. Retain the existing `youtube` / `youtu.be` trigger tokens; target the
1,536-char combined listing cap, noting the 1,024 frontmatter-validation cap binds only if
claude.ai portability is later wanted. PLAN note: after T2b's rename the `skill-quality:check`
keyword diff runs against a new directory, so the sweep must verify trigger-token continuity
manually rather than relying on the HEAD diff.

The `description` field *is* the trigger mechanism. Leave it YouTube-only and X URLs never reach the
skill, no matter how correct the engine is. This is separable from — and strictly prior to — the
rename.

Constraint: `skill-quality:check` diffs trigger keywords against HEAD and FAILs on dropped ones, so
the widened description must retain `youtube`, `youtu.be`, and `/youtube-digest` tokens while adding
X's. The current description is already dense.

### Research: there is NO URL-pattern activation field — the description IS the only trigger

`paths:` is file globs, not URLs. Keyword matching in `description` is the entire mechanism by which
an `x.com` URL can reach this skill.

**Two distinct caps — do not conflate them.** Verified against the raw specification directly:

| Cap | Scope | Binds when |
|---|---|---|
| **1,024 chars** on `description` alone | Agent Skills spec frontmatter **validation** — *"Max 1024 characters"*, restated as *"Must be 1-1024 characters"*. Enforced on claude.ai upload, the Skills API, and `package_skill.py`; **not** enforced by Claude Code | only if claude.ai / routine portability is ever wanted |
| **1,536 chars** on `description` + `when_to_use` **combined** | Claude Code skill-**listing** truncation; configurable via `skillListingMaxDescChars` | today, for a plugin skill staying in Claude Code |

Above both sits a shared listing budget that can strip the description entirely — *"The budget scales
at 1% of the model's context window."* (Changelog v2.1.32 said 2%; current docs say 1% — use 1%.)

**Documented drafting mechanics:** write in third person (inconsistent POV causes discovery
problems); be specific and include key terms; and Anthropic's own `skill-creator` notes *"Claude has
a tendency to 'undertrigger' skills… please make the skill descriptions a little bit 'pushy'."*
Near-miss negative cases are the highest-value tests.

**The direct model is Anthropic's own `xlsx` skill** — it enumerates five formats literally and
closes with an explicit negative boundary (*"Do NOT trigger when the primary deliverable is a Word
document…"*). Apply the same shape here: enumerate `youtube.com`, `youtu.be`, `x.com`, `twitter.com`
literally, plus natural-language triggers, plus a `Do NOT` clause that preserves the existing
`course-digest` boundary.

The current description spends ~640 of 1,536 chars, so adding X hosts and a negative boundary fits
comfortably under 1,536 — but will press against 1,024 if portability is ever wanted. Over-trigger
remedy if the widened description over-fires: make it more specific, or set
`disable-model-invocation: true`.

## T2b — skill rename

**Status:** **RESOLVED — (a), rename to `video-digest`** (under user delegation, 2026-08-15).
Deciding rationale: the goal is a source-agnostic skill and a name that lies about scope fails it;
repo precedent (`shadowed-skill-renames/PLAN.md:32`) shows an established rename playbook. Execution
terms, all binding on the PLAN:

- Pin `name: video-digest` in frontmatter at rename time — recorded as a **deliberate exception**
  to the 205-file no-`name:` convention, so every future directory change is free.
- Treat the command rename as a **deliberate breaking change**: CHANGELOG entry + out-of-band
  announcement naming the five silent consumer surfaces (routines, scheduled tasks/`/loop`,
  `Skill()` permission rules, SDK allowlists, bare-`/name` squatting).
- PLAN enumerates: the five `course-digest` mechanical cross-references, the twelfth entry point
  (`detect-recoverable-bootstrap.js:106-113`), and the 5 CI occurrences.
- Sweep regression test: the three stale `/youtube` references in vendored READMEs/TUNING.md must
  be caught (and fixed regardless).

### Research verdict: directory rename is free (after one cheap fix); COMMAND rename is a hard break

**No alias, no redirect, no migration path exists.** Established by absence against the complete
frontmatter table, the plugin manifest schema, and the marketplace schema: no `alias`, `aliases`,
`former-name`, or `redirect` field. Raw grep of `skills.md`: `redirect` 0 hits, `rename` 0 hits,
`deprecat*` 0 hits, `shim` 0 hits.

**The one real stability seam** — `skills.md`, "How a skill gets its command name": *"In a plugin
skill, the frontmatter `name` replaces the directory name in the last segment of the command."*

**Verified: `youtube-digest/SKILL.md` has NO `name:` field.** Its command is derived from the
directory name, so **a directory rename IS a command rename today**.

**Do this regardless of which design wins:** pin `name: youtube-digest` in frontmatter now. It
decouples the directory from the command, making any future directory rename free and invisible to
consumers. Cheapest de-risking move available, and it is independent of T2b's outcome.

**Command-rename blast radius, worst failure first** — every one except the last is **silent**:

| # | Surface | Failure |
|---|---|---|
| 1 | Cloud routines | Cross-device, cloud-persisted prompts silently invalidated; no notice on any surface |
| 2 | Scheduled tasks / `/loop` | An unresolvable skill name *"reach[es] Claude as plain text instead of executing"* — degradation, not an error |
| 3 | Consumer `Skill(youtube-digest)` permission rules | Documented as EXACT match; silently stop matching. **A deny rule failing open is the security-relevant direction** |
| 4 | Agent SDK `skills:` allowlists | The only LOUD failure — TS `query()` throws, Python raises `ValueError` |
| 5 | Docs, cross-skill prose, bare-`/name` squatting | Cosmetic to moderate |

**`renames` exists but does not reach skills.** `plugin-marketplaces.md` documents a marketplace-level
`renames` map (v2.1.193+) with chain-following, settings rewriting, and a `Renamed to "x"` notice —
**plugin-scoped only**. There is no skill-level `displayName` either. And a *plugin* rename via
`renames` silently re-prefixes every skill command it ships, which `renames` does not address.

A forwarding shim skill is undocumented and unprohibited, but is model-mediated rather than a
redirect (costs a turn, non-deterministic), keeps squatting the old bare name, and consumers
**cannot hide it** — *"Plugin skills are not affected by `skillOverrides`."*

**Revised recommendation:** pin `name:` now; treat any command rename as a deliberate breaking change
announced out-of-band, not as a mechanical sweep. The rename's *cost* is no longer the 132-occurrence
sweep — that is the easy part — it is five consumer surfaces that fail silently.

| Option | Tradeoff |
|--------|----------|
| **(a) rename to a source-agnostic name** (e.g. `video-digest`) | Correct identity; breaking slash-command change plus a repo-wide reference sweep |
| **(b) keep `youtube-digest`, widen description only** | Zero migration; a name that lies about scope |
| **(c) keep it + a thin `x-digest` alias skill** | Two listing entries for one pipeline |

**Recommendation: (a)**, with execution sequenced into the plan. Repo precedent exists:
`docs/topics/shadowed-skill-renames/PLAN.md:32` records a prior `knowledge:youtube` →
`knowledge:youtube-digest` rename, in a table of many such renames — so the repo has an established
rename playbook shape, not just one instance.

### Measured blast radius

Counted, not estimated: **132 occurrences of `youtube-digest` repo-wide; 22 files outside the skill's
own directory.**

| Surface | Files | Notes |
|---|---|---|
| `plugins/knowledge` (outside the skill dir) | 12 | includes `plugin.json`, `CHANGELOG.md`, `README.md`, `setup/SKILL.md`, `docpage-digest/SKILL.md`, `map-corpus/SKILL.md` |
| `docs/topics/**` | 6 | prior topic slices |
| `docs/` root | 3 | `knowledge-integration-design.md:12`, `MIGRATION-PLAYBOOK.md:1455`, `CLOUD-SESSIONS.md` |
| `.github/workflows/ci.yml` | 1 file, **5 occurrences** | `cache-dependency-path` and three `working-directory:` values hardcode `plugins/knowledge/skills/youtube-digest/extraction` |

All spot-checked citations verified present: `PLAN.md:32`, `knowledge-integration-design.md:12`,
`MIGRATION-PLAYBOOK.md:1455`, `SKILL.md:16` (`# YouTube`).

CI is the loud surface — a missed path there fails the build rather than rotting silently. The
vendored READMEs and `TUNING.md` (see below) are the quiet ones, and they are the class that actually
survived the last rename.

**A twelfth entry point that GENERATES the skill path — verified.**
`watch/detect-recoverable-bootstrap.js:106-113` `formatRecoverCommand` returns a command string with
`skills/youtube-digest/extraction/run.mjs` hardcoded inside it. It is absent from `SKILL.md:48`'s
eleven and from the blast-radius table above. It matters twice: the literal breaks on rename, **and**
it emits a recovery command a user copies and runs, so a stale path there fails in the user's hands
rather than in CI.

### T2b CONFLICTS with an inherited completion criterion — needs an explicit re-scope

The handoff's completion criteria include: *"`course-digest` is unchanged — `git diff --stat` shows
no edits under `plugins/knowledge/skills/course-digest/`."*

**A rename makes that criterion unsatisfiable.** `course-digest` carries routing references to
`/knowledge:youtube-digest` in five files:

- `SKILL.md:2` — **inside its `description` field**, which is trigger text that
  `skill-quality:check` diffs against HEAD
- `SKILL.md:138` — routing table row
- `context/storage-schema.md:7`
- `evals/evals.json:19,21,25` — an eval case *named* `youtube-url-routes-to-youtube-digest-skill`,
  plus its `expected_output` and grading criteria
- `reference/adapters/discovery-checklist.md:65,221`
- (`extraction/setup-deps.mjs:50` is a comment mentioning both skills — cosmetic)

The criterion's *intent* is clearly "do not fold `course-digest` in, do not refactor it" — not "never
touch a string in it".

**RESOLVED (user-approved, 2026-08-14) — the criterion is re-scoped to:** *no behavioral or
structural change to `course-digest`; mechanical cross-reference updates forced by the rename are
exempt and must be enumerated in the PLAN.* The five files above are that enumeration's starting
set; the PLAN must list them explicitly so the exemption is auditable rather than open-ended.

### Empirical rename cost — the last rename of THIS skill left stragglers

`docs/topics/shadowed-skill-renames/PLAN.md:32` records a prior `knowledge:youtube` →
`knowledge:youtube-digest` rename. Three references to the **pre-rename** `/youtube` name survive
repo-wide today:

- `plugins/knowledge/vendor/video-digestion/README.md:5`
- `plugins/knowledge/vendor/repo-analysis/README.md:5`
- `plugins/knowledge/vendor/video-digestion/TUNING.md:55` (`After /youtube watch on driver video:`)

The known-miss class is exact and repeatable: **vendored-package READMEs and tuning docs** — the
low-traffic surfaces a reference sweep skips because they read as third-party. A `sed` over
`skills/` and `docs/` would have missed all three.

**Use these three lines as the T2b sweep's regression test.** A sweep that does not catch them will
not catch their successors. They should be fixed regardless of whether T2b proceeds — the stale name
is wrong today.

**Couples to A1.** Resolve together.

## A1 — epic directory, queue partition, migration

**Status:** move (i) **RESOLVED** (user-approved, 2026-08-14) · move (ii) **TAGGED-DEFERRED** with a
trigger. The thread was originally asking the wrong question; the earlier option set is retained
below as rejected alternatives rather than deleted.

### The reframe — source is not a partitioning axis, and epic was always meant to be a variable

The original framing asked *"what should the on-disk epic directory be called?"* and generated four
options, three of which made the source a directory level. That is wrong on its own terms: a video's
source is **slice metadata** — already recorded in `run-state/watch.json` — not a storage partition.
Partitioning storage by source would also make a mixed-source batch (queue a YouTube video and an X
video, drain them together) unrepresentable, which is the natural and desirable case.

The path has three axes, and source is none of them:

| Axis | Meaning | State today |
|---|---|---|
| **Root** | project / corpus | **Configurable** — `library_dir`, resolved by `work-root.js:19` |
| **Epic** | a batch or campaign of videos | **Documented as a variable, hardcoded in code** ← the actual defect |
| **Slug** | the individual video | Derived from title + key |

**Confirmed in code, not asserted:** `watch-state.js:40` declares `@property {string} sourceUrl` and
`:79-83` persists it into `watch.json` via `createWatchState`. Source is slice metadata **today**.

`SKILL.md` renders the path as `.work/<watch-epic>/…` — a placeholder — on **19** lines
(`:18,28,40,52,56,82,88,106,112,118,119,129,193-198,325`), and `:112` calls `youtube-watch` the
"canonical epic dir".

### A1 splits into two moves. Only the first is established.

An adversarial pass separated them. Recording the split because conflating them was a real error:
an established correction was being used to carry an unestablished feature into scope alongside it.

#### Move (i) — source is not a directory level · **RESOLVED, in scope**

Settled and confirmed in code. Consequences:

- **No per-source epic directories.** Kills the per-source option and both compatibility-read variants.
- **Default literal unchanged** (`youtube-watch`) — so no migration, no orphaning, every existing
  slice on every consumer's disk resolves as before.
- **One queue root, one `claims/` namespace** — no split queue, no claim-key collision.
- **Mixed-source batches work by construction**, which is the desirable case and the one per-source
  directories would have foreclosed.
- **A1 decouples from T2b on this alone.** The epic name stops tracking the skill name because the
  epic stops being a source axis — a cleaner reason than the storage-identifier argument, and one
  that does not depend on it.

#### Move (ii) — parameterize the epic value · **TAGGED-DEFERRED, out of scope**

Rejected for this refactor on three grounds.

**`SKILL.md:56` is a deliberate deferral, not evidence of drift.** It was cited here as the latter;
it reads verbatim: *"Templating the sub-path shape is a tracked follow-up, **not yet built**; this
skill's contract is **root relocation only**."* So `derive-video-slug.js:7` is that contract
*implemented*, not a drift from it. Pulling an explicitly-deferred feature into an X-parity refactor
because it is adjacent is scope creep — it needs its own justification, not move (i)'s coattails.

**It does not solve the problem it appears to solve.** The default stays `youtube-watch`, so
`watch <x-url>` with no epic argument still lands X content there. Parameterization relocates
responsibility for the name onto the user rather than fixing it. The honest description is "the
current shape plus an optional knob", not "strictly better".

**And it is not nearly free** — that claim was scoped to `queue-claim.js` and over-generalized. Three
independent consumers of the constant, only one parameterized:

| Consumer | State |
|---|---|
| `queue-claim.js:30` via `resolveEpicDir` | already takes its root as a parameter ✓ |
| `derive-video-slug.js:45` `resolveWorkSliceDir(repoRoot, videoSlug)` | **takes no epic parameter**; hardcodes the constant. Every caller (`run-watch.js:22`) needs threading |
| `watch-state.js:16` | imports the constant directly for the prose rendering at `:169,193` |

The **queue** path is parameterized; the **slice** path is not.

**Deferral trigger:** a user needing multi-batch or explicitly mixed-source epics, **or** A2
resolving the published-surface question (a `--epic` flag and/or `userConfig` key lands inside A2's
blast radius — CLI surface, config schema, CHANGELOG, docs — on a versioned marketplace plugin).
Renaming the default literal is filed with it and becomes cosmetic once nothing depends on the value.

#### Ships now regardless of (ii) — the display-leak fix

`watch-state.js:169,193` interpolate the constant into user-facing continuation-prompt prose, so an
X resume reads `youtube-watch/`. Render every user-facing path from the **resolved** slice dir, never
from the constant. Correct and cheap under (i) alone, and it is the precondition that makes (ii)
safe whenever (ii) is taken up.

**Scope correction: the epic constant is NOT the only YouTube string reaching a consumer's git
history.** `watch/export-sheet-frame-index.js:75` writes the literal `"{tmp}/youtube-sheets-unknown"`
as the `sheetsDir` fallback into `key-frames/sheet-frame-index.json` — an artifact the Output contract
**stages**. So a YouTube-named string is committed into every consumer's repo whenever the contact-
sheet temp dir cannot be resolved. Fix it alongside the display leak, and retract any claim that the
constant is the sole exposure. A sweep for other literal `youtube-` strings reaching staged artifacts
belongs in the PLAN.

### Rejected alternatives (retained — the original framing)

`transcript/derive-video-slug.js:7` exports `YOUTUBE_WATCH_EPIC_DIR = "youtube-watch"`. It is not a
path seam — it is a hardcoded YouTube name in every user's **durable** `.work/` tree:

- `derive-video-slug.js:45` builds the slice path from it
- `queue-claim.js:31` resolves the **queue root** from it
- `watch-state.js:169,193` writes it into resume prompts

### The population is not enumerable — this changes the option set

`lib/work-root.js:19` resolves the root as
`YOUTUBE_WORK_ROOT || CLAUDE_PROJECT_DIR || process.cwd()`, and `SKILL.md:48` documents `library_dir`
accepting an absolute path, a leading `~`, or a `${NAME}` / `%NAME%` environment reference
**specifically so the root can be machine-varying and live outside any repo**. This is a published
marketplace plugin, so the population that matters is every consumer's disk.

**A migration that enumerates known locations is therefore wrong by construction.** The 5-slice /
216-file sweep below is a floor on this machine, not a census. It is evidence *against* a bare
rename, not a scoping estimate for one.

| Option | Cost |
|--------|------|
| **(1) Backward-compatible read** — resolve slices under either epic dir; new writes take the new name | No migration owed and nothing orphaned. **But in its broad form it is a correctness defect, not a policy choice.** Claims are keyed by row number in a flat namespace — `claimFilePath(epicDir, row)` → `claims/${row}.json` (`queue-claim.js:39-40`). Two live epic dirs means two `QUEUE.md` files that both have a row 3, so `claims/3.json` is ambiguous; keeping two claims dirs instead means `reclaimStaleClaims` (`:166`) must sweep both or stale claims leak. See the narrow form below, which avoids this entirely |
| **(2) User-run migration command** shipped as a skill action, pointed at the user's own `library_dir` | Correct for an unenumerable population, but only runs if the user knows to run it. Leaves a long tail of unmigrated trees that option (1)'s compatibility read would still be needed to serve |
| **(3) Per-source epic dirs** | Splits the queue deliberately rather than accidentally; still rewrites the queue state machine |
| **(4) Keep `youtube-watch` as a stable STORAGE-FORMAT IDENTIFIER**, decoupled from the display name | Zero migration, zero orphaning, one queue root, no state-machine change. Costs an on-disk name that no longer matches the skill's name — **and one user-visible leak that must be fixed as part of it**, see below |

**A cheap option that survives if A1 is ever reopened.** The queue module is *already* parameterized:
`claimRow` (`:71`), `releaseRow` (`:126`), `listClaims` (`:139`), and `reclaimStaleClaims` (`:166`)
all take `epicDir` explicitly. The singleton exists in only two places — `resolveEpicDir`'s default
argument (`:30`) and the CLI entry (`:191`). So **slice resolution and queue root are separable**: a
backward-compatible read scoped to *slice* resolution only is a path join with no state machine and
no claim-key exposure, leaving the queue single-rooted. Option (1) is refuted in its broad form, not
in that narrow one. Recorded so a later revisit does not re-derive it.

### Measured migration cost — this is not hypothetical

Swept the machine for existing `youtube-watch` epic directories. **Five slices across two consuming
repos, 216 files already committed to git:**

| Repo | Slices | Tracked files | Queue |
|---|---|---|---|
| `melodic-software/knowledge-corpus` | 3 | 176 | none |
| `melodic-software/medley` | 2 | 40 | `QUEUE.md` present |

So a bare rename does not merely "orphan slices on disk" — it orphans **committed** content in two
real repositories, one of which has a live `QUEUE.md` whose rows point into the old path. A rename
therefore owes a migration that moves the directories, rewrites `QUEUE.md` row paths,
`run-state/watch.json` state, and the `continuation-prompt.md` bodies that `watch-state.js:169,193`
generated with the old constant embedded.

On this machine that is bounded — but see above: this machine is not the population.

### Recommendation: (4), and it decouples A1 from T2b

**Recommendation: (4) — keep `youtube-watch` as a stable storage-format identifier.**

The reasoning matters, because "zero migration, a lie on disk" is a weak argument and was the one
originally recorded here. The real argument is that **a storage-format identifier is not a display
name**, and the two are deliberately decoupled in mature systems: on-disk format identifiers
routinely outlive the product names that created them, precisely so that renaming a product does not
invalidate stored data. Holding the constant stable is therefore *format stability*, not incumbency —
it is the one option that survives an unenumerable install base without asking anyone to run
anything, and the only one that keeps a single queue root.

The surviving analogies are strong: `node_modules` is an npm-specific name that yarn, pnpm, and bun
all still write, precisely because it is stored state and renaming it would invalidate every tree in
existence. `.git` and `.vscode` are the same shape.

If the name's YouTube origin is judged unacceptable in a source-agnostic skill, option (2) plus the
narrow slice-only compatibility read is the honest expensive answer, and it should be costed as such
rather than reached for because the name looks wrong.

### (4) is not free — it leaks onto a display surface, and must ship with the fix

The "it is only stored state, users never read it" defence is **empirically false here**.
`watch-state.js:169` interpolates the constant into the continuation prompt a user reads —
``resume from `.work/${YOUTUBE_WATCH_EPIC_DIR}/${state.videoSlug}/` artifacts`` — and `:193` does the
same in its Instructions section. Under (4), a user resuming an **X** video is told to look under
`youtube-watch/`.

This is the cheapest defect on the board and does not sink (4), but (4) must ship with the fix rather
than a claim of zero user-visible cost:

- Render the resume prompt's slice path from the **resolved slice dir**, never by re-interpolating
  the epic constant into prose.
- Audit anything else that writes the constant into user-facing text. `preflight-metadata.js:4` uses
  the generic `.work/<watch-epic>/QUEUE.md` placeholder in a comment and is clean; `watch-state.js`
  is the one that is not.

**The line the design commits to, which is what makes the storage-identifier framing honest rather
than convenient:** *the constant is storage, and every user-facing rendering derives from the
resolved path rather than from the constant.*

**Consequence: the "A1 and T2b must resolve together" constraint dissolves under (4).** That coupling
was correct only given the assumption that the on-disk name must track the skill name — which is the
assumption (4) rejects. Under (4), T2b renames the skill freely and touches no consumer's `.work/`
tree. The constraint is retained in the frontier table **only** as a conditional: it binds if the
user chooses (1), (2), or (3).

**Still collides with T4 in the same module:** the slice-key change and this constant live in the
same 46-line file (`derive-video-slug.js`). One thread of work, not two — independent of which
option wins.

## A2 — published config and environment namespace

**Status:** **RESOLVED** (under user delegation, 2026-08-15) — rename-with-compatibility-read on
the env surface; downloader-scoped config keys keep their names; adapter-namespacing
TAGGED-DEFERRED.

| Option | Verdict |
|---|---|
| (a) keep `YOUTUBE_*` everywhere | Rejected — unlike A1's storage identifier, an env/config name is a **published interface**, read and typed by consumers; A1(4)'s format-stability argument does not transfer to it |
| (b) hard-rename | Rejected — silently breaks every consumer who set `YOUTUBE_WORK_ROOT` et al.; same unenumerable-population argument as A1 |
| **(c) rename + compatibility read** | **Adopted** — new `VIDEO_DIGEST_*` names primary; resolution checks new then old, warns once on old; deprecation documented in CHANGELOG with the T2b breaking-change entry |

Terms:

- All six env vars rename under (c) — the five in `run-args.js` **plus `YOUTUBE_ACQUIRE_PHASE_GAP_SEC`**
  (`acquire.js:24,57-58`), which is hereby named: it also enters the `run-args.js` flag map and the
  docs, closing the sixth-knob gap.
- `userConfig` keys `yt_dlp_*` / `max_concurrent_acquires` are **downloader- or pipeline-scoped, not
  YouTube-scoped** — accurate for both sources (X auth is also a yt-dlp cookies file). Keys keep
  their names; only the human-readable `"… (youtube-digest)"` titles change, mechanically, with T2b.
- **Adapter-namespaced config: TAGGED-DEFERRED.** Trigger: a third source, or the first auth/config
  knob that is not yt-dlp-shaped. Design note for that day: take streamlink's `@pluginargument`
  posture — declared name, type, validation, sensitivity — never `--extractor-args` string-parsing.
- A1 move (ii)'s deferral trigger referenced A2's resolution: this resolution does **not** fire it —
  no `--epic` flag or epic `userConfig` key ships here.

`plugins/knowledge/.claude-plugin/plugin.json:38-63` declares four `userConfig` entries literally
titled `"… (youtube-digest)"`: `yt_dlp_js_runtimes`, `yt_dlp_cookies_file`,
`yt_dlp_cookies_from_browser`, `max_concurrent_acquires`. `lib/run-args.js:22-33` maps CLI flags onto
`YOUTUBE_WORK_ROOT`, `YOUTUBE_YT_DLP_*`, `YOUTUBE_MAX_CONCURRENT_ACQUIRES`, and `SKILL.md:48`
documents `YOUTUBE_WORK_ROOT` as the launcher forwarding contract across eleven run-script sites.

This is a **versioned marketplace plugin**. Keep-prefix vs rename-with-deprecated-aliases vs
hard-rename is a deliberate decision needing a CHANGELOG entry, not a `sed`.

Second-order: `yt_dlp_cookies_*` are semantically YouTube-only. A flat namespace may not survive a
third source, so the design must also say whether auth knobs become adapter-namespaced.

**A sixth environment variable exists that the flag map does not cover — verified.**
`acquisition/acquire.js:24` declares `ACQUIRE_PHASE_GAP_ENV = "YOUTUBE_ACQUIRE_PHASE_GAP_SEC"`, read
by `resolveAcquirePhaseGapMs` (`:57-58`). It appears in **neither** `lib/run-args.js`'s five-entry
flag map **nor** `plugin.json`'s `userConfig` — it is a live runtime knob reachable only by
hand-setting the env var. A2 must name it explicitly, or it silently keeps the `YOUTUBE_` prefix
after every documented key is renamed.

## T3 — contract shape and dispatch

**Status:** **RESOLVED** (under user delegation, 2026-08-15) — **static host-keyed registry** with
declarative claims; regex only within a host an adapter already owns; unknown host fails closed with
the supported-source list; CI collision test kept as insurance, not present value. Deciding
rationale: the type-safety fix and the security fix are the same change — a static map is checkable
and untraversable, an interpolated specifier is neither (see SECURITY below). The type-lane
precondition is **implementation step zero**, not a design blocker. Priority/scoring stays out with
its deferral trigger recorded below (first format-shaped claim). `@satisfies` is the annotation
standard.

Provisional direction: reuse `course-digest`'s **pattern** — plain object, explicit
`REQUIRED_METHODS`, `validateAdapter` + `createAdapter` factory, `Result`-typed returns — with a
method set fitted to the URL/yt-dlp lane.

**What explicitly does NOT transfer, so an implementer does not copy the factory wholesale:**
`createAdapter(platform, platformCfg)` (`adapter-contract.js:70`) takes an **explicit platform
string resolved from config** and calls `validatePlatformConfig` (`:71`). This lane has no such
config and must **infer** the source from the URL.

That is why dispatch is folded into this thread rather than left downstream: it changes the factory
signature. Unknown host must fail closed with the supported-source list — the observed
`Unsupported URL: <external site>` failure shows yt-dlp will otherwise chase an outbound card link
off-platform.

### BLOCKING PRECONDITION — the repo's type lane is switched OFF

Verified directly, not relayed. **Both** extraction `tsconfig.json` files set `"checkJs": false`
(`course-digest/extraction/tsconfig.json:9`, `youtube-digest/extraction/tsconfig.json:9`) alongside
`allowJs: true` and `noEmit: true`, and there are **zero `// @ts-check` directives** anywhere in
`plugins/knowledge`. CI runs `tsc --noEmit` in both lanes and **passes green because it checks
nothing** in the JSDoc contract.

Probed with the repo-pinned TypeScript, identical files, one setting changed:

| Defect | `checkJs: false` | `checkJs: true` |
|---|---|---|
| Missing required method | silent | TS2741 |
| Excess property | silent | TS2353 |

**Consequence: the entire "runtime duck-typing vs types vs conformance suite" question was posed
against a checker that is not running.** Every JSDoc-dependent recommendation in this design is inert
until the lane is switched on. **That is the first implementation step, before any contract work.**

Two holes no annotation closes even once it is on: **too-few-parameters is accepted silently** (both
`@type` and `@satisfies`), and an **interpolated `import()` resolves to `any`**, which also stops the
checker examining the *host's* use of the result. Standardize on `@satisfies` — available in the
pinned version, catches missing (TS1360) and excess (TS2353) without widening the type.

### SECURITY — the incumbent resolver is path-traversable. Do not replicate it.

`course-digest/extraction/lib/config.js:44-51`:

```js
const adapterPath = join(thisDir, "..", "adapters", `${platform}.js`);
if (!existsSync(adapterPath)) return null;
return import(`../adapters/${platform}.js`);
```

**The defect is missing input validation, not a check/use mismatch** — a precision worth keeping,
because the wrong diagnosis leads to the wrong fix. Both the `join()` and the `import()` interpolate
the *same* `${platform}`, so `existsSync` does check the file that gets loaded. **The hole is that
`platform` is never charset-validated**, so `../secret/pwned` resolves to a real module outside
`adapters/` and the guard passes honestly. **CWE-829 + CWE-22.**

**The `%2e` hazard belongs to the obvious FIX, not to today's code.** A
`path.resolve(base, platform + '.js').startsWith(base)` guard *would* be bypassable, because `path`
does not percent-decode while ESM specifier resolution does — `%2e%2e` is an opaque directory name
to `path.resolve` and `..` to the URL resolver. Against today's code `%2e%2e` simply fails
`existsSync`. State it as **"do not fix it this way"**, not as a live bypass.

**Severity today is genuinely low — verified.** `platform` originates at
`extract-course.js:151-159` as `course.platform`, read from a `course.json` on disk, and there is
**no `argv` or `process.env` parsing at the entry point at all**. Local, config-driven. Worth fixing
on principle, not urgently.

**But the transfer risk inverts the severity, and that is the finding for this lane.** Here the
adapter is selected **from a URL** — untrusted remote input. Copying this shape and feeding it
anything URL-derived takes severity from low to high in one step.

**Design obligation: use a static registry — an explicit map from key to already-imported module —
not a computed dynamic import.** The type-safety fix and the security fix are the same change: a
static map is checkable *and* untraversable, while an interpolated specifier is neither.

### Dispatch has no incumbent idiom to reuse — verified

Two exhaustive negatives, both independently checked because reuse-or-replace leans on them:

- **No repo-wide governance rule** for how a one-contract-many-implementations surface must be built.
  `plugins/architecture/reference/` contains only `topic-docs.md`; `docs/conventions/` covers
  topic-docs only; `docs/adr/` holds 0001–0009, none about adapter seams. So the design is not
  diverging from a governed pattern — there is nothing to obey, only two divergent plugin-local
  contracts.
- **Exactly one implementation-dispatching dynamic import repo-wide** —
  `course-digest/extraction/lib/config.js:50` `return import(\`../adapters/${platform}.js\`)`. Every
  other `await import(` in `plugins/` resolves a Node builtin, an npm package, or a test helper.

**Consequence for reuse-or-replace:** there is no dispatch idiom to reuse, so designing dispatch from
external prior art is *reuse of a proven pattern*, not novelty-seeking. The incumbent *mechanism*
worth naming is `resolveAdapter` (`config.js:44-51`): filename-convention resolution
(`adapters/<platform>.js`) guarded by `existsSync`, not a registry — and it resolves from an explicit
platform string, which this lane does not have.

**Provenance note:** both negatives originated as relayed, unverified claims in an ungraded
exploration and were flagged by their own author as the highest damage-if-wrong items. They are
recorded here only because they were re-checked directly.

### Research verdict on dispatch — REVERSES the instinct to copy yt-dlp's `_VALID_URL` / `suitable()`

Gate-passed research against a yt-dlp checkout at `5d6b8c8`.

**The mechanism** (`YoutubeDL.py:1706-1725`): iterate an ordered dict, take the first extractor whose
`suitable()` returns true. `suitable()` defaults to `_match_valid_url(url) is not None`
(`common.py:627-632`). **No scoring, no priority, no ambiguity detection.** Ordering *is* the entire
arbitration policy — and the ordering fact that matters is an `assert`, not a comment:
`make_lazy_extractors.py:84` `assert ies[-1].__name__ == 'GenericIE'`.

**Counts over 940 extractor modules — independently reproduced by a verifier against the same pinned
checkout (`5d6b8c8`), with two figures corrected:**

| Measure | Count | Note |
|---|---|---|
| `suitable()` overrides outside `common.py` | **74** | exact |
| Lines where one extractor calls **another's** `suitable()` | **88** | exact (across 59 files) |
| `_VALID_URL` patterns needing a negative lookahead | **55** | *corrected from 54* |
| `YoutubeIE._VALID_URL` size | **2,582 bytes (2.5 KB)** | *corrected from ~2.7 KB* |

### The inference originally drawn from these counts is WITHDRAWN

The counts were first read as *"regex-on-URL dispatch does not avoid a host registry — it becomes one,
written by hand."* **That does not hold.** The verifier classified every one of them:

- **73 of 74** `suitable()` overrides sit in files defining **2+ extractor classes for the same
  site**. Exactly **one** is in a single-extractor file.
- **73 of 88** cross-extractor call lines reference a class **defined in the same file**. Only
  **15 of 88** are genuinely cross-module.

**So the counts measure *within-host* disambiguation** — YouTube video vs tab vs playlist, all on
`youtube.com` — **not cross-host collision.** A host-keyed registry would eliminate essentially none
of them; it would relocate them *inside* the host's adapter, where they would remain hand-written
mutual exclusion. And the recommendation below explicitly **keeps** within-host pattern matching. The
evidence was measuring the cost of the thing the recommendation preserves.

**Read plainly, the data is mild counter-evidence:** 15 genuinely cross-module arbitration sites
across 940 adapters says first-match-wins over URL regex scales *remarkably well* across hosts.

**Do not cite the 74/88/55 counts as the reason for host-keyed dispatch. They argue the other way.**

This is the **third instance in this design of the same error class** — real, reproducible numbers
carrying an interpretation they do not support (see also the `scripts/office` copy-paste inference
and the `< 5,000 tokens` corroboration label). It is the failure mode that survives verification
longest, because nobody disputes the fact and so nobody re-checks the conclusion drawn from it.

### R1 survives — on independent evidence that does hold

- **Declarative claims enable a cheap static index** — supported independently by the Pygments
  measurements (2 / 22 / 245 module imports) and streamlink's shipped `_plugins.json`.
- **The CI collision test** rests on two independent instances (gallery-dl's `test_extractor.py`
  round-trip, Tika's `findDuplicateParsers`), not on these counts.
- **`YoutubeIE.suitable()` parses the query string** — a genuine, specific demonstration that a URL
  regex cannot model every claim. It does not generalize to 940 modules, but it is real.

Two further documented facts:

- **Static ordering could not satisfy everyone.** `--force-generic-extractor` was deprecated for
  `--use-extractors` (`fe7866d0`), letting users name, reorder, and negate extractors at runtime.
  Precedence became a runtime knob.
- **The self-hosted-instance case has no regex answer** — PR #1791 (Mastodon/PeerTube/Misskey) open
  since 2021-11-25. **gallery-dl solved it**: `BaseExtractor.update()` compiles a host data table into
  the pattern at load time, with a `basecategory:URL` escape and user-registered instances.

**Honest absence:** no yt-dlp maintainer has ever publicly proposed host-based dispatch (seven query
phrasings, zero hits) — but the repo has GitHub Discussions **disabled**, so there is no design
corpus to find. Absence of proposal is not rejection.

**REVISED RECOMMENDATION — declarative host-keyed claims.** No scoring, no priority scale; regex only
*within* a host an adapter already owns. Add one **CI collision test**, on two independent
precedents: gallery-dl's full-registry round-trip (`assertEqual(cls, extractor.find(cls.example).__class__)`
across all 920 adapters) and Tika's `findDuplicateParsers()` (~20 lines).

**Deferred trigger for adding priority later:** the first adapter whose claim is *format*-shaped
rather than *host*-shaped (streamlink's `LOW_PRIORITY` `.m3u8` matcher is the canonical case).

### Scale mismatch — what NOT to inherit. This lane will have TWO adapters, not 940.

The prior art is drawn from systems with 920–940 handlers. Several of its mechanisms exist *because
of* that scale and are pure overhead here. Recorded explicitly so the PLAN does not lift them:

| Mechanism | Why it exists at scale | Verdict at N=2 |
|---|---|---|
| Lazy static index / codegen (`make_lazy_extractors.py`) | Regex compilation is ~80% of startup across 940 modules | **Out of scope.** Pure overhead |
| Registered-but-not-dispatched state (`_WORKING = False`, `AVFMT_EXPERIMENTAL`) | Operationally necessary where sites break weekly | **Out of scope.** With two adapters you know within one run |
| `--use-extractors` runtime reordering | Static ordering could not satisfy thousands of users | **Out of scope** |
| Scoring / priority scale | Needed once a declarative key stops being unique | **Out of scope**, and already rejected above |

**Cheap and worth it at N=2 — keep these:**

- **Declared arity (R4)** — the highest-value item in the whole set for this lane, and **not
  scale-driven at all**: X specifically has the 0/1/N problem and YouTube does not.
- **Four distinct error types (R5)** — three observed X failure modes plus YouTube's bot-challenge
  class already exist. Fits today.
- **Declared, namespaced per-adapter config (R6)** — this *is* the fix for the
  `YT_DLP_EXTRACTOR_ARGS` defect. Lands regardless of scale.
- **CI collision test (R2)** — ~10 lines. Near-worthless at N=2 (two adapters, two distinct hosts,
  collision impossible absent a written-wrong pattern), but it is what catches adapter three. Keep as
  **insurance, not present value**, and say so rather than overselling it.

**Transfer risk to state in the PLAN:** every system in the contrast set is **Python**, with runtime
class registration and metaclass machinery (`LazyLoadMetaClass`, `@pluginmatcher` decorators,
module-level `__plugin__` exports). This lane is **plain ESM with JSDoc types and vitest**. The
*shapes* transfer — a declarative claim, a canonical example, one extract method, a validate-and-
resolve factory. **None of the registration mechanisms do.** Lift the contract shape, not the
machinery.

**The convergent rule that decides this**, from five contrast systems: every *scored* system upgraded
to scoring because its declarative key stopped being unique (`.m`, `.ttl`, `ftyp`, ZIP/OLE2,
`application/xml`). URL-keyed systems never upgraded, because **a hostname is a unique key**. The
trigger is not handler count or input difficulty — it is *"can two independently-authored adapters
legitimately claim the same key?"* For hosts, no.

**Also adopt (documented, cheap, each from a named precedent):**

- **Split the declarative claim from the behavioural contract.** FFmpeg separates public
  `AVInputFormat` (metadata only) from the internal `FFInputFormat` vtable across an ABI boundary.
  That is precisely the split this contract is about to make.
- **Clamp what a handler can do to dispatch.** Pygments forces staticmethod-ness, clamps scores to
  [0,1], and converts exceptions and falsy returns to 0.0 — a misbehaving handler can be wrong but
  cannot crash dispatch. FFmpeg does none of this and pays for it with cross-handler knowledge
  embedded in independently-authored handlers (`wavdec.c`/ACT, `mp3dec.c`/ac3).
- **Take Tika's hint posture, not FFmpeg's.** A filename or `Content-Type` hint may select among
  candidates or specialize one, **never overrule** them, and an interpreted type from an `http(s)`
  URL is ignored outright. FFmpeg lets a server-supplied `Content-Type` add 30 points on zero content
  evidence. **This lane reads `Content-Type`, `og:video:type`, and filename extensions — all remotely
  controlled**, so Tika's posture is the security-relevant one.
- **Keep a registered-but-not-auto-dispatched state.** Every system has one
  (`AVFMT_EXPERIMENTAL`, `_WORKING = False`, `NO_PRIORITY`, `<parser-exclude>`). yt-dlp's is the most
  user-respectful: a broken adapter still *claims* the URL and says so, rather than falling through
  to a generic path and emitting a confusing partial result.

## T4 — adapter-method-set

**Status:** **RESOLVED** (under user delegation, 2026-08-15; T1 and T3 now resolved). The draft's
seven methods resolve to **five required methods + declared attributes**, applying the tier rule
below ("attribute > predicate > method") to every per-source variation that is data, not behaviour:

| Contract element | Kind | Stage | Disposition |
|---|---|---|---|
| `matchUrl(url)` | required method | dispatch | Kept — claim + canonicalization (T10 (ii)); no I/O |
| `extractSliceKey(url, metadata)` | required method | 3 | Kept — signature fixed even though both sources need only `url` |
| `acquire(...)` | required method | 1 | Kept — specified by OUTPUTS (media path, caption paths, metadata), never by yt-dlp invocation |
| `harvestLinks(metadata)` | required method | 9 | Kept — post-text links only (T10) |
| `acceptForEnqueue(url)` | required method | 13 | Kept — preflight hard-reject stays per-source |
| ~~`buildDownloaderArgs(...)`~~ | **declared attribute** | 1b | Extractor-args string is a class attribute on the YouTube adapter, read by the shared driver (granularity resolution below) |
| ~~`classifyCaption(captionPaths)`~~ | **declared attribute** | 2 | Adapter declares its caption class/trust (e.g. X: platform-ASR); the shared ladder consumes the declaration — T12 lifted the edit prohibition, and a declaration keeps source knowledge out of shared code without a callback. **Stage 2 collapses to shared; per-source stages 7 → 6** |
| ~~`classifyError(stderr)`~~ | **declared attribute** | 14 | Per-adapter error-pattern table consumed by the shared retry loop (T11) |
| hosts / claim keys | declared attribute | dispatch | Registry keys (T3) |
| `transcriptStrategy` default | declared attribute | 2/4 | Per-source default, pipeline-overridable (T5) |
| capabilities | declared attributes, **closed by default** | — | T9's SQLAlchemy posture: adapters declare what they HAVE; absence is a declaration, not a failure |
| content-claim capability | **reserved, unimplemented** | dispatch | D-C below |

Uniform 0..N result envelope (T6) with an open metadata namespace and a reserved source-specific
key prefix (envelope re-derivation below). Slug formatting stays shared; construction does no I/O
(cheap pure normalization permitted); declared arity is dead (T6 — arity is a property of the
result). Contract stability posture must be declared explicitly in the contract file itself
(yt-dlp's undeclared-API caution below).

### Structural finding — WITHDRAWN in its strong form; the weak form survives and is what matters

This thread briefly recorded *"model yt-dlp as one adapter among N rather than as the substrate"* on
the strength of gallery-dl's `ytdl` extractor. **The precedent is real but does not transfer.**

**The precedent, verified:** `gallery_dl/extractor/__init__.py:265-266` does list `"ytdl", "generic"`
as the final two modules, and `find()` is first-match-wins over module order. **But** `ytdl.py:21`'s
default pattern is `r"ytdl:(.*)"` — it requires an explicit `ytdl:` **prefix**, widening to a
catch-all only at `:154-156` when a user opts in via config. Out of the box, gallery-dl does **not**
let a delegating adapter compete for ordinary URLs.

**The transfer fails on ROLE, not registration.** In gallery-dl, `ytdl` is a **last-resort escape
hatch** for sites gallery-dl itself does not support — which is exactly why it sits near-last and is
off by default. In this lane, yt-dlp is the **primary acquisition mechanism for both sources**.
Opposite ends of the same dispatch order.

Taken literally the claim is therefore either **vacuous** — if yt-dlp is one adapter and both sources
acquire through it, there is exactly *one* acquisition adapter and the YouTube/X split lives inside
it, collapsing the per-source design this whole thread set is building — or **false**, since if
YouTube and X are two adapters both shelling out to yt-dlp, then yt-dlp *is* the substrate.

**What survives, and it is the part that does the work:** the contract must not assume adapters
perform their own HTTP, nor that acquisition is yt-dlp-shaped. **`acquire` stays a required method**;
it is simply specified by its **outputs** — media path, caption paths, metadata — rather than by
yt-dlp invocation. That is a *contract-level* rule, not a topology-level one, and it is
`course-digest`'s own stated principle: *"prescribes WHAT adapters produce, not HOW they produce
it"* (`adapter-contract.js:7`). It protects a future API-only or local-file source without any
topology claim.

**T4's method set does not change again.** Recorded at length so the topology claim is not
re-derived.

**yt-dlp's own modern answer, same team:** the 2025 `PoTokenProvider` framework (PR #12840, merged
2025-05-18) solves pluggable per-site behaviour by **inverting every axis of `InfoExtractor`** —
dataclasses over a 475-line docstring; `abc.ABC` + `@abstractmethod` over a plain class; request
validation over none; explicit `register_provider` over name-suffix discovery; typed errors over
generic; a **declared** public API over an undeclared one. Its PR text: *"Consider this an experiment
of a 'Extractor Provider' framework."* Prototyped **out-of-tree as a plugin first**, then adopted.
Every axis it inverted is one this contract is choosing right now.

**Supporting cautions, all documented:**

- **No API-stability statement exists** for yt-dlp's extractor plugin API (searched README,
  CONTRIBUTING, `plugins.py`, `common.py`, the wiki, the sample-plugins repo). **Declare this
  contract's stability posture explicitly.**
- **A prose contract has no referential integrity, not even to itself:** `CONTRIBUTING.md:288` sends
  authors to *"lines L119-L440"* of `common.py`; the docstring spans 106-580 and line 119 is blank —
  stale since 2023-09-23, unnoticed, **because nothing can notice**. Favour a machine-checkable
  contract.
- **Split conformance from liveness testing.** yt-dlp's per-extractor network `_TESTS` are **not run
  in CI** (`run_tests.py:39-62`; every workflow runs only `core`), a maintainer citing dead links.
  Conformance: offline, fixture-based, CI-gated. Liveness: scheduled, alerting, never on the merge
  path. → feeds **T9**.
- **URL matching alone is known-insufficient by the incumbent's own admission** — PR #4307 shrank
  `generic.py` 4,189 → 1,303 lines, motivated by *"matching using only URL has it's limitations…
  Sometimes additional network requests are needed."* It expressed embed-only extractors as
  **`_VALID_URL = False`** — a sentinel overload, which is what an untyped contract invites.

**D-C — reserve a content-claim capability now?** yt-dlp bolted one on in 2022 at the cost of that
dispatcher rewrite, then overloaded the URL-claim field to express it. **Recommended:** reserve it as
a **separately declared capability that no adapter implements today**, rather than building it now or
overloading the URL claim later.

### The result envelope — re-derived, and the original premise was backwards

The envelope recommendation was first hung on a streaming-vs-whole-object argument ("three of four
peer systems stream"). **That premise points the other way.** gallery-dl, Pygments, and Tika stream
because they transform bytes into tokens or events — streaming is inherent to *content processing*.
yt-dlp does not stream, because it emits **metadata about** media rather than the media itself.
**This pipeline is in yt-dlp's category**: it produces metadata plus file paths. So "three of four
stream" argues, if anything, that this envelope should look like the fourth.

The conclusions were right; only the derivation was wrong. Stronger support for both is already in
the same evidence set:

**1. The transcript travels as a replayable file path, not as a consumed stream.**
Tika's `ParserUtils.ensureStreamReReadable` buffers to disk *"to permit Parsers 2+ to read the same
data"*, and Tika 4 hard-codes `TikaInputStream` into the signature rather than documenting the
requirement in prose. That is a **multi-attempt dispatch** argument, and it is far stronger here than
any streaming claim: this pipeline reads the transcript repeatedly and out of order — claim
inventory, research agenda, vision alignment, synthesis — with the vision lane interleaving against
frame timestamps. A consumed stream would have to be re-acquired for each pass.

**2. The metadata namespace is open, with retired keys never reused.**
Pygments' `Token.Foo.Bar` parent-fallback, Tika's arbitrary `Metadata` keys, and gallery-dl's
underscore-prefixed extension keys with **retired message numbers never reused** all converge. This
matters concretely: X supplies fields YouTube does not (post text as `description`, repost and quote
counts) and lacks fields YouTube has (chapters, comment list, heatmap). A closed envelope would force
either a lossy common denominator or a schema change per source. An open namespace with a reserved
prefix for source-specific keys costs nothing and absorbs source three.

**Rating raised from moderate to strong** — the conclusions were under-supported only because they
were hung on the wrong premise, not because the evidence was thin.

### Three constraints to state explicitly

- **`extractSliceKey` takes `(url, metadata)`** even though YouTube and X both need only `url`.
  Widening a required signature later is a breaking change across every adapter.
- **Slug FORMATTING stays shared.** The adapter owns the key; `deriveVideoSlug` owns the format and
  has its own tests. Without this stated, an implementer moves the whole function.
- Routing YouTube through `extractVideoId(url)` too makes it URL-authoritative, closing a latent
  redirect divergence where yt-dlp's reported id could differ from the requested URL's.

**Granularity sub-question — RESOLVED, and the earlier recommendation was wrong about the mechanism.**

This thread previously recommended a fine-grained `buildDownloaderArgs` hook. **That is withdrawn.**
The local evidence identified a **real defect** and prescribed the **wrong fix** — a distinction
worth recording, because the evidence itself was sound and only the inference from it failed.

The defect stands exactly as measured: `build-yt-dlp-args.js:9` pushes
`YT_DLP_EXTRACTOR_ARGS = "youtube:max_comments=20,all,top;comment_sort=top"` **unconditionally** at
`:113-114` alongside `--write-comments`, and X has no comment list.

**The fix is a declared per-adapter attribute, not a callback.** The YouTube extractor-args string
becomes a **class attribute on the YouTube adapter**, read by the shared driver — not a method the
shared driver invokes back into the adapter. That keeps **one coarse seam**, avoids duplicating
stage 1c's retry/throttle/auth machinery, and still stops X inheriting YouTube's comment args.

A coarse per-adapter `acquire()` would duplicate stage 1c; a fine-grained hook would constrain every
adapter to a yt-dlp-shaped argument model. The attribute does neither.

But the prior art says most per-source variation should not be a **hook** at all. Three tiers,
observed across 920 gallery-dl adapters and 135 streamlink plugins, with **zero** machinery
duplicated:

1. **Attribute only** — Instagram's rate limit is `request_interval = (6.0, 12.0)`, read as the
   default for a user-overridable config key and enforced by the *shared* request loop. When
   exponential 429 backoff landed, all 920 adapters got it for free.
2. **One predicate inside the shared loop** — the base declares `_handle_429 = util.false`;
   `skeb.py:36-45` overrides only that predicate. **It is the only such override across 257
   modules.** This is the pattern to copy when a fine hook is genuinely warranted — narrow, single-
   purpose, inside machinery the adapter does not own.
3. **Auth as convention over base-provided credential resolution** — yt-dlp's `_NETRC_MACHINE` plus
   `_perform_login` over the base's netrc/TFA chain.

**Required-vs-provided is the ratio to aim at.** yt-dlp requires exactly **two** things —
`_VALID_URL` and `_real_extract` — and `_real_extract` is the *only* `NotImplementedError` in the
entire 4,176-line base (`common.py:830-832`). Roughly 200 other methods are free helpers.

**Rule adopted:** any required contribution whose absence fails **silently** is a contract defect.
streamlink's module-level `__plugin__` is the counter-example — a required contribution that fails
silently. gallery-dl's registry round-trip test is the general antidote.

**Anti-rule — the sharpest "do the opposite" in the corpus: DECLARE ARITY, never infer it.**
`_RETURN_TYPE` (`common.py:3822-3832`) scans `_TESTS` for keys beginning `playlist` to decide whether
an adapter yields a video or a playlist, and `is_single_video()` drives user-facing behaviour off that
inference. Deriving contract facts from test fixtures is the defect; declare arity explicitly.

**Site-specific arguments — right instinct, wrong execution, and now unfixable.**
`--extractor-args` / `_configuration_arg` (`common.py:4023-4034`) exists because per-site knobs were
metastasizing into the global option namespace. But it **always** returns a list of lowercased
strings, every call site hand-parses, there is **no key registry and no validation**, a typo is
silently ignored, and an adapter's accepted keys cannot be enumerated. It cannot be given validation
now because users depend on the silence. It was introduced by a direct-to-master commit with a
one-line message and no PR (`5d3a0e79`) — there is no design discussion to recover.

**Take streamlink's `@pluginargument` instead:** the CLI flag is derived from the module name, and
`type`, `type_kwargs` validation, `requires`, and `sensitive` are all **declared**. This bears
directly on **A2** — the published config namespace is the same decision one layer up.

**Construction does no I/O.** Three independent post-mortems: gallery-dl `8fdab9fb` (68 files,
because dispatch instantiates candidates just to test the match), gallery-dl `b4c59993` making it an
*executable invariant* after the maintainer broke it himself, and streamlink removing `Plugin.bind()`
in 5.0.0 (`gc.collect()` went 0 → 3,835 after the fix). A `matchUrl`/claim check must not construct
the adapter.

**Stated as "no I/O", not "no work" — the looser form contradicts a technique worth taking.**
streamlink `plugins/youtube.py:84-97` **canonicalizes `self.url` in `__init__`**, which is work in the
constructor and is explicitly recommended by the same research. The supported rule is that
construction performs no network or filesystem access; cheap pure normalization is fine and useful.

## T5 — transcript-source posture

**Status:** **directional** (under user delegation, 2026-08-15) — direction agreed; the remaining
detail carries research tags below.

**Direction:** the strategy seam from constraint 2 — a per-source-defaulted, pipeline-overridable
`transcriptStrategy` (`captions` | `asr` | `captions+repair`) — with these defaults:

- **YouTube: `captions`** — behaviour unchanged for every existing user.
- **X, caption present: `captions+repair`** — posture (v): proper-noun repair over the platform VTT,
  lexicon drawn from the post text (`description` carries the author-typed proper nouns) and
  harvested links. Near-zero dependency cost, aimed at the observed corruption.
- **X, caption absent: `asr`** — posture (ii): faster-whisper large-v3, `batch_size=8`. Mandatory,
  resting on **unpredictability, not frequency** — no predictor of caption presence exists, so the
  pipeline cannot know in advance; feasibility cleared on consumer hardware (2-hour video < 3 min).
- **Posture (iv) — ASR as substrate for every source — REJECTED** for this refactor: it lands a
  multi-GB model dependency on every existing YouTube user and is a separately-costed project, per
  constraint 3.
- ASR is an **optional capability**, declared closed by default (T9): absent the ASR toolchain, the
  X caption-absent path degrades explicitly (digest without transcript, stated in provenance),
  never silently.

**Research tags on the remaining detail** (probes already specified; run them during
implementation, cheap and empirical — each is a one-clip measurement, not a literature search):

- `[T5-ASR-ENTITY]` Does whisper-class ASR beat X's ASR on **technical proper nouns**? Evidence bar
  below stands: general WER is not an answer; "no evidence exists" is decision-grade. Governs
  whether `captions+repair` on the caption-present path is ever upgraded to posture (iii)
  (ASR-replace).
- `[T5-ASR-TIMESTAMPS]` Word-level timestamp quality of the ASR path — load-bearing, the pipeline
  aligns cues to frames. Probe: transcribe a known clip, compare cue boundaries against platform
  VTT.
- `[T5-ASR-LEXICON]` Does `initial_prompt` / vocabulary biasing close the proper-noun gap? Probe:
  one clip with and without a post-text lexicon. Governs whether the repair lexicon also feeds the
  ASR rung.

Originally "how does X flip `isAutoCaption` without editing managed `select-caption.js`"; T12
refuted the managed constraint and T4 resolved the mechanism as a declared caption-class attribute
consumed by the shared ladder.

The known defect: X's `.en.vtt` matches `MANUAL_EN_PATTERN` (`select-caption.js:23`) → `manual-en` →
`isAutoCaption: false` → X's own ASR is routed through `cleanManualCaptions`.

**The "`select-caption.js` is MANAGED, do not edit" constraint is REFUTED — see T12.** Direct edits
are permitted. The mechanism must be re-derived on separation-of-concerns merits: an adapter-supplied
classification keeps source knowledge out of shared code, while a source-aware rung in the shared
ladder is simpler but couples the ladder to a source. Weigh them; do not inherit the answer.

But X's ASR corrupts exactly the technical proper nouns downstream research and synthesis depend on
("Clawed code", "MySkills", "Npx", "220K stars"), and `cleanAutoCaptions` cannot un-corrupt them.
A per-source rung patch makes the *routing* correct while leaving the *transcript* bad — and the
defect propagates into the highest-value stage.

### The premise this thread was built on is WRONG — and it makes a fallback mandatory

Gate-passed X-extractor research, structural plus firsthand:

- **There is no date cutoff for X captions, in either direction.** A **2018** post carries `en` VTT;
  multiple 2024–2026 posts carry **none**. The handoff's open question ("does coverage hold before
  2024?") was the wrong question — caption presence is a property of X's own pipeline **per video**,
  invisible to yt-dlp, and no upgrade changes it.
- **In sampling, captions were absent more often than present** — n=12, 4 present / 8 absent.
  **Do not quote that as a rate.** The sample is biased *toward* presence: at least three of the four
  caption-positive posts are yt-dlp's own `_TESTS` fixtures, which are chosen precisely because they
  exercise extractor features including caption handling. The true absence rate is therefore likely
  **higher** than 8/12. The direction is safe; the number is not.
- **No predictor of caption presence exists.** Structurally there is no date, size, or version gate
  anywhere in the code path — an extractor-side cutoff would be visible in source — and empirically
  the `ext_tw_video` vs `amplify_video` hypothesis was **tested and falsified**, recorded as an
  unresolved absence rather than inferred away.
- yt-dlp's sole source is `_extract_m3u8_formats_and_subtitles` (`twitter.py:47`) — `.m3u8` variants
  only; the `.mp4` branch returns `([f], {})`. There is **no twitter-specific caption code**, and
  **`automatic_captions` is never populated** (so `--write-auto-subs` is inert — use `--write-subs`).
- Spaces and Broadcasts are **structurally** caption-free.

**Consequence: a transcript fallback is REQUIRED, not optional — and it rests on UNPREDICTABILITY,
not on frequency.** This is the stronger form and the one to cite: captions are sometimes absent, and
**nothing predicts when**. A pipeline that cannot know in advance whether a transcript will exist
must carry a fallback regardless of how often it fires. Framed that way the biased sample stops
mattering — the argument does not depend on the rate at all.

This thread was originally framed as "X's captions are bad, should we improve them". The real problem
is that **X frequently and unpredictably has no captions at all**, so posture (i) — platform captions
only — cannot deliver the watch parity the goal demands. Eliminated on evidence, before the ASR
research returns.

That collapses the choice to *which* fallback, and re-weights it: posture (v) (proper-noun repair
over an existing caption) **cannot stand alone**, because it presupposes a caption exists. It remains
valuable as a *quality* layer on the caption-present path, but something must cover caption-absent.

**Two further contract corrections from the same source:**

- **Subtitle keys are the raw, unnormalized `LANGUAGE` attribute** (`common.py:2307`), fallback
  `'und'` — observed `en`, `en-US`, `en-GB`. **Do not hardcode `subtitles['en']`.**
- **The `<X-word-ms>` sample recorded in the handoff is malformed.** Real tags have a **closing tag
  and wrap the word text**; `ms` is per-word **durations**, `character_ranges` are inclusive offsets
  into the wrapped text with arity always equal (48/48 real tags), and `index` is the **cue** index,
  not a word index. The handoff's sample has an arity mismatch that never occurs in real data.
  Materially: **yt-dlp does *not* strip these tags** (`webvtt.py`: *"The payload is not
  interpreted"*), so `--write-subs` puts raw tags on disk; `--convert-subs srt` yields clean text.
  Detect with a literal `<X-word-ms` test — no predictor of presence was found, and both the
  "auto-generated" and "recent track" hypotheses were falsified firsthand.

**Five postures under research:** (i) platform captions only · (ii) self-hosted ASR only when no
caption exists · (iii) ASR when the caption is known-weak platform ASR · (iv) ASR as the primary
path for every source · (v) **proper-noun repair over the caption you already have**, using
in-band metadata as a per-video domain lexicon.

Posture (v) was missing from the first framing and may be the strongest value-for-cost option:
yt-dlp's `description` for an X post is the **full post text**, which contains the correctly-spelled
proper nouns the ASR corrupted — because the author typed them. Harvested links carry more of the
same vocabulary. Near-zero dependency cost, aimed exactly at the observed failure mode.

### Three constraints on how this thread is allowed to resolve

1. **T5 must not block T4.** Whether the transcript comes from captions, ASR, or repaired captions,
   the adapter still needs `matchUrl`, `extractSliceKey`, argument building, error classification,
   and link harvest. Transcription changes *what sits behind* stages 2 and 4, not *whether* they are
   per-source. T5 stays off round 1's critical path.
2. **Model it as a strategy, not a fork.** A per-source-defaulted, shared-pipeline
   `transcriptStrategy` (`captions` | `asr` | `captions+repair`) keeps `classifyCaption` meaningful
   for caption-sourced adapters and makes ASR an alternative rung. Every posture above then leaves
   the T4 contract intact. Note `capability-matrix.md` stage 2 currently models two states
   (per-source classification, shared ladder); a strategy needs a third.
3. **The research must not conflate a fallback rung with a substrate replacement.** ASR as a rung
   for sources whose captions are known-bad is additive, cheap to accept, cheap to defer. ASR as the
   transcription substrate for *every* source — including YouTube's human-authored manual captions —
   is a strictly larger change that lands on every existing user and turns a
   yt-dlp/ffmpeg/ImageMagick prerequisite list into one carrying a multi-GB model download. Those
   are different projects and must be costed separately.

### FEASIBILITY — settled, and it clears comfortably

Partial ASR return (the topic was cut short by session wrap-up; treat as unverified by a second
context). **Measured on consumer hardware, not extrapolated from datacenter figures** — RTX 3070 Ti
8GB, faster-whisper v1.1.0, beam 5, CUDA 12.4:

| Config | 10-min video | 2-hour video |
|---|---|---|
| large-v3 fp16 unbatched | 48 s | 9 m 42 s |
| large-v3 int8 unbatched | 45 s | 9 m 05 s |
| large-v3 fp16 `batch_size=8` | 13 s | **2 m 37 s** |
| large-v3 int8 `batch_size=8` | 12 s | **2 m 28 s** |

One labelled substitution (large-v2 → large-v3 timing, justified by the model card: identical
architecture apart from 128 vs 80 mel bins and one new language token), **zero hardware
extrapolation** — the anchor machine is already consumer-class.

**Verdict: runtime is not a barrier.** A 2-hour video transcribes in under 10 minutes unbatched and
under 3 batched, on a mid-range consumer GPU. Feasibility was the gate on whether an ASR path is
viable at all; it clears.

**`large-v3-turbo` has no defensible point estimate** — three independent measurements of the
turbo÷large-v3 ratio spread **4.7×** (1.69× batched H200 short-form, 2.16× H200 long-form, 8× OpenAI's
own A100 reference). The disagreement is mechanistic rather than noise: turbo cuts decoder layers
32→4 and leaves the encoder identical, so its speedup depends entirely on the encoder/decoder time
split, which moves with batching and beam size. Best guide is the long-form ratio (~22 s / ~4 m 29 s),
range 1 m 13 s – 5 m 43 s at 120 min. **If a turbo number is ever needed, measure it on the target box
— a 60-second test beats any further research.**

Related caution surfaced in the same pass: **distil-large-v3.5's headline "~1.5× faster than
large-v3-turbo" is not reproduced by the leaderboard's own long-form run (1.05×).** Its main selling
point does not survive independent measurement.

**Still open when the session wrapped** — carry into the plan: entity-level proper-noun evidence
(priority 1), word-level timestamp quality (priority 3, and load-bearing since the pipeline aligns
cues to frames), and whether `initial_prompt` / vocabulary biasing closes the proper-noun gap
(priority 4, the mechanism that would let a per-video lexicon feed the ASR path).

**Evidence bar, stated so the research cannot satisfy it cheaply:** a general WER win is *not* an
answer. WER is dominated by common words; the failure that matters here is a low-frequency-token
failure. The ASR posture is supported only by entity-level or rare-word evidence that whisper-class
ASR beats X's ASR **on technical proper nouns specifically**. "No such evidence exists" is itself a
decision-grade result and rates the posture's support as weak.

## T6 — multi-media-posture

**Status:** **RESOLVED** (directional 2026-08-14; D-A closed under user delegation, 2026-08-15).
Return a uniform 0..N collection; arity is a property of the result, never of the adapter. All of
0/1/N expressible without an exception escaping. **D-A resolved: a post with no video produces a
text-only digest with populated provenance** — Tika's `EmptyParser` posture (well-formed empty
result, never null, never a throw), because it removes a special case from every downstream
consumer. Research returned and gate-passed; `playlist_count` is the discriminator and a zero-entry
playlist is a *downstream filtering artifact*, not an extractor state.

Multi-media X posts return `_type: playlist`; one observed sample had **zero** entries.

### REVERSED by research — `twitter.py` already solves 0/1/N for this exact source

The fail-closed recommendation was made without knowing what the extractor already does.
`twitter.py:1348-1390` handles the full arity range in **five branches**:

| Case | Behaviour |
|---|---|
| N videos wanted | `playlist_result(entries)`, titles suffixed `#1`, `#2`… |
| Exactly 1 | the **bare video dict** — arity collapsed |
| User pinned an index (`/status/…/video/2`) | that one video; **`_VALID_URL` carries `(?P<index>\d+)`**, so which-item-in-this-post is part of the URL claim |
| 0 videos, but an outbound link | `url_result(expanded_url)` — **delegates to another adapter** |
| 0 videos, no link | `raise_no_formats(..., expected=True)` then `return info` — a **metadata-only result**, not an exception, not `None` |

And `_yes_playlist()` (`common.py:4036-4051`) is the adapter **asking the pipeline's policy**
(`--no-playlist`), not deciding unilaterally. **The adapter shapes the result; the pipeline owns the
policy.**

**Take all five cases. Reject the collapse** — but the two halves of that recommendation are **not
co-equal**, and pressing the weaker one broke it.

**Load-bearing half — never collapse 1 to a bare object.** Return a uniform 0..N collection. Arity is
then carried **in the result**, so nothing needs declaring and no consumer branches. The collapse is
exactly why every yt-dlp consumer must branch on `_type`.

**Failed half — a per-adapter arity declaration.** `_RETURN_TYPE` (`common.py:3823-3832`) is a
`classproperty` computed from `_TESTS`: no playlist keys in any test → `'video'`; playlist keys in all
tests → `'playlist'`; otherwise → `'any'`. **Verified: `twitter.py` contains zero occurrences of
`_RETURN_TYPE`.** Carrying both single-video and playlist tests, it resolves to **`'any'`**, and
`is_single_video()` (`common.py:3838`) returns `None` for it.

**So for exactly our second source, per-adapter arity declaration degenerates to a value carrying no
information** — and not because the inference mechanism is weak. It is structural: **X's arity is a
property of the individual post, not of the adapter.** An adapter-level `returnType` field would
resolve to `'any'` for the X adapter on day one and buy nothing.

**Restated:** *return a uniform 0..N collection; arity is a property of the **result**, never of the
adapter.* The `_RETURN_TYPE` evidence now supports the *opposite* of the "declare it per adapter"
reading — it is a worked example of that declaration failing. A convenience accessor may collapse at
the call site; the contract must not.

**Revised recommendation:** do **not** fail closed. The zero-entry playlist that motivated the
fail-closed posture is a *representable state*, not an unsupported one — it is the "0 videos" branch,
which yt-dlp answers with a metadata-only result rather than an error. The design obligation is that
all of 0, 1, and N be expressible **without an exception escaping**.

The remaining product decision is D-A: what a post with no video should *produce* downstream — empty
digest, error, or text-only digest. **Recommended: text-only digest with populated provenance**,
matching Tika's `EmptyParser` posture (a well-formed empty result, never a null and never a throw),
because it removes a special case from every downstream consumer.

---

**Superseded — the v1 fail-closed framing, retained.**

**Recommendation: refuse, fail closed, for v1.** Three required details:

- The refusal must land **before acquisition burns a download** — `preflight-metadata.js` is the
  natural site (it is also stage 13, already per-source).
- Detection must **not** key on `entries.length` — the observed sample had 0 entries.
- The deferral carries a **trigger**, not just a tag: *revisit when a 2+ entry X playlist sample is
  obtained.* A tag without a trigger is a dropped item.

## T7 — spoke-topology

**Status:** **RESOLVED — (a) `reference/sources/<source>.md`** (under user delegation, 2026-08-15).
Deciding rationale: gains check-5 coverage, reuses `course-digest/reference/adapters/` idiom rather
than inventing a parallel one, no cross-plugin gate change. Binding terms: routing in the hub is an
**explicit conditional table** ("read `reference/sources/x.md` when the URL is an x.com/twitter.com
status") — it is both the documented progressive-disclosure mechanism and the only orphan detection
available, since check 15 is shallow. A `transcript <url>` run never loads the watch spoke; a
YouTube run never loads the X source file. Sizing driven by the `< 5,000 token` hub budget.

Provisional: a dedicated `sources/` directory (`sources/youtube.md`, `sources/x.md`).

**Corrected rationale.** The "is source a peer concern of `context/`" framing was wrong — `context/`
is *already* mixed-axis (`watch-pipeline`, `watch-queue`, `workflow` are pipeline-stage docs;
`gotchas`, `quality-gates` are cross-cutting). The real argument is **discoverability**: burying the
source set inside a seven-file `context/` makes the adapter set invisible from the tree.

**Requirement the thread was missing — CONFIRMED by research, and stronger than stated.** Moving
lines into spokes does not reduce context cost if the hub tells the agent to read them all.

Documented: *"At startup, only the metadata (`name` and `description`) from all Skills is pre-loaded.
Claude reads SKILL.md only when the Skill becomes relevant, and reads additional files only as
needed."* / *"No context penalty for large files: Reference files, data, or documentation don't
consume context tokens until actually read."*

**An unconditional "read all spokes" split is NET-NEGATIVE, not neutral** — the same tokens land in
context, *plus* N extra Read round-trips, *plus* documented partial-read risk: *"Claude may partially
read files when they're referenced from other referenced files… Claude might use commands like
`head -100` to preview content rather than reading entire files, resulting in incomplete
information."*

So the design must state that a `transcript <url>` run never loads the watch spoke, and a YouTube run
never loads the X source file. Routing must be explicit per the documented form — *"'Read
`references/api-errors.md` if the API returns a non-200 status code' is more useful than a generic
'see references/ for details.'"*

Two further documented constraints on spoke shape: **keep references one level deep from SKILL.md**,
and give any reference file over 100 lines a table of contents (`best-practices`; note
`skill-creator` says 300 — the two official sources diverge, so take the stricter 100).

**This also settles the file-level orphan gap noted above.** Since no gate detects an unreferenced
spoke in any layout, and since routing must be conditional and explicit anyway, an explicit
"read X when Y" routing table in the hub is doing double duty — it is both the documented
progressive-disclosure mechanism and the only orphan detection available.

### Pre-check result — it does not, and this changes the options

Ran the check. **`sources` is not a recognized skill-internal directory in either relevant gate:**

- `check-skill.sh:221` — `INTERNAL_DIRS='context|templates|scripts|reference|references|actions|evals|lanes|catalog|vendor'`. Check 5 (broken-internal-ref) matches refs **only** inside those dirs (`:234-235`), so `` `sources/x.md` `` would never be existence-checked. A dead link to a source spoke would pass silently.
- `check-skill.sh:346` — check 15 iterates `context reference references templates lanes actions`, so a `sources/` directory would never be flagged as an orphan spoke either.

Choosing `sources/` therefore **opts the new spokes out of both gates** — the opposite of what the split is meant to buy.

Revised options:

| Option | Tradeoff |
|--------|----------|
| **(a) `reference/sources/<source>.md`** | Gains **check 5** coverage: `INTERNAL_DIRS` includes `reference`, and the char class `[A-Za-z0-9._/-]+` includes `/`, so a nested `reference/sources/x.md` citation IS existence-checked. **Matches the repo's own established per-source spoke idiom**: `course-digest/reference/adapters/{dometrain,teachable,discovery-checklist}.md` is exactly this shape. Cost: two levels deep, against the one-level guidance — but the incumbent already does it, so this is reuse rather than a silent second way |
| **(b) top-level `sources/` + amend `skill-quality`** | Best name, one level. `plugins/skill-quality/scripts/check-skill.sh` **is in this repo**, so adding `sources` to both lists is ownable — but it is a cross-plugin change requiring a marketplace version bump and it changes a gate for every consumer of the plugin, for one skill's benefit |
| **(c) `context/source-<name>.md`** | Gate-covered, one level, zero cross-plugin change. Weakest discoverability; `context/` is already seven mixed-axis files |

**Revised recommendation: (a).** It buys check-5 coverage, one-level-deep is already not honored by the incumbent precedent, and it reuses an idiom this repo established rather than inventing a parallel one. (b) stays viable if the research says a top-level source axis is worth a gate change; (c) is the fallback if two levels is judged unacceptable.

**Do not over-claim what (a) buys.** It is *not* "gate-covered on both checks". Check 15 is shallow — `grep -q "$spoke_dir/"` (`:348`) only asserts the **top-level** directory is mentioned somewhere in `SKILL.md`, so the first `reference/` citation anywhere satisfies it for the entire subtree. A `reference/sources/x.md` that exists but is never cited is **not** caught, in this layout or any other. The coverage gained is check 5's cited-but-missing direction only; file-level orphan detection does not exist in either layout, so an explicit routing table in the hub is the only thing that will catch an unreferenced spoke.

The original `sources/` recommendation is recorded as overturned rather than deleted — it was chosen on naming aesthetics without checking what the gate actually recognizes.

## T9 — test-seam-posture

**Status:** **RESOLVED** (under user delegation, 2026-08-15; T4 now resolved) — a **shared
conformance suite** in SQLAlchemy's shape, layered over (not replacing) the colocated vitest seam:

- The suite is asserted **once against the contract, consumed per adapter** (SQLAlchemy's answer):
  each adapter owns a thin test file importing the shared suite with its own capability
  declaration, so escape hatches are visible and local.
- Capability declarations **skew closed** (79/112 precedent): a new adapter opts in to what it has
  and is never failed for what it lacks — X's missing comments/chapters/heatmap/`automatic_captions`
  are declarations, not failures.
- Conformance is **offline, fixture-based, CI-gated**; liveness (real network) is scheduled and
  never on the merge path (yt-dlp's `_TESTS`-not-in-CI lesson).
- **An X golden eval fixture IS added** — `skill-quality:check` has an eval-presence check, and the
  end-to-end X completion criterion needs a pinned fixture regardless.
- Rationale: all four live defects in this design (wrong caption boolean, timestamp fidelity, error
  misrouting, 0/1/N arity) are wrong-value/wrong-behaviour defects a type checker cannot catch —
  the table below.

### SQLAlchemy's dialect conformance suite — the canonical third option

Surfaced by a nested research agent, so **not gate-passed**; its load-bearing count was
independently re-verified here (`79` `exclusions.open()` vs `112` `exclusions.closed()` in
`lib/sqlalchemy/testing/requirements.py`, confirmed by direct fetch). Treat the rest as
well-cited-but-unverified.

This is the mature instance of the enforcement option T3 lists third — a **shared conformance suite**
rather than runtime duck-typing or types alone. Four transferable pieces:

1. **The suite is consumed by star-import into a file the adapter owns.** `test/test_suite.py` is
   literally `from sqlalchemy.testing.suite import *`. The shared suite is a dependency the adapter
   pulls in, not a harness the adapter is fed to. When one test does not apply, the adapter re-imports
   that class under an alias and overrides the single method — an escape hatch that is visible and
   local, not a config exclusion list.
2. **Capability declaration is a subclass with properties, pointed at by ONE key.** A dialect ships
   `Requirements(SuiteRequirements)` overriding only the properties it differs on, and names it via a
   single `requirement_cls` config key (or one `--requirements` flag). Each test opts in with
   `@testing.requires.<name>`, so a declared-closed capability deselects exactly the tests that need
   it **and nothing else**.
3. **Defaults skew CLOSED, and that is the load-bearing design choice** — 79 open vs 112 closed.
   Universal capability is open; anything a backend might plausibly lack is closed by default, **so a
   new dialect opts in rather than being failed for what it does not have**. This directly answers
   T4's open question about optional-method semantics and absent-method defaults: a new source adapter
   should declare what it *has*, and the contract should not fail it for what it lacks.
4. **Environment provisioning is a separate, optional module** (`provision.py`, discovered by
   package-relative import, absent in two of three real dialects checked). The *capability* seam and
   the *environment* seam are deliberately different files.

**Why this shape fits this lane exactly.** X genuinely lacks capabilities YouTube has — no comment
list, no chapters, no heatmap, no `automatic_captions`. Under a closed-by-default capability
declaration those are *declarations*, not failures, and the conformance suite deselects precisely the
cases that depend on them. The alternative — a contract that assumes YouTube's capability set and
treats absence as an error — is the shape currently causing the `YT_DLP_EXTRACTOR_ARGS` defect.

### What a conformance suite catches that a type checker cannot

The defect class is **wrong value** and **wrong runtime behaviour**, never wrong shape — every
example type-checks cleanly in its failure mode. Direct analogues in this lane:

| SQLAlchemy assertion | This lane's analogue |
|---|---|
| Booleans round-trip as `bool`, not `-1`/`0` or `'t'`/`'f'` | Caption rung classification: `isAutoCaption` is a correct `boolean` while carrying the **wrong value** for X — the exact live defect |
| `Decimal` in, `Decimal` out — silent float coercion loses digits | Timestamp fidelity through VTT parse into frame alignment |
| Driver errors map to the right exception class, and a non-ASCII message survives | **T11's error taxonomy** — X errors currently traverse a YouTube-shaped fallback while remaining well-typed |
| `rowcount` reports *matched* vs *changed* rows — `int == int` either way | Arity: 0/1/N from a multi-media post, which is **T6** |

All four of this design's live defects are in the class a conformance suite catches and a type
checker cannot. That is the argument for T9 taking this shape rather than relying on JSDoc plus
`checkJs`.

Both former sub-questions are answered in the status block above (once-against-contract consumed
per adapter; X golden fixture added). Existing seam retained: colocated vitest `*.test.js` per
module, plus `evals/` fixtures and `evals/check-*.js` outcome scripts.

## T10 — x-read-coupling

**Status:** **RESOLVED** (under user delegation, 2026-08-15) — agent-lane optional `/x:read`
invocation as recommended below; `harvestLinks` returns post-text links only. The unenforced-
invariant sub-decision resolves as **(ii) adapter-level URL canonicalization**: the X adapter's
claim/normalize step re-derives the canonical status URL itself, so the guarantee the capability
matrix asserts is made by code on every entry path, CLI included. Deciding rationale: the URL is
untrusted input selecting the adapter (T3's security posture), canonicalization is cheap pure
normalization explicitly permitted at construction (T4's streamlink precedent), and (i) would
document a hole rather than close it. The three operating conditions (cookie cases, silent 429
degradation detection, weeks-to-months auth-fallback windows) bind the adapter's design.

X's real reference links live in reply chains. `/x:read` step 2 (Thread Reader) reaches them.

**Recommendation:** agent-lane skill invocation, treated as optional — matching the hub's existing
posture toward `/discovery:research` ("reference implementation, not a hard dependency"). A hard
code dependency would make `knowledge` uninstallable without `x`. The adapter's `harvestLinks`
returns post-text links only.

**`/x:read` is text-only, and nothing in this repo acquires X MEDIA — verified.** Its frontmatter
grants exactly one tool: `allowed-tools: WebFetch(domain:threadreaderapp.com)`. A grep of the whole
`x` plugin for `yt-dlp`, `ffmpeg`, `video`, and `.mp4` returns zero matches.

**RESOLVED — the acquisition path exists and works anonymously.** Verified firsthand end-to-end, not
by metadata probe: a full download of a public status with **no cookies, no account, no extractor
args**, yielding a 1,762,361-byte MP4 (ffprobe-confirmed `h264`+`aac`, 111.28 s) plus an 8,385-byte
`.en.vtt`. The earlier constraint on T3/T4 — "do not design as though an acquisition path exists" —
is lifted.

**But three operating conditions come with it, and they belong in the design rather than being
discovered later:**

- **Cookies are required for exactly three cases**, all raised via `raise_login_required`:
  NSFW/age-restricted, protected accounts (the cookie account must also *follow* the author), and any
  `not authorized` API message. **Cookies are now the only auth route** — `-u`/`-p`/`--netrc` were
  deleted 2025-12-30 (PR #15432).
- **A 429 does NOT error.** Since 2023-12-24 the extractor warns *"Rate-limit exceeded; falling back
  to syndication endpoint"* and **silently degrades**, losing `*_count` metadata and **all but one
  video of a multi-video post**. No retry or backoff exists in the extractor. A silent partial result
  is far worse than a failure here, so the adapter must detect the degradation rather than trust the
  result.
- **Guest access has collapsed site-wide twice** (2023-06-30, 2025-03-10); both fixes were alternate
  APIs rather than cookies. Of the three `twitter:api` values, **`legacy` has 404'd since 2025-07-25**
  (#13837, open).

**Volatility, measured:** X is ~11× more stable than YouTube by commit count (581 vs 50 focused
commits; median inter-commit gap 26 d vs 3 d) — **but with a long tail**: longest gap 219 days, six
site-bugs open 28–848 days, and one issue took 289 days to "fix" by *deleting the capability*. Size
any auth-dependent fallback window in **weeks-to-months, not off the 3-day median.**

**Unenforced-invariant sub-decision (must resolve here).** `capability-matrix.md` asserts that any X
URL entering the pipeline has already passed the `x:read` gate's match-capture-rebuild. If the gate
is agent-lane and the CLI is directly invocable — `SKILL.md:48` enumerates eleven run-script entry
points — nothing enforces that on direct CLI invocation. Resolve one of two ways:

- **(i)** state that the invariant binds the **skill lane only**, and the CLI treats its URL as
  trusted input; or
- **(ii)** add adapter-level URL canonicalization that re-derives the canonical status URL.

As written the artifact asserts a guarantee no code makes.

## T12 — is `select-caption.js` actually a managed surface?

**Status:** **RESOLVED — NO. The inherited constraint does not hold.**

### The check that settles it

`standards/distribution/sync-manifest.yml` (`version: 2`) declares managed materializations as
`components: <name>: files: <source-path>: <target-path>`. It contains **37 components**:
`actionlint`, `agent-orientation`, `architecture-decisions`, `claude-permissions`,
`claude-review-caller`, `claude-security-review-caller`, `comment-hygiene-action`,
`comment-hygiene-tools`, `concurrency-policy`, `dependabot-policy`, `dotnet-analysis`,
`editorconfig-checker`, `gitleaks`, `go-analysis`, `lefthook-base`, `lefthook-dotnet`,
`lefthook-powershell`, `lefthook-python`, `lefthook-shellcheck`, `local-lane-guards`, `lychee`,
`markdownlint`, `markdownlint-home`, `node-runtime`, `path-detection-action`,
`path-detection-guardrails`, `path-detection-tools`, `pin-comment-convention`,
`pr-convention-policy`, `psscriptanalyzer`, `pyright`, `repository-text`, `review-instructions`,
`ruff`, `runner-policy`, `shellcheck`, `typos`.

Every one is repo-level tooling or policy. **Exactly one targets anything under `plugins/`:**

```yaml
components/path-detection/machine-path-patterns.sh: plugins/guardrails/lib/path-detection/machine-path-patterns.sh
```

`plugins/guardrails/`, not `plugins/knowledge/`. **Nothing in the knowledge plugin is a managed
materialization**, and `select-caption.js` is not one.

### What this changes — and what it does not

The prohibition is lifted: editing `select-caption.js` is not a managed-materialization edit and the
org convention does not forbid it.

**But "may edit" is not "should edit", and the design conclusion may not change.** The ladder is
**shared** code. Teaching it about X puts source-specific knowledge into a shared module — precisely
what the adapter seam exists to prevent. So an adapter-supplied classification may still be the right
answer.

The difference is that it is now a **design argument about separation of concerns**, which can be
weighed, rather than an **inherited prohibition**, which could not. Re-derive T5's mechanism on the
merits.

### Downstream consequence, conditional

If the re-derivation drops `classifyCaption` from T4's required set, **stage 2 may collapse to shared
entirely** — reducing the per-source stage count from seven to six and shrinking the adapter surface.
Do not fold that into `capability-matrix.md` until T5's mechanism is settled.

### Method note

This claim survived a handoff, a research session, and several adversarial passes because it was
*stated as a constraint rather than as a finding*. Constraints inherited across a session boundary
were the one category of concrete specific in this design that never got verified. They now do.

---

**Superseded record — the OPEN framing this thread carried before the check above.**

The handoff carried this as a hard constraint: *"`select-caption.js` is a MANAGED youtube-digest
surface — the X caption fix is X-local rung classification, never an edit there."* Two threads were
built on it (T5's whole framing, and T4's `classifyCaption` method existing to route *around* the
file).

**Searched for corroboration; found none** — see `inherited-decisions.md` for the four-way search
result. No sync-manifest entry, zero matches in the `standards` repo, no marker in the file, and the
only in-repo mentions are this design's own artifacts.

The burden has flipped. This is an unsupported claim, not an established fact, and it is currently
constraining the design toward a more complex solution than may be needed.

| If | Then |
|---|---|
| **Managed (constraint holds)** | The caption fix must be adapter-local. `classifyCaption` stays a required adapter method routing around the ladder. Current design is correct |
| **Not managed** | The ladder itself can take a source-aware rung or a trust signal directly — **materially simpler**, and `classifyCaption` may not need to exist at all |

**Resolve by** checking `melodic-software/standards` governance directly (its sync manifest, its
governance-process doc, and how it declares a managed materialization) rather than by inheriting the
assertion. Cheap to settle, and it changes the shape of T4 and T5.

**Method note for the whole design:** this claim survived a handoff, a research session, and several
adversarial passes because it was *stated as a constraint* rather than as a finding. Constraints
inherited across a session boundary need the same verification as any other concrete specific.

## T11 — error taxonomy

**Status:** **RESOLVED** (under user delegation, 2026-08-15) — four distinct error types from day
one (streamlink's shape, not yt-dlp's `expected=True` flag): dispatch-level unsupported-source
(outside the adapter error hierarchy, per `NoPluginError`), retryable source error, fatal source
error, and login-required. "Mine but empty" is a well-formed result, not an error (T6). Mechanism:
a **per-adapter declared pattern table** mapping stderr patterns to taxonomy classes, consumed by
the shared retry loop at its single yt-dlp classification site
(`spawn-yt-dlp-with-auth-fallback.js:54`) — the tier-1 "attribute, not callback" rule from T4;
`classifyError` as a required method is dropped. Cookie fallback gates on the login-required class
**only**. Silent 429 degradation (T10) classifies as retryable-degraded, never as success. Concrete
identifier names are PLAN-level detail. Research basis below.
X's failure taxonomy has **12 classes**, of which **only two are cookie-remediable**, both raised via
`raise_login_required`. **None of the three observed X errors is auth or bot-challenge.** So the
cookie fallback must be gated on `raise_login_required`-shaped errors only — routing the observed
three there would retry pointlessly *and* misclassify "no video here" as an auth failure. Combined
with the four-distinct-types recommendation from the prior-art lane, this thread's shape is settled;
only the concrete type names remain.

`acquire-yt-dlp-auth.js:8` `YOUTUBE_BOT_CHALLENGE_PATTERNS` (tested `:29`) gates the cookie-fallback
retry. None of X's three observed failures match, so X errors traverse a YouTube-shaped fallback
unclassified. Open: whether error classification becomes a required adapter method
(`classifyError`), a per-adapter pattern table consumed by shared retry logic, or a shared taxonomy
with per-source pattern registration.

### Research verdict — give the four states distinct TYPES from day one

This is the strongest convergence in the prior art, and the only place a maintainer has written down
a regret in-tree.

**streamlink expresses four states with four distinct types:**

| State | Expression |
|---|---|
| "not mine" | **no exception at all** — the adapter is never constructed; the router raises `NoPluginError`, which deliberately does **not** inherit from `PluginError` (#5088: *"it's something entirely different"*) |
| "mine, but empty" | empty result or `NoStreamsError` |
| "mine, source broke" | `PluginError` — logged and **retried** |
| "mine, stop retrying" | `FatalPluginError` — re-raised past the retry loop (`main.py:519-541`, verified honored) |

**yt-dlp does the same job worse, and knows it.** `expected=True` is a **boolean flag on one exception
type** carrying the entire "normal condition, not a bug" signal. And in streamlink's tree today,
`src/streamlink/exceptions.py:7` carries the regret verbatim:

```
# TODO: don't use PluginError for failed HTTP requests or validation schema failures
```

**Recommendation:** four distinct types from the start, not a flag on one. This maps directly onto the
local defect — X's three observed failures currently traverse a YouTube-shaped bot-challenge path
because the *only* classification available is that pattern list.

**Validate remote payloads at the boundary.** 122 of 135 streamlink plugins validate against a
declarative schema, with `validate.any(success_shape, error_shape)` encoding *"the source said no"*
**inside** the schema. Because `ValidationError` is a `ValueError` and the caller catches it, schema
failure lands in the taxonomy automatically rather than needing its own branch.

**Spawn topology — checked, because the verdict above depends on it being exclusive.** Two spawn call
sites exist in `acquisition/`: `acquire-with-retry.js:40` `spawn(command, args, spawnOptions)`, which
is **generic** — it wraps whatever command it is handed — and
`spawn-yt-dlp-with-auth-fallback.js:54`, which hardcodes `"yt-dlp"` and is where the bot-challenge
patterns gate the retry. So the claim is not that only one `spawn(` literal exists, but that the
yt-dlp-specific classification lives at exactly one site. That holds, and it is the site an adapter
would have to influence.
