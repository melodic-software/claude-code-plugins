---
name: ai-briefing
description: "Aggregate AI industry news via multi-wave collection (Twitter/X, Perplexity, RSS, GitHub releases) across 13 provider buckets. Use when: 'ai briefing', 'ai news', 'what's new in AI', 'catch me up on AI', 'prep for AI meeting', 'AI roundup', 'generate AI slides'. Actions: (default) collect + dedup + rank to markdown/PPTX/HTML; 'retro --meeting N' score items as acted/noted/skipped post-meeting; 'search' full-text across archived briefings; 'drift' surface silent Twitter handles."
argument-hint: "[--since <1d|3d|7d|14d|30d>] [--providers <list>] [--extras] [--format markdown|slides|html] [--chrome] [--reset] [--status] [retro|search|drift] [...args]"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Purpose

This skill automates the full pipeline of AI news intelligence: discover → collect → deduplicate → categorize → present. It replaces a manual workflow of scrolling Twitter/X, saving URLs to Notepad, and walking through a list over hand-built slides.

The skill is general-purpose — useful anytime for staying current on AI developments. It naturally serves meeting prep when invoked with `--since 14d`, but it's equally valuable for daily check-ins (`--since 1d`) or deep dives into a single provider (`--providers anthropic`).

**What this skill is NOT:** a Twitter API client (no Twitter API keys), a replacement for `/research` (that validates technical claims; this monitors news sources), or a content creator (it curates existing content with source URLs, never fabricates).

**Grok Build is optional.** Wave 0 X preload (`--grok-preload`) enriches briefing when the `grok` CLI is installed and signed in; without it, Chrome Wave 1 alone is the full path. Probe: `node scripts/per-profile-runner.js grok-check`.

## Arguments

Parse `$ARGUMENTS` for these flags:

| Flag | Default | Effect |
|------|---------|--------|
| `--since <timeframe>` | Since `last_meeting_date` (or 14d if no last meeting) | Time window: `1d`, `3d`, `7d`, `14d`, `30d`, or explicit ISO date `2026-04-15` |
| `--meeting-prep` | Off | Marks this run as the pre-meeting briefing. **Closes current meeting window** on completion: archives output to `output/meetings/archive/meeting-{N}.md`, sets `last_meeting_date` to today, increments `meeting_n`, opens new window for next cycle. |
| `--close-meeting` | Off | Synonym for `--meeting-prep` semantics — close current window without producing fresh briefing. |
| `--window-status` | Off | Show current meeting window state. No execution. |
| `--providers <list>` | All providers | Comma-separated filter: `anthropic`, `openai`, `google`, `cursor`, `other` |
| `--extras` | On | Include EXTRAS section (robots, games, science+AI, novel applications). Pass `--no-extras` to disable. |
| `--format <type>` | `markdown` | Output format: `markdown` (default), `slides` (PPTX — only on explicit request), `html` (web slides). Slides are NEVER auto-generated; user must opt in. |
| `--chrome` | Auto-detect | Force chrome-based Twitter scanning (requires claude-in-chrome) |
| `--add-only` | Off | No-op (legacy). Every run within an open window automatically merges. |
| `--retry-blocked` | Off | Re-attempt profiles flagged as blocked in last run's `runs[-1].profiles_blocked` |
| `--thorough-date-scan` | On | Use posts force-scroll extractor to cover full date window per profile. Pass `--no-thorough` to disable. |
| `--skip-low-signal` | Off | Drop `low_signal_skip_default` profiles (corp/news/personal) from scope. Default scope INCLUDES every bucket. |
| `--scope <name>` | (adaptive) | Explicit scope override: `all` / `all-non-skip` / `high` / `test`. When unset, adaptive logic picks per standing default #19. |
| `--refresh-following` | Off | Re-scrape `x.com/{user}/following` and update `following-list.json` before scanning. |
| `--grok-preload` | Off | Wave 0: optional Grok X preload before Chrome S1. If CLI missing or not signed in, run continues with Chrome only (see `grok_degraded` on `init`). |
| `--grok-model=<slug>` | default | Optional Grok model for Wave 0 (`init` stores in run config). |
| `--require-grok` | Off | Fail `init` when `--grok-preload` requested but Grok is not ready (default: degrade silently). |
| `--meeting-n <N>` | Auto-increment from `seen-items.json` | Override meeting number for `--format slides` title slide. |
| `--yes` / `-y` | Off | Skip pre-execution confirmation gate. Required for autonomous runs. |
| `--reset` | — | Clear `seen-items.json` and start fresh (preserves `meeting_n`) |
| `--status` | — | Show last run stats, item counts, last_following_refresh age, current meeting_n |

