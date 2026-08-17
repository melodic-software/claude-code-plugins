# Agent-consumed instruction-file surfaces — verified enumeration

Durable adaptation of the lane-7 research run (2026-08-17, docs current at Claude Code v2.1.233;
full evidence table, fetch log, and coverage ledger lived in the topic's memory slice, disposable
per session). Feeds the scope statement and reference table of `docs-hygiene:write-for-agents`
([#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909); Brief:
[`../PLAN.md`](../PLAN.md)). Claude-side rows are harness-behavior claims verified against
official docs fetched during the run; re-verify against current docs when adapting into the
skill's reference file.

## Part 1 — Claude Code surfaces (25, official-docs-verified)

| # | Surface | Path pattern | When it loads |
|---|---------|-------------|---------------|
| 1 | Managed-policy CLAUDE.md | OS-specific managed dirs (e.g. `/etc/claude-code/CLAUDE.md`) | Session start, before all other scopes; cannot be excluded |
| 2 | Managed `claudeMd` settings key | `managed-settings.json` (+ `managed-settings.d/` drop-ins) | Session start, managed precedence |
| 3 | User CLAUDE.md | `~/.claude/CLAUDE.md` | Session start, full |
| 4 | Project CLAUDE.md | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Session start; re-injected after `/compact` |
| 5 | CLAUDE.local.md | `./CLAUDE.local.md` (also beside ancestor CLAUDE.md) | Session start, after same-level CLAUDE.md; still current, not deprecated |
| 6 | Ancestor CLAUDE.md | every dir from filesystem root down to cwd | Session start, root→cwd; excludable via `claudeMdExcludes` |
| 7 | Nested/subdirectory CLAUDE.md | `<subdir>/CLAUDE.md` below cwd | ON-DEMAND when Claude reads files there; NOT re-injected after `/compact` until next matching read |
| 8 | `--add-dir` CLAUDE.md | added dirs' CLAUDE.md/rules | Session start only with `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` |
| 9 | AGENTS.md | **not read natively** (CHANGELOG 0 mentions through v2.1.233) | Only via `@AGENTS.md` import, symlink, `/init` (`CLAUDE_CODE_NEW_INIT=1`), `/import` (v2.1.213+) |
| 10 | Project rules | `.claude/rules/**/*.md` (recursive, symlinks followed) | No `paths:` → session start; with `paths:` globs → on-demand on matching file read |
| 11 | User rules | `~/.claude/rules/*.md` | Session start, before project rules (lower priority) |
| 12 | `@` imports | `@path` in CLAUDE.md/rules; max 4 hops; skipped in code spans/fences | Expanded at launch with the importer; external imports gate behind one-time approval (project scope) |
| 13 | Auto-memory index | `~/.claude/projects/<project>/memory/MEMORY.md` (relocatable via `autoMemoryDirectory`) | Session start: first 200 lines or 25KB |
| 14 | Auto-memory topic files | same dir, `*.md` | On-demand only |
| 15 | Skills | personal `~/.claude/skills/`, project `.claude/skills/` (cwd + parents to repo root), plugin `skills/`, enterprise, synced, nested | Listing metadata every turn (1,536-char cap/skill); body on invocation or model trigger; `paths:` gates auto-load |
| 16 | Commands (legacy) | `.claude/commands/`, `~/.claude/commands/`, plugin `commands/` | On invocation; merged into skills mechanism; skills win collisions |
| 17 | Subagent definitions | managed > `--agents` > `.claude/agents/` > `~/.claude/agents/` > plugin `agents/` | `description` at delegation time; body becomes subagent system prompt at spawn; subagents load CLAUDE.md hierarchy + rules at their own startup |
| 18 | Subagent persistent memory | `agent-memory/<agent>/` (user/project/local) | First 200 lines/25KB of the agent's MEMORY.md into its system prompt at spawn |
| 19 | Preloaded skills in subagents | agent frontmatter `skills:` | Full body injected at subagent startup |
| 20 | Output styles | user/project/managed/plugin `output-styles/` | Session start when selected via `outputStyle`; modifies system prompt |
| 21 | Workflows | `.claude/workflows/`, `~/.claude/workflows/`, plugin `workflows/` | Startup; each file becomes a `/<name>` command |
| 22 | Plugin instruction surfaces | plugin `skills/`/`commands/`/`agents/`/`workflows/`/`output-styles/`/`hooks/` | Component-dependent; **plugin-root CLAUDE.md is NOT loaded** |
| 23 | Skills-directory plugins | `.claude-plugin/plugin.json` inside a skill folder | Loads as plugin `<name>@skills-dir` |
| 24 | Hook-carried instruction text | settings/plugin/frontmatter hooks; `prompt`/`agent` types; `additionalContext` returns | On lifecycle events; `additionalContext` capped 10,000 chars |
| 25 | `--append-system-prompt` | CLI flag | Per invocation, appended to system prompt |

Cross-cutting semantics the skill should teach: scope load order managed → user → project →
local; nested CLAUDE.md and path-scoped rules do NOT survive `/compact` re-injection; block HTML
comments are stripped from CLAUDE.md before injection; `/context` and `/memory` are the
observability commands; `InstructionsLoaded` hook fires per loaded memory file; CLAUDE.md is
context, never enforcement (hooks + managed deny are the enforcement layer); official size
guidance <200 lines per CLAUDE.md.

## Part 2 — Other-ecosystem analogues (13 conventions)

| Convention | File(s) | Auto-read |
|---|---|---|
| AGENTS.md open standard (Linux Foundation-stewarded) | `AGENTS.md` root + nested, nearest wins | Native in Codex, Cursor, Copilot agent, Gemini CLI (config), Windsurf, Zed, Roo, others — NOT Claude Code |
| Cursor rules | `.cursor/rules/*.mdc` (+ nested); legacy `.cursorrules` deprecated | Per-rule types: Always / Auto Attached (globs) / Agent Requested / Manual; also reads AGENTS.md + CLAUDE.md |
| GitHub Copilot | `.github/copilot-instructions.md`; `.github/instructions/**.instructions.md` (`applyTo:` globs); AGENTS.md (agent) | Auto-added to matching requests |
| Gemini CLI | `~/.gemini/GEMINI.md`; workspace + ancestors; JIT subdir scan; `@` imports; `context.fileName` configurable | Concatenated into every prompt |
| Windsurf | `global_rules.md`; `.windsurf/rules/` (newer docs prefer `.devin/`); legacy `.windsurfrules`; AGENTS.md | Per-rule `trigger:` manual / always_on / model_decision / glob |
| Cline | `.clinerules` file or folder; global `~/Documents/Cline/Rules/` | Appended to system prompt; workspace wins |
| Roo Code | `~/.roo/rules/`, `.roo/rules/` (+ per-mode variants); `.roorules` fallback | Auto-loaded, workspace wins |
| Aider | `CONVENTIONS.md` | **NOT auto-read** — explicit `/read` / `--read` / `.aider.conf.yml` only |
| Agent Skills standard (agentskills.io) | `<name>/SKILL.md` folders | Metadata-first progressive disclosure. The spec defines the folder format only; `.agents/skills/` (project) + `~/.agents/skills/` (user) is the shared cross-tool DISCOVERY convention — Codex CLI (layered lookup incl. `$REPO_ROOT/.agents/skills`, `$HOME/.agents/skills`, `/etc/codex/skills`), Cursor (also `.cursor/skills/`), Gemini CLI, VS Code Copilot, Zed. Claude Code notably uses its own `~/.claude/skills/`/`.claude/skills/` paths; whether it also reads `.agents` paths is a lane 9 (#2911) verification item |
| OpenAI Codex | AGENTS.md root + nested | Native (standard's originator) |
| Zed | `.rules` (accepts `.cursorrules`, AGENTS.md, CLAUDE.md); skills `~/.agents/skills/` | Auto-included; Rules Library → Skills in v1.4.0 |
| JetBrains Junie | `.junie/guidelines.md` | Auto-read during generation |
| Amazon Q Developer | `.amazonq/rules/*.md` | Auto-loaded on first interaction |

Notable interop fact: Claude Code's own `/init` reads `.cursor/rules/`, `.cursorrules`,
`.github/copilot-instructions.md`, and (with `CLAUDE_CODE_NEW_INIT=1`) `AGENTS.md`,
`.devin/rules/`, `.windsurf/rules/`/`.windsurfrules`, `.clinerules` — Anthropic's docs
corroborate the competitor paths themselves.

## Confidence caveats (recorded decisions from the research's open questions)

- Claude-side rows corroborate mostly within the single Anthropic publishing pool. **Accepted**:
  the effort's claim ladder requires verification against current official docs, not
  multi-publisher independence, for harness-behavior claims.
- Cursor / Copilot / Windsurf / Cline rows are MEDIUM confidence (vendor doc hosts egress-blocked
  in the research container; sourced via domain-filtered search + Anthropic's `/init` interop
  list as path corroborator). **Accepted for their purpose** — ecosystem awareness rows, not
  harness claims. Optional implementation-time task: re-fetch the four vendor pages from an
  unrestricted network before finalizing the skill's reference table.
- Per-vendor changelog recency checks for Part 2 were deliberately scoped out (no-deep-dive
  bound). Accepted.
- Goose `.goosehints`: UNVERIFIED candidate (all fetch paths blocked or 404 in the research
  container) — excluded from the table above; re-check at implementation if ecosystem coverage
  matters there.
- `.agents/skills/` cross-tool convention (corrected 2026-08-17, user-raised): confirmed
  directionally from multiple independent secondary pools + Cursor's own docs surfaced via
  search (vendor hosts egress-blocked here) — MEDIUM; the spec repo itself confirms it defines
  no directory locations. The Claude-Code-reads-`.agents`-paths question stays with #2911's
  harness-claims bundle.
- Fresh-context verifier catches (recorded 2026-08-17): Roo and Aider rows are single-pool
  (vendor primary only — accepted on the same vendor-authority basis, now flagged); the AGENTS.md
  "nearest wins" nested-precedence detail is thinly corroborated (standard's FAQ only); the
  Codex/Zed/Junie/Amazon Q rows are MEDIUM. None of these are harness claims for our skill —
  treat all Part 2 semantics as awareness-grade until re-fetched from an unrestricted network.
