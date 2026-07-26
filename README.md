# Melodic Software — Claude Code plugins

A public [Claude Code](https://code.claude.com/docs) plugin marketplace of reusable, repo-agnostic
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
- [`firecrawl`](plugins/firecrawl) — Web scraping, search, crawling, and file parsing through the firecrawl-cli binary with a write-to-disk-then-Read pattern that keeps large results out of context — a user-facing wrapper skill, a lazy-install setup skill, and a separate gated maintainer update skill tracking the upstream CLI and skill source.
- [`discovery`](plugins/discovery) — Structured discovery before changes: explore the local codebase and run disciplined multi-source external research, both dispatching a purpose-built subagent by default so the reading stays out of the main conversation — with source tiers, falsification, recency gates, and a corpus-coverage ledger — persisting EXPLORE.md / RESEARCH.md index-plus-sidecar handoff artifacts.
- [`dometrain`](plugins/dometrain) — Dometrain course-content grounding over a third-party remote MCP server (Dometrain-hosted, Bearer auth): search lessons, pull curated lesson documents with on-screen code, and cite timestamped deep links. Requires an active Dometrain Pro subscription. Credential entered once through Claude Code's native masked userConfig prompt and stored in secure credential storage. Ships with a grounding usage skill kept in sync with Dometrain's own official Claude Code plugin.
- [`x`](plugins/x) — Read X (formerly Twitter) posts, note tweets, and X Articles as Markdown without an X API key, via a documented fallback ladder over third-party converters — xtomd.com for single posts and articles, Thread Reader App for unrolled reply chains — so a pasted X link becomes readable content instead of a login wall.

### Design

- [`architecture`](plugins/architecture) — Scans an existing codebase for module-level architecture friction — shallow modules, seam leaks, and locality gaps — using Ousterhout's deep-module lens, presents candidates as a self-contained HTML report, and runs an interview loop on the selected candidate before handing off for planning.
- [`prototype`](plugins/prototype) — Builds throwaway code to answer a design question before committing to architecture — a logic facet (an interactive terminal app over a portable state model) and a UI facet (radically different visual variants on one route).
- [`planning`](plugins/planning) — Pre-implementation planning pipeline: chart a too-big, foggy effort as a decision map, diverge on candidate approaches, lock product intent and the engineering contract, route resolved domain language to the domain-driven-design glossary steward, explore the design space, stress-test adversarially, and produce a structured implementation plan with an approval gate.
- [`domain-driven-design`](plugins/domain-driven-design) — Domain-driven-design practice skills. Today: actively maintains a consuming project's ubiquitous-language glossary — resolves ambiguous or overloaded terms, records canonical language and rejected synonyms, sharpens what-it-IS definitions, and routes entries to already-known bounded contexts without discovering boundaries.
- [`naming`](plugins/naming) — Generates and evaluates fresh name candidates for anything — an identifier, file, module, skill, repo, or domain term — by distilling a structured context brief, fanning out blind, fresh-context generators from distinct lenses (responsibility-literal, moment-of-use, domain-lore), then scoring a shortlist against a research-ordered criteria priority resolved from the consuming org's naming criteria. The human always picks; it never auto-locks a name. An optional tournament mode adds elimination rounds with independent judges for high-stakes, hard-to-refactor names.
- [`event-storming`](plugins/event-storming) — EventStorming for domain discovery — a methodology skill (Big Picture / Process Modeling / Design-Level facilitation reference, notation, patterns) and a simulation skill (agentic multi-persona workshops that produce a structured-markdown model by default; a live Miro-board rendering path is available when the first-party miro plugin is enabled).
- [`miro`](plugins/miro) — Miro board management over the Model Context Protocol: create and manage boards, sticky notes, shapes, frames, connectors, and tags for EventStorming, brainstorming, and diagramming. Bundles a local stdio MCP server (single self-contained Node artifact); installs disabled — opt in and supply a Miro API token.

### Development

- [`markdown-format`](plugins/markdown-format) — Auto-format and lint Markdown on edit via markdownlint-cli2, using the consuming repo's own markdownlint config.
- [`bash-format`](plugins/bash-format) — Auto-format and lint shell scripts on edit via shfmt + ShellCheck, using the consuming repo's own .editorconfig and .shellcheckrc.
- [`biome-format`](plugins/biome-format) — Auto-format and lint JS/TS/JSX/JSON on edit via Biome, only when a biome.json governs the repo — using the consuming repo's own Biome config.
- [`ruff-format`](plugins/ruff-format) — Auto-format and lint Python on edit via Ruff, only when a Ruff config governs the repo — using the consuming repo's own Ruff config.
- [`typos-format`](plugins/typos-format) — Auto-fix spelling typos on edit via typos-cli, unconditionally — honoring the consuming repo's own typos configuration when one is present.
- [`go-format`](plugins/go-format) — Auto-fix Go formatting and import management on edit via goimports — runs unconditionally (no consumer-config gate), skipping generated files.
- [`eol-normalizer`](plugins/eol-normalizer) — Normalize a written file's working-tree line endings to its .gitattributes eol value on edit — symmetric CRLF/LF driven by git check-attr, advisory and never blocking.
- [`powershell-format`](plugins/powershell-format) — Auto-format and lint PowerShell on edit via PSScriptAnalyzer, only when a PSScriptAnalyzerSettings.psd1 governs the repo — using the consuming repo's own analyzer settings.
- [`actionlint`](plugins/actionlint) — Lint GitHub Actions workflow files on edit via actionlint, surfacing findings as advisory context.
- [`source-control`](plugins/source-control) — Git and GitHub delivery workflow: /commit (Conventional Commits + Co-Authored-By trailer via safe heredoc mechanics), /pull-request (prep, create, CI monitoring, review-comment triage, merge, CI-log fetch), /babysit-prs (self-pacing fleet loop — safe by default; opt-in worker/autopilot tiers add gate-checked merge and thread resolution behind a deterministic Python engine), /babysit-loop (the loop-lane merge lane: a standing or drain loop that invokes babysit-prs per cycle, configured through repo-scoped babysit_loop_* keys on the layered source-control.md seam, with merge authority human-only until the target repo's tracked config adopts the lane, a gate-proven C2-mechanical baseline once adopted, and merge-rung raises binding from the team-tracked layer only), /worktree (create, status, cleanup, audit for parallel-session isolation), /setup (check the effective commit-subject / PR-title convention merged across its config layers and the babysit-prs config, or apply — interview the repo and write the convention config to a chosen layer), and /resolve-conflicts (intent-first merge/rebase conflict resolution with a semantic-conflict sweep — never --abort). The commit-subject / PR-title convention is configurable via a source-control.md config written by a re-runnable setup skill, layered across a ~/.claude user-global file, the tracked team file, and a gitignored .claude/source-control.local.md personal overlay merged per key; Conventional Commits is the default when no convention is declared.
- [`implementation`](plugins/implementation) — Disciplined implementation stage: execute approved plans inline (`/implementation:implement`) or via orchestrated worker subagents (`/implementation:implement-dispatch`) with incremental validation, TDD-by-default cadence, green-checkpoint commits, scope-fence drift detection, and divergence detection that routes back to planning. Build/test/lint, testing, and outcome verification live in the companion `toolchain`, `testing`, and `verification` plugins, invoked when installed.
- [`toolchain`](plugins/toolchain) — Repo-agnostic polyglot verification toolchain: build + test + lint for changed files across .NET, Python, TypeScript, Bash, PowerShell, Markdown, Go, YAML, and cross-cutting surfaces (`/toolchain:check`, `/toolchain:lint`), plus a re-runnable `/toolchain:setup` with check (report the configured ecosystems and their command surface) and apply (interview, infer, and write the tracked per-ecosystem command config those skills resolve first).

### Testing

- [`playwright`](plugins/playwright) — Live E2E browser automation via Microsoft's @playwright/cli — named sessions, accessibility-ref snapshots, click/fill by ref, screenshots, console and network capture, mocking, tracing, video, and auth state, with artifacts written to disk so only paths enter context, plus a vendored upstream baseline and maintainer drift-check update flow.
- [`tdd`](plugins/tdd) — A TDD knowledge base distilled from cover-to-cover readings of Kent Beck's Test-Driven Development: By Example and Vladimir Khorikov's Unit Testing: Principles, Practices, and Patterns — fourteen author-attributed reference files behind a routing table plus a no-load quick decision guide, answering the WHY behind test design decisions.
- [`testing`](plugins/testing) — Test-stage discipline across all ecosystems: coverage-gap analysis and test planning (`/testing:plan`), TDD test authoring and placement (`/testing:write`), live E2E plus non-UI smoke verification (`/testing:run-e2e`), and failing-test root-cause diagnosis with the reproduce → isolate → fix → retest loop (`/testing:diagnose`).

### Verification

- [`verification`](plugins/verification) — Outcome-verification stage: prove a change achieved its intended outcome (`/verification:confirm` — a mechanical build/test/lint prerequisite gate, then intent-match + evidence + verdict with the criterion auto-detected by change type), and verify measurable-improvement claims against a planning-time baseline (`/verification:measure`), never fabricating numbers.

### Quality

- [`mcp-tools`](plugins/mcp-tools) — Audits MCP server tool definitions against MCP-specification and Anthropic tool-design criteria and reports a per-tool PASS/WARN/FAIL scorecard covering description, parameters, naming, and annotations. Language-agnostic — Python (FastMCP), TypeScript, and .NET.
- [`review`](plugins/review) — Code-review toolkit: six read-only reviewer agents (code, security, architecture, doc drift, build/test/lint, CI-log audit) plus two orchestration skills — a single-lens quality gate and a multi-surface review fan-out with severity-ranked, deduplicated findings.
- [`codebase-health`](plugins/codebase-health) — Repo-wide drift audit between docs, config, code, and architecture: verifies every factual claim against reality via parallel subagent fan-out, severity-rates findings, and reports read-only, delegating remediation to the implementation/verification lanes. Audit dimensions are configurable through a tracked .claude/codebase-health.md config file written by the setup skill.
- [`discipline`](plugins/discipline) — Discipline correctors that re-anchor a standing rule mid-session, then audit both the work in flight and the pre-existing state and choices it trusts, and correct what has drifted: do-your-research (research and no-assumptions discipline; sibling do-your-research-deep escalates to a typed full inventory of the session's claims — assumptions, asserted facts, concrete specifics, load-bearing premises — verified at a configurable depth and reported as a per-item ledger), follow-our-standards (alignment to the consuming org's engineering conventions), point-dont-copy (pointer-over-copy discipline — no copied content, internal-name coupling, or closed capability lists), reason-dont-recite (interrogate inherited content — precedent is evidence of what is, never self-justifying authority), tighten-your-output (terseness discipline — fewer words or lines with no loss of meaning or correctness), recheck-against-upstream (existing state is not evidence of its own correctness — audit config, code, and infra against current official upstream docs; sibling recheck-against-upstream-deep fans subagents doc-by-doc over a whole subsystem), pick-for-the-problem (tool, library, framework, and approach selection fitted to the problem, not reached for out of habit, availability, incumbency, or preconception), mind-your-maxims (cooperative-communication discipline per Grice plus the AI-augmented transparency maxim), script-the-deterministic-work (offload deterministic sub-work — counts, diffs, sorts, transforms, and scaffolds — to a script that runs, reserving model output for judgment over its real output; the audit runs both ways, also catching an existing script that over-reaches into judgement), use-your-skills (actually use the skills already in context — scan the listing, map the task, invoke the fitting skill instead of reinventing it, and name skills when delegating to a subagent), and reuse-or-replace (anti-fragmentation — new work reuses an established way of doing something or openly replaces it (migrate the old uses, record the decision), never silently stands up a second parallel way; divergence is allowed but owes a recorded reason proportional to blast radius), and scrutinize-dont-coast (adversarial self-scrutiny — stop coasting on your own recent output and re-examine whether it is sound, not merely confidently produced, through a fresh-context pass blind to the reasoning that made it, then remediate with the user; it stops the trajectory first and remediates collaboratively rather than autonomously). Plus sweep-all, a posture-batch runbook — not a corrector but a declared second species that composes them: it fans out an audit-only subagent per in-scope corrector, then applies the corrections on the main thread in a fixed order, with batch membership and order set by each corrector's own colocated tier metadata and an optional userConfig overlay. Firing one is a re-anchor, not an accusation; the audit may return clean.

### Maintenance

- [`bug-report`](plugins/bug-report) — Produces a structured five-field bug report — title, steps to reproduce, expected vs actual, severity with justification, and suggested fix location — from an informal defect description. Read-only by default: it emits the report and never edits code, opens a PR, or files an issue on its own.
- [`debugging`](plugins/debugging) — Debug observed failures via a disciplined six-phase loop: build a fast deterministic reproduction signal, reproduce, rank falsifiable hypotheses, instrument, fix with a regression test, then clean up and post-mortem.
- [`docs-hygiene`](plugins/docs-hygiene) — Documentation-hygiene toolkit of six skills: compress (flavor-trim markdown with a semantic-diff safety net), audit-noise (classify markdown noise), extract-ssot (deduplicate repeated content into a single source of truth), audit-encapsulation (detect citations into skill-private surfaces), rename-references (sweep stale references after renames), and audit-derivability (classify whether a whole document earns its existence — could a fresh agent re-derive it from the code?).
- [`code-tidying`](plugins/code-tidying) — Code tidying and comment hygiene: /code-tidying:tidy proactively hunts a rotated, glob-scoped lane for Beck-style tidyings under a research-backed scope budget and ships one tight PR; /code-tidying:batch-simplify sweeps recently changed files through grouped, dependency-ordered simplification waves with a never-drop deferred-items contract; /code-tidying:audit-comment-residue is a read-only classifier that flags history, plan, conversational, and ticket/PR residue in code comments for author-applied deletion. Project-specific tidy lanes are scaffolded into a tracked .claude/tidy-lanes/ config folder by a re-runnable setup skill.
- [`repo-hygiene`](plugins/repo-hygiene) — Repo hygiene action-router: /repo-hygiene:clean sweeps reclaimable caches, build artifacts, and stale git metadata, and can realign the working tree to a fresh-pull state — dry-run-first, with destructive tiers gated behind explicit confirmation and a session-scoped destructive-command guard. Ecosystem targets are detected at runtime; secrets, runtime dependencies, and skill data are preserved by default.
- [`repo-fleet-hygiene`](plugins/repo-fleet-hygiene) — Read-only Git/GitHub fleet audit for merged local branches, orphaned or mismatched worktree registrations, and repository transfers or renames. Findings are confidence-tiered and hand off exact targets to existing per-repository cleanup tools; this plugin never deletes branches or worktrees.
- [`disk-hygiene`](plugins/disk-hygiene) — Context-aware disk hygiene for arbitrary directory trees: inventories orphaned and temporary artifacts, classifies evidence into review tiers, and offers exact-path cleanup only after a fresh safety preview and explicit per-tier approval. The target is read-only by default; OS-managed paths, links and mount points, VCS-tracked content, changed entries, and live-handle uncertainty fail closed.

### Claude Code

- [`desktop-notification`](plugins/desktop-notification) — Alert you when Claude Code needs input — an audible terminal bell, an OSC 9 terminal notification, and an OS-native toast (macOS/Linux) on permission and idle prompts.
- [`playbooks`](plugins/playbooks) — Doctrine and knowledge playbooks as on-demand skills, plus a maintainer-facing update skill. boris — Boris Cherny's Claude Code workflow tips (howborisusesclaudecode.com); skill-authoring — Anthropic's internal skill-authoring playbook; fable-5 — Claude Fable 5's operating doctrine (self-authored, no upstream). The boris and skill-authoring packs vendor a verbatim upstream baseline; /playbooks:update drift-checks and syncs those baselines centrally (maintainers).
- [`claude-config`](plugins/claude-config) — Five audit skills for a repo's Claude Code configuration: audit (settings.json / .mcp.json / hooks / plugins / permissions drift), audit-automation-gaps (evidence-gated verdicts on automation gaps), audit-permission-grants (allow-rule / allowed-tools grants for auto-mode durability and portability), audit-instructions (locally-owned instruction surfaces vs current model capability — proposes removals/rewrites of instructions the model no longer needs, and detects cross-surface instruction conflicts), and audit-pass (one coordinated, ordered, resumable pass over a named target — three-scope inventory, run-time-derived exclusion set, stable finding identity, suppression memory, resume, one human gate — delegating every check to the plugin that owns it).
- [`claude-memory`](plugins/claude-memory) — Keeps a repo's Claude Code memory layer healthy and under your control, against criteria derived from official Claude Code documentation. The audit skill checks the instruction/memory layer (CLAUDE.md, CLAUDE.local.md, .claude/rules/, auto-memory) with a deterministic script-backed spine plus judgment-tier checks. The stateless skill inspects, disables, and (confirm-gated) purges Claude-written auto memory across all settings scopes.
- [`claude-ops`](plugins/claude-ops) — Claude Code operations toolkit. Seven skills: observability (read locally captured telemetry — OTEL store, collector, hook-event JSONL, ccusage — with trend reports and store pruning), known-issues (search known Claude product GitHub bugs, check service health, maintain a persistent tracked-issue registry), changelog (ingest Claude Code changelog entries and integrate them into the current repo), plugins (bring a machine's plugin fleet current on demand — marketplace refresh, effective-scope updates including in-repo project/local installs, new-plugin install per policy, scope-divergence detection and explicit convergence), morning-brief (read-only gh-based operator morning view — queue-label counts, merge-ready PRs, parked decisions with their RECOMMENDED lines, and loop-lane telemetry freshness), lanes (start/restart/stop/status loop lanes as named background Claude Code sessions seeded from canonical prompt files, with per-lane model/effort and a repo-pull + marketplace-refresh launch step), and a re-runnable setup action that settles where the known-issues registry lives. Plus a family of seven advisory *-audit telemetry-emitter hooks (API errors, config changes, instruction loads, permission denials, pre-compaction, skill usage, tool failures) that emit the shared hook-telemetry envelope, and a reference sink that maps envelopes into the hook-events.jsonl the observability skill reads.
- [`rate-limit-guard`](plugins/rate-limit-guard) — Shared rate-limit guard for loop lanes: a statusline wrapper tees the subscription rate-limit windows to a fixed machine-scope file, a StopFailure hook records rate-limit stops reactively, and a reader contract fixes how consuming sessions pause and resume.
- [`context-guard`](plugins/context-guard) — Per-session context-window observability: a statusline wrapper tees each session's context_window fields to a per-session snapshot file, a zone resolver classifies usage into smart/acceptable/dumb bands (zones.json SSOT with shipped defaults), and a reader contract fixes how consuming sessions interpret the snapshots.
- [`plugin-quality`](plugins/plugin-quality) — Post-use behavioral audit of Claude Code plugin components: a six-step audit workflow (evidence capture, grounded mapping in a fresh subagent, blindspot pass, interactive contract lock, presence-gated review seams, work-item emit with draft+confirm) over any skill, agent, hook, command, or config you have actually used — zone-informed by context-guard snapshots when present, conservative when not.
- [`skill-quality`](plugins/skill-quality) — Skill-authoring QA tooling: a static contract checker that runs twenty deterministic checks over a Claude Code skill (frontmatter, listing-budget cap, trigger-keyword preservation, line caps, broken internal refs, markdownlint, gotchas surface, evals presence, precompute opportunity, injection shell-declaration) and a bundled evals.json schema for validation. Runs against any repo's skills directory via the convention-resolution ladder — no baked layout.

### Autonomy

- [`autonomy`](plugins/autonomy) — Governed autonomous agent operation: role-topology, binding-seam, wiring-vs-advisor, telemetry, return-accounting, trigger-dispatch, per-work-class guardrail-matrix, standing-routine-catalog, and design-only runner-charter contracts for climbing the AI-adoption ladder, plus a guided-setup skill that discovers an adopting org's state, writes its schema-versioned binding, wires standards-pinned OTLP emission with a zero-cost file-artifact default, wires human-attested return capture at the task boundary, wires signal adapters with one governed dispatch entrypoint, binds the five-class guardrail matrix to an org's isolation substrates with an in-boundary live-validation probe before recording each fail-closed binding, and stands up standing-routine-catalog classes as scheduled temporal signal adapters behind the one governed queue with free scheduling defaults wired as reviewable changes and each routine's work-class mapping homed on the security surface.

### Security

- [`guardrails`](plugins/guardrails) — Twelve safety guards that block secret/credential writes, hardcoded machine-specific paths, git hook-bypass attempts, irreversible git operations (force-push, reset --hard, worktree-wide checkout/restore discards), Bash file-write workarounds that circumvent Write/Edit hooks, commit subjects and gh pr create titles that violate the repo's tracked team convention (when one is declared in .claude/source-control.md), (advisory) hallucinated CLI flags, (advisory) /plugin:skill references that do not resolve, (advisory) markdown citing a repo path the repo's own history shows was removed, (advisory) un-throttled Workflow fan-out that risks burst 529s, and (advisory) direct git commit/gh pr create calls bypassing this marketplace's own commit/pull-request skills — each independently toggleable.

### Workflow

- [`session-flow`](plugins/session-flow) — Session-lifecycle toolkit of thirteen skills: workflow (navigate a staged dev workflow and suggest the next stage), handoff (write a save-point and resume prompt for /clear-and-resume), continue-in-background (delegate the task to a fresh background agent that continues it now — same save-point engine as handoff, delivered by launching a detached claude --bg session seeded with the resume prompt; launches only on explicit user request), keep-going (recover and continue after any interruption OR when live off-thread work looks stalled — inventory off-thread work, inspect its real output, act only on evidence, then continue; after a usage limit lifts it continues rather than summarizing-and-stalling), find-handoff (recover a lost handoff after /clear — when the resume prompt was written but never copied — via a read-only detection ladder: known-location glob of the handoffs dir, then a bounded, recency-ranked transcript scan for the handoff directive and dashed-rail markers, then a confirm-before-resume gate; surfaces only the resume prompt + metadata, never raw transcript content), clean-stop (get to a durable, linked stopping point before the machine may go away — sweep every repo/worktree for uncommitted, unpushed, or PR-less work, push it durable, put breadcrumbs in PR/issue bodies, then give a free-and-clear verdict), retro (structured end-of-session retrospective with transcript metrics and learning codification), running-retro (in-flight retrospective checkpoints that spawn a subagent to analyze the transcript so far and append classified findings to a cumulative running ledger — capture and route only, the live counterpart to retro; also owns a detached-observer substrate that can watch a session out-of-band and run the checkpoint autonomously after the session ends), orient (read-only session orientation — synthesize where we stand, what we are doing, and why, from durable + off-thread state the built-in /recap never sees: ledgers, handoffs, workflow checklists, running-retro ledgers, open PRs and work-items, and git), orchestrate (arm a session or worker with proactive-orchestration imperatives), reanchor (verify a session's working assumptions are still true against live reality — referenced PRs/issues/branches, base-branch drift, renamed/version-drifted surfaces, stale memory-tier files — before building on them), reconcile (retire finished off-thread work and reconcile this session's task ledger with reality — the prune-and-reconcile counterpart to keep-going's resume: inventory the work this session spawned, inspect its real state, retire the finished and close proven-done tasks, auto-settling the finished and gating any kill of still-running work; sibling sessions in the project are reported read-only), and setup (check-centric verification of the observer's runtime prerequisites and configuration).
- [`visualization`](plugins/visualization) — On-demand visualization router: infers what in the current conversation should be shown visually, then decides the best FORM (a mermaid diagram, a markdown table, a hand-authored SVG/CSS chart, ASCII/Unicode art, or a rich rendered page) and the best MEDIUM (inline terminal, a local HTML file, or a published Artifact) via a decision matrix over content shape, complexity, and a configurable medium preference. Renders good defaults and asks only when the target is genuinely ambiguous and no form was named. A form-and-medium decision layer in front of the craft capabilities — it routes chart craft and artifact-design fundamentals to those capabilities when installed and never restates them.

### Project Management

- [`work-items`](plugins/work-items) — Manages development work items through a provider-neutral tracker seam that ships with the plugin (bundled dispatcher plus github and local-markdown adapters; seam plugin-dir canonical, adapters consumer-local-first): dashboard, taxonomy-labeled creation, a race-safe assignee-plus-lease claim protocol, recurring-schedule checks, TODO scanning, stale-lease auditing, plan decomposition into vertical-slice items, raw-intake triage (issues and unsolicited PRs through raw, verified, briefed, autonomous-eligible states), plus the two work-items loop lanes of the loop-lane convention: a self-paced autonomous work-loop drain (work-class admission gate, adaptive item cap, PR-only) and an attended attend-queue escalation lane. The re-runnable setup skill binds the provider (.work-item-tracker.json), seeds the recurring-schedule seam (.github/recurring-schedule.json), and remaps canonical role labels.

### Operations

- [`machine-health`](plugins/machine-health) — Workstation health audit: OS-specific checks (disk, OS updates, security posture, CISA KEV correlation) run from a versioned catalog with trend-aware severity, approval-gated remediations, and dated markdown reports. Windows fully implemented; macOS/Linux scaffolded (report UNKNOWN and stop). Machine state persists in the plugin data directory; the report directory and check catalog are configurable.
- [`github`](plugins/github) — GitHub admin-plane audit, advice, and guided setup over the authenticated user's own gh CLI: billing and cost control, security posture, rulesets and settings drift, Actions policy, and every other org/repo/enterprise settings area. Grounded in live state and current official GitHub docs (zero vendored knowledge); read-only by default, every mutation user-in-loop.

### Learning

- [`education`](plugins/education) — Interactive multi-session learning coach: teaches a general subject or a concept grounded in the consuming repo through the Knowledge-Skills-Wisdom progression, with persistent per-topic learning state. Also a single-session domain primer, a one-shot plain-language explainer that drops anything to genuinely plain words, and a post-work comprehension check that quizzes the human on a completed change.

### Music

- [`songwriting`](plugins/songwriting) — Songwriting craft companion — eight concern-scoped lyric-craft skills (workflow router, rhyme, object-writing, meter-prosody, song-form, co-write, diagnose, practice) applying Pat Pattison's methods, plus Suno v5.5 prompt engineering (style prompts, tagged lyrics, genre templates, troubleshooting).

### Personal

- [`kindle-dedrm`](plugins/kindle-dedrm) — Manage the Kindle for PC 2.8.0 + Calibre DeDRM workflow for personal-use ebook DRM removal on books you own (Windows only). Action router with setup, sync, update, cleanup, and status, each state mutation paired with a documented compensating reversal.
- [`ai-briefing`](plugins/ai-briefing) — Build source-backed AI-industry briefings from official vendor publications, configured RSS/Atom feeds, GitHub releases, reputable secondary reporting, and user-supplied URLs. Deduplicate, rank, and present results as markdown or optional HTML/PPTX decks, with repository-owned profile, audience, and brand configuration. Automated X/Twitter collection is disabled; Playwright is used only for deterministic local rendering.
- [`adhd`](plugins/adhd) — Shape and restructure the assistant's output for a reader with ADHD — action-first, low-friction, and digestible. adhd:shape is a standing session posture: lead with the concrete next action, number multi-step work, restate state across turns, cap and rank lists, give concrete time estimates, make wins visible, and cut preamble, recap, and closers. adhd:clarify is a one-shot reshape of a dense, decision-heavy artifact already on screen — chunk it one-decision-at-a-time, define the session's own jargon, and surface exactly what you must decide, faithfully (operative terms quoted verbatim, no altitude loss), rendered as an HTML decision table for big content. Reauthored in part from ayghri/i-have-adhd (MIT). Deliberately mutually exclusive with terse-for-tokens output shapers like caveman — opposite objectives.

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
- `CLAUDE.md` — operating rules for AI agents working in this repo (fresh-docs mandate + plugin design rules).
- `docs/OFFICIAL-DOCS.md` — canonical index of the official Claude Code doc pages the mandate sends you to.

## Official documentation

This repo tracks policy and wiring only; authoritative behavior lives in the official docs, which must
be read fresh rather than recalled. Start at the
[Claude Code plugins guide](https://code.claude.com/docs/en/plugins).

## License

[MIT](LICENSE).