## Action menu

| Action | When | What it does |
|---|---|---|
| (default) | Meeting prep / mid-window run | Multi-wave collection → categorize → emit briefing markdown / slides / HTML / PDF |
| `retro --meeting <N>` | Within ~24h after meeting #N | Interactive capture — prompts user `acted/noted/skipped` per item, updates `audience_signal` in `seen-items.json`, writes `output/retro-{N}.md`, surfaces patterns |
| `search "<query>"` | Anytime | Full-text search across `output/meetings/archive/meeting-*.md` files. Returns match list with meeting #, item title, audience signal, cross-meeting recurrence count |
| `drift` | Weekly cron (or on-demand) | Reads `seen-items.json` `current_meeting_window.runs[]` per-profile capture counts. Surfaces profiles silent ≥2 consecutive runs. Suggests demotion candidates |

### `/ai-briefing:ai-briefing retro --meeting N`

Interactive flow:

1. Read `output/meetings/archive/meeting-{N}.md` — extract every bullet (provider, headline, body, urls)
2. For each bullet, prompt user via `AskUserQuestion`:
   - `acted` — user/team installed, configured, used the thing this week
   - `noted` — user remembers it, may revisit later
   - `skipped` — user has no recall or no relevance
3. Update `seen-items.json` per item: set `audience_signal`, increment `meetings_mentioned`, append to `update_history` if new state vs prior meetings
4. Write `output/retro-{N}.md`: per-item annotation table, pattern summary, follow-list demote/promote recommendations
5. Apply approved recommendations (user confirms before write)

Auto-mode: skip per-item prompts, infer from heuristics (high tier + multi-source = `noted`, low tier single-source = `skipped`); flag for human review.

### `/ai-briefing:ai-briefing search "<query>"`

Grep across `output/meetings/archive/meeting-*.md` + cross-reference with `seen-items.json` `audience_signal` + `meetings_mentioned`. Returns match list grouped by meeting with provider/tier/signal/recurrence count.

### `/ai-briefing:ai-briefing drift`

```bash
/ai-briefing:ai-briefing drift                  # report
/ai-briefing:ai-briefing drift --auto-demote    # apply demotions to context/following-list.json
```

Reports profiles silent ≥2 consecutive runs (warning) or 4+ (strong demotion signal), bucket coverage trends, recommended actions (drop deleted accounts, demote quiet handles, investigate sudden drops).

## Recurring schedule (2-week cadence)

User runs `/ai-briefing:ai-briefing --meeting-prep` every 2 weeks ahead of the AI meeting. Set up via `/schedule create "ai-briefing-meeting-prep" --cron "0 8 * * 1/14" --command "/ai-briefing:ai-briefing --meeting-prep"` or `/loop 14d /ai-briefing:ai-briefing --meeting-prep`. The default `--since` calculation handles bi-weekly cadence: window = `now - last_meeting_date`.

## Audience context (ranking lens + apolitical filter + impact tag)

The engine's default audience is a **software engineering team** thinking about pragmatic use of AI in everyday development — NOT pure research breakthroughs or speculative AGI debates. The S4 categorize step weights HIGH/MED/LOW by this lens. Both lenses below ship as **documented, overridable engine defaults**; a consumer profile refines or replaces them (see "Profiles" below).

