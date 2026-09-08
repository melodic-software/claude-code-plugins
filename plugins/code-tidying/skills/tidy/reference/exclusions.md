# Exclusions reference

Three exclusion lists gate every tidy run, in order of how they apply:

1. **GLOBAL HARD EXCLUSIONS** — not touched, regardless of lane. Applies to every run, and the path entries are lifted only through the section 4 channels.
2. **GLOBAL SOFT EXCLUSIONS** — technically allowed but an autonomous run is not equipped to verify changes safely. Touch only with explicit user override.
3. **SELF-UPDATE EXTRA HARD** — additional restrictions that ONLY apply when the `self-update` lane is the active lane. Applied on top of the global lists.

Section 4 then defines the three channels that **lift** the section 1 path entries for a run, an operator, or a repository, and names what no channel lifts.

These lists are the canonical universal baseline; the consuming project's own instructions extend them.

---

## 1. GLOBAL HARD EXCLUSIONS

The GLOBAL HARD list gates every lane. A tidying that would touch any entry is automatically out of scope — file an issue if drift exists, and clean-exit the run if the only candidates fall in this list.

### Agent & enforcement configuration (universal)

Claude Code surface — `.claude/**` in full: the whole directory is agent surface — settings, agents, hooks, rules, routines, tidy-lanes (the consumer's own lane definitions — the lane contract cannot tidy itself), and any settings-wired hook or bootstrap script that lives there. Any script wired as a hook command **anywhere** is excluded wherever it lives, because a hook command may point outside `.claude/`. Hook wiring is not only the project settings scope (`.claude/settings.json`, `.claude/settings.local.json`): a plugin's `hooks/hooks.json` and a skill's or agent's frontmatter `hooks` block wire hook commands too, and a script reached through either is excluded on the same footing. `.mcp.json`. Other agents' config bundles (e.g. `.codex/**`, `.cursor/**`) — a tidy must not mutate another agent's behavior. GitHub surface — `.github/workflows/**`, `.github/actions/**`, `.github/CODEOWNERS`, `.github/dependabot.yml`. Local git-hook chain — the hook manager's config and script directories (e.g. `lefthook.yml`, `.lefthook/**`, `.husky/**`, `.pre-commit-config.yaml`). Cross-ecosystem lint / style config — `.editorconfig`, `.shellcheckrc`, and their per-tool equivalents.

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
- Applies to every `skills/*/SKILL.md` in this plugin, including skills added later

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

## 4. Overriding the HARD path list

Everything **path-based** in section 1 is overridable. A path exclusion is a default, not a law: it exists because an autonomous hunt has no reason to be in that file, which is a different claim from "the user may not ask for it". `/code-tidying:dissolve-comments override ruff.toml` is a legitimate request, and a list that cannot express it forces the user to edit by hand what the skill exists to do.

Three channels lift it, each owning one row of the config-ownership table in `docs/PLUGIN-PHILOSOPHY.md` "Configuration ownership and scope".

| Channel | Table row | Form | Reach |
|---|---|---|---|
| `override` argument | Invocation-specific choice | A bare flag token in the skill's argument grammar | The named target of that one run |
| `hard_exclusions` userConfig | Personal or administrator scalar | `enforce` (default) or `advisory` | Every run this operator makes, until changed |
| `.claude/code-tidying/exclusion-overrides.md` | Tracked repository convention | A tracked file of root-relative globs | Every run in that repository, for every operator |

### The `override` argument

Bare token `override`, spelled the way `safe`, `docs`, and `dry-run` are. It lifts the HARD **path** list for the run's resolved target and nothing wider. Always honored when the session is interactive, because an interactive user is present to see what the run reports.

Interactivity gates only `tidy`. On `dissolve-comments` and `batch-simplify` the token is honored in a non-interactive run as well, because the target is already the enumeration: the user typing `override <path>` named the file, so there is nothing further to enumerate and take a go-ahead on. The `tidy` gate below exists because a lane of globs is not a named file.

Its reach is the run's target, and the three skills' targets are not the same size. On `dissolve-comments` and `batch-simplify` the target is a named path or a resolved diff, and the user typing the token has the file in view. On `tidy` the target is a whole lane of globs, so the same token lifts the list across every file the lane matches, and the run's output is an autonomous PR rather than a working-tree diff the user reads first.

That difference gets a gate rather than a caveat. On `tidy`, `override` **enumerates before it edits**: after Phase D's hunt, the run lists the specific HARD paths it now intends to touch and takes a go-ahead on that list, exactly as `batch-simplify`'s repo mode confirms its inventory. An interactive user answers. A non-interactive run has nobody to answer, so it does not proceed on a blanket token: it reports the enumerated list and continues with those candidates dropped, leaving the rest of the lane's tidyings to ship normally. The operator then re-runs interactively or puts the durable entries in the repository overrides file, which is the channel built for a standing decision. Combining `override` with `dry-run` produces that enumeration and nothing else, which is the cheap way to see the list first.

The other two skills need no such gate: their target is already the enumeration.

To operate on a directory genuinely named `override`, spell it `./override`.

### The `hard_exclusions` userConfig option

`enforce` (default) keeps the section 1 path list blocking, which is the behavior every earlier release shipped. `advisory` reports each HARD path match and never blocks, so the operator's standing posture is "tell me, then proceed". It is a scalar, not a list: `userConfig` types are `string`, `number`, `boolean`, `directory`, and `file`, so a per-path list cannot live there and belongs in the repository file below. Any value outside the two is read as `enforce`.

### The consumer-declared overrides file

`${CLAUDE_PROJECT_DIR}/.claude/code-tidying/exclusion-overrides.md`, tracked, optional, and absent by default. It is the exact mirror of **Consumer-declared protections** above: protections *add* paths to HARD, overrides *subtract* them.

Shape: a `## Overrides` heading followed by one fenced block, one root-relative glob per line, `#` starting a comment line. Anything outside that block is prose for the humans reading it and is not parsed.

````markdown
## Overrides

```text
# The team hand-reviews every lint-config diff, so tidying may reach them.
ruff.toml
.editorconfig
```
````

Rules the file obeys:

- **Root-relative only.** Reject an absolute path and any entry containing `..`; report the rejected line rather than resolving it.
- **It only subtracts.** A glob here can lift a section 1 path entry. It cannot add one, and it cannot lift anything on the non-overridable list below.
- **It cannot lift itself.** The file sits inside `.claude/**`, which section 1 protects, and a glob matching the overrides file or the tidy-lanes beside it is rejected with that reason. Editing the switch is the operator's job, never a run's: a mechanism that can widen its own reach is not a mechanism. Lifting the rest of `.claude/**` is allowed, and the run reports the lifted set path by path.
- **A same-repo collision resolves toward the protection.** When a glob here matches a path the same repository's `CLAUDE.md` or `.claude/rules` declares protected, the protection wins and the run reports the conflict by naming both declarations. Two tracked team statements disagree, and a plugin does not get to pick a winner silently.

### Precedence

The three channels only ever loosen, so precedence resolves per path rather than per run. For each candidate path, in order:

1. The `override` argument named this run's target → **lifted**.
2. A glob in the repository overrides file matches → **lifted**, unless a consumer-declared protection also matches.
3. `hard_exclusions` is `advisory` → **lifted, and reported as advisory**.
4. Otherwise → **enforced**, dropped before triage exactly as before.

Argument beats repository file beats userConfig. Nothing here reaches a path that was never on the section 1 path list; every channel is subtraction from one fixed set.

### Reviewability is the price

A run that lifted anything reports, for every lifted path, the channel that lifted it. A lifted path that edits without saying so is the failure this whole section is trying not to create, so the report line is not optional and a run that cannot produce it enforces instead.

### What stays HARD under every channel

Not overridable, in any channel, at any value:

- **The behavioral guards** in section 1 (`Behavioral changes`). DB migrations against real instances, breaking API changes, HTTP route signature changes, MCP tool schema changes. These are not paths, so there is nothing for a path override to lift: they are the skills' structure-only contract, and a run that changes behavior is out of contract wherever the file sits.
- **The work-tracking exclusions** in section 1. Claimed items, items with an open PR, blocked or deferred items. These are tracker state, not paths, and lifting them means colliding with another agent's work.
- **Section 3, SELF-UPDATE EXTRA HARD.** The self-update lane's guard against an autonomous run rewriting this plugin's own contract surface, including this section. A mechanism that can switch itself off is not a mechanism.
- **The override machinery itself**, wherever it lives: this file, the consumer's `.claude/code-tidying/exclusion-overrides.md`, and the `.claude/tidy-lanes/` definitions beside it. Same reason. A run may be granted the rest of `.claude/**`; it is never granted the switch that grants it.
- **The GLOBAL SOFT list** in section 2, which is not a path list and already has its own explicit-user-override rule.

---

## How to apply these lists during a run

1. **Phase A (Triage)** — re-read this file AND the consuming project's declared protections. Resolve the three override channels in section 4 and write down the lifted set before hunting. Note the active lane's lane-specific extra exclusions on top of these globals.
2. **Phase D (Hunt)** — when classifying candidates, drop anything that touches a GLOBAL HARD path that section 4 did not lift. Move SOFT candidates to the deferred-items list unless the user has explicitly authorized them in interactive mode.
3. **Phase E (Implement)** — every Edit / Write call has the file path validated against the HARD list above, minus the lifted set. If a tidying would require touching an unlifted HARD file, abort the tidying and continue with the next candidate. Stage with `git add <path>` only, never `-A` or `.`.
4. **Report** — every lifted path is named in the run's report with the channel that lifted it (section 4, "Reviewability is the price").
5. **Self-update specifically** — `lanes/self-update.md` summarizes the EXTRA HARD list; this file is the canonical version, so the two are reconciled here when they differ. Section 4 does not reach it.

If a HARD-list entry is wrong for a whole repository (the file moved, the concern is stale), the durable fix is the overrides file in section 4 or a deliberate user-driven edit here, NOT an autonomous tidying that "discovers" the entry should change.
