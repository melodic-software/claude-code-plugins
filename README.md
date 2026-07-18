# Melodic Software — Claude Code plugins

A private [Claude Code](https://code.claude.com/docs) plugin marketplace of reusable, repo-agnostic
skills, hooks, and agents. Each plugin is designed to work in any repository and to be customized by
consumers without editing the plugin itself.

> The catalog below is generated from the plugin manifests and kept in sync by CI. New plugins clear
> the per-plugin migration gate in [`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md).

## Use this marketplace

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install <plugin-name>@melodic-software
```

Browse and manage with `/plugin`. To refresh after updates: `/plugin marketplace update melodic-software`.

### Enable plugin suggestions for an organization

Some catalog entries declare `relevance` signals so Claude Code can suggest the plugin when a
session's work matches (matching runs locally; nothing is reported anywhere). Suggestions are
opt-in per marketplace: they surface only after an administrator allowlists the marketplace in
[managed settings](https://code.claude.com/docs/en/settings#settings-files) — declare the
marketplace source AND allowlist its name in the same file:

```json
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": {
        "source": "github",
        "repo": "melodic-software/claude-code-plugins"
      }
    }
  },
  "pluginSuggestionMarketplaces": ["melodic-software"]
}
```

The source declaration is required for any non-official marketplace: the allowlisted name is
ignored if the locally registered marketplace came from a different source, which stops an
unrelated catalog from registering under an allowlisted name to get its plugins suggested.
Reference: [Recommend plugins for your org](https://code.claude.com/docs/en/plugin-relevance).

A few personal or external-service plugins install disabled (`defaultEnabled: false`) until the
user opts in with `/plugin enable`; an existing install is never flipped by catalog changes.

## Catalog

<!-- catalog:start -->

### Discovery

- [`knowledge`](plugins/knowledge) — Ingest external knowledge into durable, synthesized artifacts. Ships a book-distillation pipeline (PDF/EPUB into concept-organized, author-attributed skill reference files), a YouTube pipeline (watch, transcript, link harvest, and repo-applicability synthesis), and a course-digest pipeline (extract and synthesize online video courses — Dometrain, Teachable — into repo-applicable recommendations), plus a re-runnable setup action; a configurable library directory governs where synthesized artifacts land in the consuming repo.
- [`context7`](plugins/context7) — Looks up current library documentation, API references, and code examples via Context7 (ctx7 CLI or the Context7 MCP server) with a two-step resolve-then-query workflow: a lookup skill (default lookup plus an upstream drift-check action) and a setup skill for CLI install, auth, and MCP configuration.
- [`firecrawl`](plugins/firecrawl) — Web scraping, search, crawling, and file parsing through the firecrawl-cli binary with a write-to-disk-then-Read pattern that keeps large results out of context — plus a gated maintainer update flow tracking the upstream CLI and skill source.
- [`discovery`](plugins/discovery) — Structured discovery before changes: explore the local codebase (inline or in an isolated forked subagent) and run disciplined multi-source external research with source tiers, falsification, and recency gates — persisting EXPLORE.md / RESEARCH.md handoff artifacts.

### Design

- [`architecture`](plugins/architecture) — Scans an existing codebase for module-level architecture friction — shallow modules, seam leaks, and locality gaps — using Ousterhout's deep-module lens, presents candidates as a self-contained HTML report, and runs an interview loop on the selected candidate before handing off for planning.
- [`prototype`](plugins/prototype) — Builds throwaway code to answer a design question before committing to architecture — a logic facet (an interactive terminal app over a portable state model) and a UI facet (radically different visual variants on one route).
- [`planning`](plugins/planning) — Pre-implementation planning pipeline: chart a too-big, foggy effort as a decision map, diverge on candidate approaches, lock product intent and the engineering contract, route resolved domain language to the domain-driven-design glossary steward, explore the design space, stress-test adversarially, and produce a structured implementation plan with an approval gate.
- [`domain-driven-design`](plugins/domain-driven-design) — Domain-driven-design practice skills. Today: actively maintains a consuming project's ubiquitous-language glossary — resolves ambiguous or overloaded terms, records canonical language and rejected synonyms, sharpens what-it-IS definitions, and routes entries to already-known bounded contexts without discovering boundaries.
- [`naming`](plugins/naming) — Generates and evaluates fresh name candidates for anything — an identifier, file, module, skill, repo, or domain term — by fanning out blind, fresh-context generators from distinct lenses (responsibility-literal, moment-of-use, domain-lore), then scoring a shortlist against the consuming org's naming criteria. The human always picks; it never auto-locks a name. An optional tournament mode adds elimination rounds with independent judges for high-stakes, hard-to-refactor names.
- [`event-storming`](plugins/event-storming) — EventStorming for domain discovery — a methodology skill (Big Picture / Process Modeling / Design-Level facilitation reference, notation, patterns) and a simulation skill (agentic multi-persona workshops that produce a structured-markdown model by default; a live Miro-board rendering path is available when the first-party miro plugin is enabled).
- [`miro`](plugins/miro) — Miro board management over the Model Context Protocol: create and manage boards, sticky notes, shapes, frames, connectors, and tags for EventStorming, brainstorming, and diagramming. Bundles a local stdio MCP server (single self-contained Node artifact); installs disabled — opt in and supply a Miro API token.

### Development

- [`markdown-format`](plugins/markdown-format) — Auto-format and lint Markdown on edit via markdownlint-cli2, using the consuming repo's own markdownlint config.
- [`bash-format`](plugins/bash-format) — Auto-format and lint shell scripts on edit via shfmt + ShellCheck, using the consuming repo's own .editorconfig and .shellcheckrc.
- [`biome-format`](plugins/biome-format) — Auto-format and lint JS/TS/JSX/JSON on edit via Biome, only when a biome.json governs the repo — using the consuming repo's own Biome config.
- [`ruff-format`](plugins/ruff-format) — Auto-format and lint Python on edit via Ruff, only when a Ruff config governs the repo — using the consuming repo's own Ruff config.
- [`eol-normalizer`](plugins/eol-normalizer) — Normalize a written file's working-tree line endings to its .gitattributes eol value on edit — symmetric CRLF/LF driven by git check-attr, advisory and never blocking.
- [`powershell-format`](plugins/powershell-format) — Auto-format and lint PowerShell on edit via PSScriptAnalyzer, only when a PSScriptAnalyzerSettings.psd1 governs the repo — using the consuming repo's own analyzer settings.
- [`actionlint`](plugins/actionlint) — Lint GitHub Actions workflow files on edit via actionlint, surfacing findings as advisory context.
- [`source-control`](plugins/source-control) — Git and GitHub delivery workflow: /commit (Conventional Commits + Co-Authored-By trailer via safe heredoc mechanics), /pull-request (prep, create, CI monitoring, review-comment triage, merge, CI-log fetch), /babysit-prs (self-pacing fleet loop — safe by default; opt-in worker/autopilot tiers add gate-checked merge and thread resolution behind a deterministic Python engine), /worktree (create, status, cleanup, audit for parallel-session isolation), /setup (interview the repo and write the tracked commit-subject / PR-title convention config plus babysit-prs userConfig), and /resolve-conflicts (intent-first merge/rebase conflict resolution with a semantic-conflict sweep — never --abort). The commit-subject / PR-title convention is configurable per repo via a tracked .claude/source-control.md config written by a re-runnable setup skill; Conventional Commits is the default when no convention is declared.
- [`implementation`](plugins/implementation) — Disciplined implementation stage: execute approved plans inline (`/implementation:implement`) or via orchestrated worker subagents (`/implementation:implement-dispatch`) with incremental validation, TDD-by-default cadence, green-checkpoint commits, scope-fence drift detection, and divergence detection that routes back to planning. Build/test/lint, testing, and outcome verification live in the companion `toolchain`, `testing`, and `verification` plugins, invoked when installed.
- [`toolchain`](plugins/toolchain) — Repo-agnostic polyglot verification toolchain: build + test + lint for changed files across .NET, Python, TypeScript, Bash, PowerShell, Markdown, YAML, and cross-cutting surfaces (`/toolchain:check`, `/toolchain:lint`), plus a re-runnable `/toolchain:setup` that writes the tracked per-ecosystem command config those skills resolve first.

### Testing

- [`playwright`](plugins/playwright) — Live E2E browser automation via Microsoft's @playwright/cli — named sessions, accessibility-ref snapshots, click/fill by ref, screenshots, console and network capture, mocking, tracing, video, and auth state, with artifacts written to disk so only paths enter context, plus a vendored upstream baseline and maintainer drift-check update flow.
- [`tdd`](plugins/tdd) — A TDD knowledge base distilled from cover-to-cover readings of Kent Beck's Test-Driven Development: By Example and Vladimir Khorikov's Unit Testing: Principles, Practices, and Patterns — fourteen author-attributed reference files behind a routing table plus a no-load quick decision guide, answering the WHY behind test design decisions.
- [`testing`](plugins/testing) — Test-stage discipline across all ecosystems: coverage-gap analysis and test planning (`/testing:plan`), TDD test authoring and placement (`/testing:write`), live E2E plus non-UI smoke verification (`/testing:e2e`), and failing-test root-cause diagnosis with the reproduce → isolate → fix → retest loop (`/testing:diagnose`).

### Verification

- [`verification`](plugins/verification) — Outcome-verification stage: prove a change achieved its intended outcome (`/verification:confirm` — a mechanical build/test/lint prerequisite gate, then intent-match + evidence + verdict with the criterion auto-detected by change type), and verify measurable-improvement claims against a planning-time baseline (`/verification:measure`), never fabricating numbers.

### Quality

- [`mcp-tools`](plugins/mcp-tools) — Audits MCP server tool definitions against MCP-specification and Anthropic tool-design criteria and reports a per-tool PASS/WARN/FAIL scorecard covering description, parameters, naming, and annotations. Language-agnostic — Python (FastMCP), TypeScript, and .NET.
- [`review`](plugins/review) — Code-review toolkit: six read-only reviewer agents (code, security, architecture, doc drift, build/test/lint, CI-log audit) plus two orchestration skills — a single-lens quality gate and a multi-surface review fan-out with severity-ranked, deduplicated findings.
- [`codebase-health`](plugins/codebase-health) — Repo-wide drift audit between docs, config, code, and architecture: verifies every factual claim against reality via parallel subagent fan-out, severity-rates findings, and fixes or presents for review. Audit dimensions are configurable through a tracked .claude/codebase-health.md config file written by the setup skill.
- [`re-anchor`](plugins/re-anchor) — Discipline correctors that re-anchor a standing rule mid-session, then audit both the work in flight and the pre-existing state and choices it trusts, and correct what has drifted: do-your-research (research and no-assumptions discipline; sibling do-your-research-deep escalates to a subagent-fanned verification pass over every load-bearing claim), follow-our-standards (alignment to the consuming org's engineering conventions), point-dont-copy (pointer-over-copy discipline — no copied content, internal-name coupling, or closed capability lists), reason-dont-recite (interrogate inherited content — precedent is evidence of what is, never self-justifying authority), tighten-your-output (terseness discipline — fewer words or lines with no loss of meaning or correctness), recheck-against-upstream (existing state is not evidence of its own correctness — audit config, code, and infra against current official upstream docs; sibling recheck-against-upstream-deep fans subagents doc-by-doc over a whole subsystem), pick-for-the-problem (tool, library, framework, and approach selection fitted to the problem, not reached for out of habit, availability, incumbency, or preconception), and mind-your-maxims (cooperative-communication discipline per Grice plus the AI-augmented transparency maxim). Firing one is a re-anchor, not an accusation; the audit may return clean.

### Maintenance

- [`bug-report`](plugins/bug-report) — Produces a structured five-field bug report — title, steps to reproduce, expected vs actual, severity with justification, and suggested fix location — from an informal defect description. Read-only by default: it emits the report and never edits code, opens a PR, or files an issue on its own.
- [`debugging`](plugins/debugging) — Debug observed failures via a disciplined six-phase loop: build a fast deterministic reproduction signal, reproduce, rank falsifiable hypotheses, instrument, fix with a regression test, then clean up and post-mortem.
- [`docs-hygiene`](plugins/docs-hygiene) — Documentation-hygiene toolkit of five skills: compress (flavor-trim markdown with a semantic-diff safety net), audit-noise (classify markdown noise), extract-ssot (deduplicate repeated content into a single source of truth), audit-encapsulation (detect citations into skill-private surfaces), and rename-references (sweep stale references after renames).
- [`code-tidying`](plugins/code-tidying) — Code tidying and comment hygiene: /code-tidying:tidy proactively hunts a rotated, glob-scoped lane for Beck-style tidyings under a research-backed scope budget and ships one tight PR; /code-tidying:batch-simplify sweeps recently changed files through grouped, dependency-ordered simplification waves with a never-drop deferred-items contract; /code-tidying:comment-residue is a read-only classifier that flags history, plan, conversational, and ticket/PR residue in code comments for author-applied deletion. Project-specific tidy lanes are scaffolded into a tracked .claude/tidy-lanes/ config folder by a re-runnable setup skill.
- [`repo-hygiene`](plugins/repo-hygiene) — Repo hygiene action-router: /repo-hygiene:clean sweeps reclaimable caches, build artifacts, and stale git metadata, and can realign the working tree to a fresh-pull state — dry-run-first, with destructive tiers gated behind explicit confirmation and a session-scoped destructive-command guard. Ecosystem targets are detected at runtime; secrets, runtime dependencies, and skill data are preserved by default.
- [`repo-fleet-hygiene`](plugins/repo-fleet-hygiene) — Read-only Git/GitHub fleet audit for merged local branches, orphaned or mismatched worktree registrations, and repository transfers or renames. Findings are confidence-tiered and hand off exact targets to existing per-repository cleanup tools; this plugin never deletes branches or worktrees.
- [`disk-hygiene`](plugins/disk-hygiene) — Context-aware disk hygiene for arbitrary directory trees: inventories orphaned and temporary artifacts, classifies evidence into review tiers, and offers exact-path cleanup only after a fresh safety preview and explicit per-tier approval. The target is read-only by default; OS-managed paths, links and mount points, VCS-tracked content, changed entries, and live-handle uncertainty fail closed.

### Claude Code

- [`desktop-notification`](plugins/desktop-notification) — Alert you when Claude Code needs input — an audible terminal bell, an OSC 9 terminal notification, and an OS-native toast (macOS/Linux) on permission and idle prompts.
- [`playbooks`](plugins/playbooks) — Doctrine and knowledge playbooks as on-demand skills, plus a maintainer-facing update skill. boris — Boris Cherny's Claude Code workflow tips (howborisusesclaudecode.com); skill-authoring — Anthropic's internal skill-authoring playbook; fable-5 — Claude Fable 5's operating doctrine (self-authored, no upstream). The boris and skill-authoring packs vendor a verbatim upstream baseline; /playbooks:update drift-checks and syncs those baselines centrally (maintainers).
- [`claude-config`](plugins/claude-config) — Three audit skills for a repo's Claude Code configuration: audit (settings.json / .mcp.json / hooks / plugins / permissions drift), automation-gaps (evidence-gated verdicts on automation gaps), and permission-hygiene (allow-rule / allowed-tools grants for auto-mode durability and portability).
- [`claude-memory`](plugins/claude-memory) — Audits the Claude Code instruction/memory layer — CLAUDE.md, CLAUDE.local.md, .claude/rules/, and auto-memory — against a checklist derived from official Claude Code documentation. A deterministic script-backed spine (MEMORY.md index integrity, orphan always-loaded rules) yields identical findings on identical repo state; judgment-tier checks apply fixed criteria with model reading. Actions: audit (default), fix (per-item approval), update (refresh criteria from current docs), report.
- [`claude-ops`](plugins/claude-ops) — Claude Code operations toolkit. Five skills: observability (read locally captured telemetry — OTEL store, collector, hook-event JSONL, ccusage — with trend reports and store pruning), known-issues (search known Claude product GitHub bugs, check service health, maintain a persistent tracked-issue registry), changelog (ingest Claude Code changelog entries and integrate them into the current repo), plugins (bring a machine's plugin fleet current on demand — marketplace refresh, effective-scope updates including in-repo project/local installs, new-plugin install per policy, scope-divergence detection and explicit convergence), and a re-runnable setup action that settles where the known-issues registry lives. Plus a family of seven advisory *-audit telemetry-emitter hooks (API errors, config changes, instruction loads, permission denials, pre-compaction, skill usage, tool failures) that emit the shared hook-telemetry envelope, and a reference sink that maps envelopes into the hook-events.jsonl the observability skill reads.
- [`skill-quality`](plugins/skill-quality) — Skill-authoring QA tooling: a static contract checker that runs seventeen deterministic checks over a Claude Code skill (frontmatter, listing-budget cap, trigger-keyword preservation, line caps, broken internal refs, markdownlint, gotchas surface, evals presence) and a bundled evals.json schema for validation. Runs against any repo's skills directory via the convention-resolution ladder — no baked layout.

### Autonomy

- [`autonomy`](plugins/autonomy) — Governed autonomous agent operation: role-topology, binding-seam, and wiring-vs-advisor contracts for climbing the AI-adoption ladder, plus a guided-setup skill that discovers an adopting org's state and writes its schema-versioned binding.

### Security

- [`guardrails`](plugins/guardrails) — Eight safety guards that block secret/credential writes, hardcoded machine-specific paths, git hook-bypass attempts, irreversible git operations (force-push, reset --hard, worktree-wide checkout/restore discards), Bash file-write workarounds that circumvent Write/Edit hooks, (advisory) hallucinated CLI flags, (advisory) un-throttled Workflow fan-out that risks burst 529s, and (advisory) direct git commit/gh pr create calls bypassing this marketplace's own commit/pull-request skills — each independently toggleable.

### Workflow

- [`session-flow`](plugins/session-flow) — Session-lifecycle toolkit of six skills: workflow (navigate a staged dev workflow and suggest the next stage), handoff (write a save-point and resume prompt for /clear, with optional --bg background-agent launch), keep-going (recover and continue after any interruption — inventory off-thread work, inspect its real state, resume or restart it, then continue the main task), retro (structured session retrospective with transcript metrics and learning codification), orchestrate (arm a session or worker with proactive-orchestration imperatives), and reanchor (verify a session's working assumptions are still true against live reality — referenced PRs/issues/branches, base-branch drift, renamed/version-drifted surfaces, stale memory-tier files — before building on them).

### Project Management

- [`work-items`](plugins/work-items) — Manages development work items through a provider-neutral tracker seam (GitHub the bound adapter today): dashboard, taxonomy-labeled creation, a race-safe assignee-plus-lease claim protocol, recurring-schedule checks, TODO scanning, stale-lease auditing, plan decomposition into vertical-slice items, and raw-intake triage (issues and unsolicited PRs through raw, verified, briefed, autonomous-eligible states). Canonical role labels remap via the tracker binding; the recurring-schedule seam (.github/recurring-schedule.json) is seeded and reshaped by the re-runnable setup skill.

### Operations

- [`machine-health`](plugins/machine-health) — Workstation health audit: OS-specific checks (disk, OS updates, security posture, CISA KEV correlation) run from a versioned catalog with trend-aware severity, approval-gated remediations, and dated markdown reports. Windows fully implemented; macOS/Linux scaffolded (report UNKNOWN and stop). Machine state persists in the plugin data directory; the report directory and check catalog are configurable.

### Learning

- [`education`](plugins/education) — Interactive multi-session learning coach: teaches a general subject or a concept grounded in the consuming repo through the Knowledge-Skills-Wisdom progression, with persistent per-topic learning state. Also a single-session domain primer.

### Music

- [`songwriting`](plugins/songwriting) — Songwriting craft companion — eight concern-scoped lyric-craft skills (workflow router, rhyme, object-writing, meter-prosody, song-form, co-write, diagnosis, daily-practice) applying Pat Pattison's methods, plus Suno v5.5 prompt engineering (style prompts, tagged lyrics, genre templates, troubleshooting).

### Personal

- [`kindle-dedrm`](plugins/kindle-dedrm) — Manage the Kindle for PC 2.8.0 + Calibre DeDRM workflow for personal-use ebook DRM removal on books you own (Windows only). Action router with setup, sync, update, cleanup, and status, each state mutation paired with a documented compensating reversal.
- [`ai-briefing`](plugins/ai-briefing) — Build source-backed AI-industry briefings from official vendor publications, configured RSS/Atom feeds, GitHub releases, reputable secondary reporting, and user-supplied URLs. Deduplicate, rank, and present results as markdown or optional HTML/PPTX decks, with repository-owned profile, audience, and brand configuration. Automated X/Twitter collection is disabled; Playwright is used only for deterministic local rendering.

<!-- catalog:end -->

Install one: `/plugin install <plugin-name>@melodic-software`.

## What's here

- `.claude-plugin/marketplace.json` — the marketplace catalog.
- `plugins/` — one directory per plugin.
- `docs/MIGRATION-PLAYBOOK.md` — design charter, extensibility model, the per-plugin migration gate, and the local development loop.
- `docs/extensibility-contract-smoke-tests.md` — verified behavior for gaps the official docs leave open.
- `docs/hook-migration-audit.md` — point-in-time audit of medley's general-purpose hooks for extraction into `guardrails`/`claude-ops`.
- `docs/ai-briefing-design.md` — engine/profile/personal split design record for the `ai-briefing` migration (reference adopter of the profiled-folder convention).
- `docs/CI-RUNNER-ROUTING.md` — local-runner selection, hosted boundaries, and failure recovery.
- `CLAUDE.md` — operating rules for AI agents working in this repo (fresh-docs mandate + canonical links).

## Official documentation

This repo tracks policy and wiring only; authoritative behavior lives in the official docs, which must
be read fresh rather than recalled. Start at the
[Claude Code plugins guide](https://code.claude.com/docs/en/plugins).

## License

[MIT](LICENSE).