- **Pragmatic-use ranking lens** (default) — bias HIGH for things an engineer can use next week (Claude Code / Cursor / Copilot releases), items that change cost/access economics, and industry-wide legal/regulatory shifts; bias LOW for research speculation and viral vibe.
- **Apolitical filter** (default) — drop partisan-only content (politician deepfakes, campaign-AI memes, partisan policy threads); KEEP true industry-wide controversy that affects AI access/cost/regulation even when a politician is named (e.g. supply-chain disputes, landmark AI-governance trials, state-AG suits).
- **Impact tag** (profile-provided, optional) — when the active profile supplies a tech-stack lens, Step 4.5 enrichment annotates HIGH items with `impact: high|medium|low|none + reason` against that stack. With no profile stack lens, the impact tag is omitted.

See [`references/audience-defaults.md`](references/audience-defaults.md) for the full default ranking lens, worked apolitical-filter examples, and how a profile supplies an impact-tag stack lens.

## Profiles (audience / deployment variants)

The engine resolves a **named profile** — a per-audience config folder in the consumer project — for its curated inputs and branding. Files at `.claude/ai-briefing/` are the **default profile**; each `.claude/ai-briefing/<name>/` subfolder is a **named profile** overlaying the default per key. Active profile per the convention-resolution ladder: exactly one profile present → use it; several → the `active_profile` `userConfig` scalar or a `--profile <name>` argument; none → the bundled neutral seed (an unprofiled, generic run). Select the runtime profile by exporting `AI_BRIEFING_PROFILE=<name>` for the runner/build scripts.

A profile carries: the curated `following-list.json`, an optional `brand.js` overlay (org name, tagline, logos, theme), and an optional tech-stack impact lens. Run `/ai-briefing:setup` to scaffold one interactively.

## Standing defaults (DO NOT ASK)

Session-level standing rules — applied automatically without prompting. Override only via explicit contrary flag.

