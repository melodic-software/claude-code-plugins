# Exclusions reference

Three exclusion lists gate every tidy run, in order of how they apply:

1. **GLOBAL HARD EXCLUSIONS** — never touched, regardless of lane. Applies to every run.
2. **GLOBAL SOFT EXCLUSIONS** — technically allowed but an autonomous run is not equipped to verify changes safely. Touch only with explicit user override.
3. **SELF-UPDATE EXTRA HARD** — additional restrictions that ONLY apply when the `self-update` lane is the active lane. Applied on top of the global lists.

**Re-read this file at the start of every tidy run** — memory of the lists across sessions is unreliable. The lists below are the canonical universal baseline; the consuming project's own instructions extend them.

---

## 1. GLOBAL HARD EXCLUSIONS

The GLOBAL HARD list gates every lane. A tidying that would touch any entry is automatically out of scope — file an issue if drift exists, and clean-exit the run if the only candidates fall in this list.

### Agent & enforcement configuration (universal)

Claude Code surface — `.claude/settings.json`, `.claude/settings.local.json`, `.claude/agents/**`, `.claude/hooks/**`, `.claude/rules/**`, `.claude/routines/**`, `.claude/tidy-lanes/**` (the consumer's own lane definitions — the lane contract cannot tidy itself), `.mcp.json`. Other agents' config bundles (e.g. `.codex/**`, `.cursor/**`) — a tidy must not mutate another agent's behavior. GitHub surface — `.github/workflows/**`, `.github/actions/**`, `.github/CODEOWNERS`, `.github/dependabot.yml`. Local git-hook chain — the hook manager's config and script directories (e.g. `lefthook.yml`, `.lefthook/**`, `.husky/**`, `.pre-commit-config.yaml`). Cross-ecosystem lint / style config — `.editorconfig`, `.shellcheckrc`, and their per-tool equivalents.

### Consumer-declared protections

The consuming project's own `CLAUDE.md` / `.claude/rules` may declare additional protected paths — read them during Phase A and treat every declared protection as HARD. Typical examples: central build/analyzer infrastructure (`Directory.Build.props`, `Directory.Packages.props`, banned-API lists, custom analyzer source trees), solution/workspace files and SDK pins, architecture-test suites whose rules are behavioral, and bootstrap/install scripts.

### Security & branch protection

Branch-protection rule changes — out of scope for any lane. Security workflows + secret-scanning / static-analysis config — `.github/workflows/**` is HARD by path globally; called out separately for emphasis. Secret-pattern detection rules and their fixtures.

### Behavioral changes (regardless of file location)

These are NOT path-list entries (they're not glob-matchable) — they apply as agent-judgment guards regardless of which path the edit targets:

- DB migrations against real instances (autonomous runs have no ephemeral test DB)
- Breaking API changes — any change to public symbols that downstream consumers depend on
- HTTP route signature changes — endpoint URL, method, request/response DTO shapes
- MCP tool schema changes — tool name, input schema, output schema, behavior

### Work-tracking exclusions

- Work items another agent has already claimed
- Work items with an open PR linked
- Work items labeled blocked or deferred

---

## 2. GLOBAL SOFT EXCLUSIONS

The GLOBAL SOFT list identifies areas where edits are technically allowed, but an autonomous run cannot verify changes in them safely. Manual override (a lane run with explicit user supervision) is the only acceptable mode for SOFT-excluded areas. Entries are concept tokens — classify candidates against them during Phase D.

### Stack-agnostic concepts

- `browser-tests` — any UI rendering / interaction that CLI-only verification cannot validate
- `interactive-auth-flows` — OAuth redirects, OIDC handshakes, session-cookie issuance. Needs a real browser session and a running identity provider
- `db-migrations-against-real-instances` — the boundary between a structural ORM migration and a behavioral schema change is judgment-dependent (also listed under HARD; emphasized here)
- `ide-only-flows` — designer-generated code, resource-file wiring with IDE extensions, anything that only runs inside a specific IDE

### Consumer-declared SOFT areas

The consuming project's instructions may declare additional areas its verification cannot cover — orchestration hosts whose startup ordering isn't CLI-verifiable, browser-rendered UI frameworks, identity/auth wiring, tests that need a local database instance, telemetry-pipeline ordering. Read them during Phase A and route candidates in those areas to the deferred-items list unless an interactive user explicitly overrides.

---

## 3. SELF-UPDATE EXTRA HARD

This list applies ONLY when the active lane is `self-update`. The self-update lane operates on this plugin's own files in a maintainer working-tree checkout, and these EXTRA HARD entries protect the skill's CONTRACT SURFACE from being modified by an autonomous run of itself.

If during a self-update run you find drift in any of the following, **clean exit, NO PR, report what was found to the user.** Do NOT file an issue (the "file deferrals" pattern is for in-scope work). The user reviews and decides.

### Frontmatter (entire YAML block of every skill file)

- `name`, `description`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `model`, `effort`, `paths`, `hooks`, `context`, `agent`, `shell`
- Applies to both of this plugin's SKILL.md files AND any future skill files that grow frontmatter

### Safety-mechanism content

- The HARD / SOFT exclusion lists (this file) — section headings, bullet items, section ordering. The safety net cannot tidy itself
- The Action Router section of `SKILL.md` — the argument grammar table is a contract with users
- The Workflow phase list in `SKILL.md` — phase names and order are a contract; renumbering or renaming changes behavior
- The Lane catalog + lane-resolution-order sections in `SKILL.md` — the consumer lane contract (`.claude/tidy-lanes/`) is a published interface
- Lane file `## Scope` blocks — every lane file's scope globs. Changing scope changes what the lane operates on
- Lane file `## Watch-for patterns` — adding or removing watch-for items changes the lane's behavior
- Lane file `## Lane-specific extra exclusions` — same logic as the global lists; safety contract
- `reference/scope-budget.md` numeric values — the 200/8 target and 400/15 cap are research-derived; changing them needs research, not a tidy

### Out-of-scope work

- Adding new bundled lanes or templates — that's a feature addition (`feat:`), not a tidy
- Removing existing lanes or templates — that's a behavioral change with downstream impact
- Changing Conventional Commits type defaults — affects PR titles, which affect the default branch's history

---

## How to apply these lists during a run

1. **Phase A (Triage)** — re-read this file AND the consuming project's declared protections. Note the active lane's lane-specific extra exclusions on top of these globals.
2. **Phase D (Hunt)** — when classifying candidates, drop anything that touches a GLOBAL HARD path. Move SOFT candidates to the deferred-items list unless the user has explicitly authorized them in interactive mode.
3. **Phase E (Implement)** — every Edit / Write call has the file path validated against the HARD list above. If a tidying would require touching a HARD file, abort the tidying and continue with the next candidate. Stage with `git add <path>` only, never `-A` or `.`.
4. **Self-update specifically** — `lanes/self-update.md` summarizes the EXTRA HARD list at run-time; this file is the canonical version. Trust this list, not memory.

If a HARD-list entry is wrong (the file moved, the concern is stale), the fix is a deliberate user-driven edit — NOT an autonomous tidying that "discovers" the entry should change.