1. **Add-only = MERGE, not APPEND** — if `last_run` is within the requested `--since` window, treat as continuation. **Merge new items into the existing provider buckets** under the same HIGH/MED/LOW headings. **NEVER tack on a "## Run N" or "## Supplement" delta section**. The briefing is a single consolidated document — every run rewrites the body so the reader sees one organized view. Update `seen-items.json` incrementally; output file is rebuilt clean each run from the merged item set. Run history lives in `seen-items.json` `current_meeting_window.runs[]` + `context/runs/`, NOT in the markdown body.
2. **Thorough date-scan by default** — use posts force-scroll extractor (see `references/chrome-extraction.md`).
3. **EXTRAS on by default** — robots, science breakthroughs, novel applications. User finds these consistently valuable.
4. **Retry blocked profiles automatically** — same-session screenshot fallback for `[BLOCKED: Cookie/query string data]` filter hits.
5. **Per-stage state writes** — runner writes per-profile JSON after every stage (S1 → S6). Survives mid-run interruption. See `references/per-profile-loop.md`.
6. **Default scope = ALL buckets** — first run in any open meeting window scrapes every handle in `following-list.json` `scan_priority`. Opt-out via `--skip-low-signal` flag OR explicit `--scope=high|all-non-skip|test`.
7. **Cap leadership/low-volume accounts at 1 scroll** — DarioAmodei, JeffDean, ch402 etc. post <5x/week. Full deep-scroll wastes time.
8. **2-profile cap per `browser_batch`** — stability: 3+ profile batches occasionally trigger MCP timeout.
9. **Live following diff every 4-6 weeks** — first run of any session, check `last_following_refresh` timestamp in `following-list.json`; if >42 days old, auto-trigger `--refresh-following`.
10. **5-surface coverage default** (per `chrome-extraction.md`): Profile Posts + Profile with_replies (mandatory for `high_signal_required`) + Home Following (DOM-click + ⋯→Most Recent override) + Home For you (supplementary) + Twitter Advanced Search (>7d windows on high-volume handles). Run selector-presence probe at session start before bulk extraction.
11. **12-bucket coverage MANDATORY** — every run must produce a (possibly empty) section for each: **Anthropic / OpenAI / Google / Cursor / xAI-Grok / Meta-Llama / DeepSeek / Microsoft / Compute & Infrastructure / Real-world AI / Legal & regulatory / Other / EXTRAS (Robotics)**. Empty bucket = note "no notable items this window" — never silently drop.
12. **Web-research depth = Twitter depth — for ALL 13 buckets, not just legal.** Each bucket gets at minimum 1 Perplexity query + 1 WebSearch per run, even buckets with handle lists. Compute / Real-world / Legal get web-research-FIRST treatment (Twitter follows). See `references/providers.md` per-bucket query templates.
13. **Apolitical filter applied at categorize step** — drop partisan-only items BEFORE ranking. Industry-controversy items keep even when politicians named.
14. **In-tree build pipeline is canonical for `--format slides|html`** — `output/build/*.js` (Node ESM, pptxgenjs + playwright direct). The fallback plugins (`/document-skills:pptx`, `/frontend-design:frontend-design`, `/ui-ux-pro-max:slides`) are documented escape hatches only — see `references/slide-generation.md` "Fallback skill paths". Pipeline detail in `references/build-pipeline.md`.
15. **AI-in-loop is mandatory — scripts handle mechanical, AI handles judgment.** Pipeline is `node run.js` for efficiency, NOT autonomy. Mandatory overseer checkpoints: (a) review emitted `slides-data.js` before build, (b) curate Patterns synthesis, (c) review `build/shots/slide-NN.png` screenshots + `audit.json` warnings before ship. See `references/build-pipeline.md` "AI-in-loop checkpoints".
16. **Tooling-first surfacing — HIGH bucket leads with product/IDE/CLI/SDK/plugin updates** ahead of model + research news. Per-provider HIGH-tier priority order: see `references/providers.md` "Per-provider HIGH/MED priority table". **Rule of thumb:** if the engineering team can't try it / install it / call it / configure it within a week, it's not HIGH — even if it's strategically interesting. Move to MED with a one-line context.
17. **Vendor coverage minimum** — every run must check tooling-news for **at minimum**: Anthropic (Claude Code, Claude.ai, Cowork, Claude Desktop), OpenAI (Codex CLI, Codex desktop app, Agents SDK, ChatGPT app), Cursor (IDE + Cloud Agents + SDK), **Augment Code** (Auggie CLI + Remote Agent), **Microsoft** (M365 Copilot + Copilot Studio + Visual Studio 2026 + VS Code + GitHub Copilot), Google (Gemini API + AI Studio + Workspace), xAI (Grok + Grok Voice), Meta (Llama + Meta AI), DeepSeek (V/R series + TUI). Plus framework tier: LangChain/LangGraph, Vercel AI SDK, Bun, Firecrawl. Don't silently drop a vendor — note "no notable items this window" if true.
18. **Per-profile loop discipline (Wave 1 canonical — main-session-orchestrated, Option A)** — Wave 1 is orchestrated by the main interactive CC session via the runner's stage CLI. Each profile completes ALL 6 stages (S1 Capture → S2 Validate → S3 Synthesize → S4 Categorize → S5 Persist → S6 Check off) in order before advancing. State persisted after every stage. Anti-bot pause at 90 navs/session — main session stops, user re-triggers. **Why main session, not autonomous runner:** chrome-in-chrome MCP only loads in the active interactive session's WebSocket; `claude -p` subprocesses do NOT inherit plugin MCP. S3 + S4 spawn `claude -p` inside the runner. Default scope = `all`; override via `init --scope=all-non-skip|high|test`. See `references/per-profile-loop.md` (Execution protocol + Wave 1 orchestration loop sections) and `references/runner-architecture.md` (10-subcommand surface).
19. **Adaptive scope across runs in same meeting window** — when `--scope` is unset, runner picks scope from prior-run velocity stored in `current_meeting_window.runs[]`:

    | Run state | Auto-picked scope | Why |
    |---|---|---|
    | First run in window (runs[] empty) | `all` | Cold-start — establish full baseline |
    | Run N+1 where prior run added ≥3 LOW items | `all` | LOW bucket still productive — keep scanning |
    | Run N+1 where prior run added <3 LOW items AND prior-prior run added <3 LOW items | `all-non-skip` | Two consecutive empty-LOW runs — bucket gone quiet |
    | Run N+1 where prior run added 0 MED items AND HIGH delta < 2 | `high` | Tail of window, only watch core vendors |
    | After `--meeting-prep` closes window | `all` | Reset on next window |

    Explicit `--scope=X` always wins. Adaptive logic NEVER drops HIGH or LEADERSHIP — those scan every run. `--refresh-following` forces `all`.

20. **Grok Wave 0 is optional** — Chrome Wave 1 is the full, canonical path; never block briefing on Grok. `init --grok-preload` probes the Grok CLI and degrades on a missing/unsigned CLI (`grok_degraded` in init stdout; `config.grok_preload: false`) rather than failing — pass `--require-grok` only when a caller genuinely needs Grok to hard-fail on an unready CLI. When `config.grok_preload` is true, run `grok-capture --index=N` as S0 before Chrome S1; it records `S0_grok_capture: skipped` (returning `{skipped: true}`) whenever preload is disabled or a capture errors, so Chrome Wave 1 always proceeds. Captured X posts merge into S3 synthesize (Chrome URLs win on dedup). Grok install: <https://x.ai/cli>.

21. **Follow-list diff against UNION of accounts.\* + scan_priority.\***, never single structure. `following-list.json` carries parallel groupings — `accounts.*` (16 semantic buckets) and `scan_priority.*` (4 priority buckets); a handle can live in one but not the other. Single-structure diff produces false-positive `added` entries for already-tracked handles. New writes go to BOTH structures in lockstep. Full pitfall catalog (parallel-structure bug, CDP timeout patterns, brand vs personal handle disambiguation, profile drift, bucket assignment by verification not guess) lives in `references/chrome-extraction.md` "Following-list diff pitfalls (learned 2026-05-21)" — cite by H2 heading, do not restate inline.

22. **`--refresh-following` also audits existing low-signal + uncategorized buckets for role drift.** Engineers move companies; a handle classified as `uncategorized_creators/low` 3 months ago may now be Claude Code @ Anthropic. Every refresh should re-verify any handle in `uncategorized_creators` and `low_signal_skip_default` against a current bio probe — specifically check for new affiliations with: Anthropic, OpenAI, Cursor, Google DeepMind, xAI, Windsurf, Cognition. Promote to the matching `accounts.*` vendor bucket + `scan_priority.medium_signal` (or `high_signal_required` for IC engineers at HIGH-tier vendors). Cadence: every `--refresh-following` invocation (so 4-6 weeks). See `references/chrome-extraction.md` "Pitfall 4 — Profile drift".

## Data Files

Two homes, resolved per profile. **Machine-local state** (never tracked) lives under `${CLAUDE_PLUGIN_DATA}/<profile>/` — seen-items, per-run artifacts, generated decks; running in-repo it falls back to the skill tree. **Tracked config** (the curated `following-list.json`, brand overlay) lives in the consumer profile at `.claude/ai-briefing/[<profile>/]`, falling back to the bundled `seed/following-list.json`. Paths in the table below are relative to their home.

| File | Purpose |
|------|---------|
| `context/seen-items.json` *(state)* | Dedup registry — every captured item across all runs. Includes `current_meeting_window.runs[]` audit trail. |
| `following-list.json` *(config: profile → `seed/`)* | Categorized X/Twitter handles in `scan_priority` buckets — the single SSOT for Wave 1 scanning. Refresh via `--refresh-following` every 4-6 weeks. Optional override maps `scroll_iterations` and `credibility_score` per handle. |
| `context/runs/<run-id>-checklist.json` | Per-run coverage checklist. Created Step 0.5, frozen Step 7. Archived; not loaded between runs. |
| `context/runs/<run-id>-chrome.json` | Per-run chrome scan manifest. |
| `references/providers.md` | Provider categories, account handles, query templates, changelog URLs, per-provider HIGH/MED priority table |
| `references/chrome-extraction.md` | Chrome-based Twitter extraction workflow |
| `references/checklist-system.md` | Run checklist verification |
| `references/slide-generation.md` | Slide structure, default brand spec (tokens in `output/build/brand.js`), provider logo registry, fallback skill paths |
| `references/audience-defaults.md` | Default audience framing, pragmatic-use ranking lens, apolitical filter, profile-provided impact-tag schema |
| `references/build-pipeline.md` | In-tree `output/build/*.js` Node ESM pipeline — slides-data.js schema, build commands, validate gates, Step 5 detailed flows |
| `references/per-profile-loop.md` | Per-profile S1-S6 state machine + Wave 1 orchestration loop |
| `references/runner-architecture.md` | 10-subcommand runner surface |
| `references/pre-execution-gate.md` | Step 0.7 confirmation panel detail |
| `references/enrichment-passes.md` | Step 4.5 enrichment pass details |
| `references/resume-detect.md` | Step 0.4 AskUserQuestion option detail |
| `references/window-state.md` | Meeting window schema + lifecycle detail |
| `output/build/` | **Build pipeline** — Node ESM scripts, brand assets, generated `slides-data.js`, validation screenshots. Not meeting content. |
| `output/meetings/meeting-{N}.md` | **Single consolidated briefing for the open meeting window.** Rebuilt clean each run via merge. |
| `output/meetings/latest.md` | Mirror of the active `meeting-{N}.md`. |
| `output/meetings/archive/` | Closed meeting briefings moved here on `--meeting-prep` / `--close-meeting`. |
| `output/meetings/ai-meeting-{N}.{html,pdf,pptx}` | Deck deliverables emitted by `output/build/` pipeline. |

**Files that MUST NOT exist:** `seen-items.backup.json`, `seen-urls-set.json`, `rolling.md`. Backups belong in git history; URL dedup index is derivable from `seen-items.json` on demand; rolling.md is superseded by meeting-window pattern.

### Per-handle overrides (following-list.json)

Optional sibling maps to `scan_priority` buckets — keyed by handle (with leading `@`):

| Map | Default | Purpose |
|---|---|---|
| `scroll_iterations` | 12 (per `chrome-extraction.md`) | Per-handle override of posts force-scroll iteration cap. High-volume → 18 (sama, gdb, AnthropicAI). Leadership-low-volume → 1 (DarioAmodei, JeffDean). Auto-tunable from `oldest_captured` vs cutoff trend across last 3 runs. |
| `credibility_score` | 5 | 0-10 source weight. Vendor-official + leadership: 9-10. Verified eng/PM: 7-8. Practitioner with track record: 5-6. Random commentary: 1-3. S3 synthesis weights candidates by source credibility. HIGH tier requires ≥1 source with credibility ≥7. |

Both maps are optional — missing keys fall through to defaults. Updated by hand or by `/ai-briefing:ai-briefing retro` when audience signal patterns emerge.

## Execution Flow

The full Step 0-8 runbook — argument parse + state load, resume detect (0.4), checklist build (0.5), window state (0.5b), window-status short-circuit (0.6), pre-execution confirmation gate (0.7), following refresh (0a), source registry (1), multi-wave collection Waves 1-4 (2), dedup (3), categorize + rank (4), enrichment passes (4.5), output generation markdown/slides/HTML/PDF (5), checklist verify gate (6.5), state update (7), pre/post-meeting loop (8) — plus Quality Rules and Error Handling lives in **`context/execution-flow.md`**. Read it before executing a briefing run; the Standing defaults (DO NOT ASK) above apply throughout.
