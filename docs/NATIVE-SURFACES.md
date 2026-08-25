# Native surfaces registry

Generated view over the native-overlap store. The block between the markers below is rendered from
`docs/native-surfaces/records.json` by
`plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py generate` and kept in sync by CI
— **never hand-edit it**. Verdicts, evidence, and recheck triggers are edited in the store; this
file is output.

Every verdict here is a human's. Rows are recorded per overlap between a native Claude Code surface
and a component in this repository, and each one carries the observable event that obliges
re-deriving it. Availability is never asserted: an observation record says what was seen, where,
and when — see [`docs/conventions/native-references/`](conventions/native-references/README.md).

<!-- native-surfaces:start -->

## Summary

| Lane | Rows | Baked | Verdicts |
|---|---|---|---|
| Built-in CLI commands | 1 | 0 | complementary 1 |
| Bundled skills | 6 | 1 | complementary 6 |
| Plugin-backed built-ins | 1 | 0 | complementary 1 |
| Session-provided skills (observation-only) | 1 | 0 | defer 1 |

## Built-in CLI commands

### `export` → `session-flow:clean-stop`

- **Verdict:** `complementary` — No component duplicates /export and none may invoke it: built-ins are user-invoked only, and the command is confirmed unavailable headless. clean-stop, handoff (prompt-only path), and retro instead suggest that the user run it at session-end moments, because transcripts are retention-swept and the conversation otherwise has no durable artifact. The native surface does the exporting; the skills only name the moment and a destination convention (<memory_dir>/exports/). Verdict recorded per the user-approved export-session-flow Brief (PR #3355).
- **Native surface:** `export` (built-in command; markers: none)
- **Our component:** `session-flow:clean-stop` (skill)
- **Evidence:**
  - probed on the live v2.1.241 binary 2026-08-24: `claude --bare -p "/export <path>"` returned `/export isn't available in this environment.` and wrote no file, so the command is an interactive-terminal surface
  - documented at code.claude.com/docs/en/commands.md: /export renders the current conversation as plain text to clipboard or a file (optional filename argument), no format or redaction flags
  - output written to user paths sits outside the cleanupPeriodDays retention sweep (path-scoped to ~/.claude), which is the durability property the suggestions exist for
  - suggestion sites: plugins/session-flow/skills/clean-stop/SKILL.md (durability sweep), handoff/SKILL.md (prompt-only close), retro/SKILL.md (post-chain-coverage offer); all body text, presence-gated with the canonical token, none baked into a description or Boundary section
- **Observation:** live-roster — probed on the live v2.1.241 binary in a Linux container (headless form unavailable; interactive form documented but not observed here); one environment, one day (2026-08-24)
- **Recheck trigger:** a Claude Code release note or docs change adds an /export format/redaction flag, a headless or programmatic form, or an official conversation-sharing surface; any of these reopens whether suggestion-only is still the right integration shape (verified 2026-08-24)
- **Baked:** description phrase no · Boundary section no

## Bundled skills

### `code-review` → `review:code-review`

- **Verdict:** `complementary` — Same object, different invocation surface. The bundled skill is a session-driven review of the current diff or a named PR, with mutating flags (--fix writes the working tree, --comment posts to the PR). review:code-review is a non-interactive CI lane a reusable workflow invokes for one pull request, deliberately scoped out of security when a security lane exists. Neither replaces the other: a CI lane cannot be typed into a session, and the session surface has no workflow contract.
- **Native surface:** `code-review` (bundled skill; markers: none)
- **Our component:** `review:code-review` (skill)
- **Evidence:**
  - `code-review` present in the extraction as bundled-skill
  - aliases: review
  - native description: Review the current diff or a PR for bugs and cleanups
  - our description: CI code-review lane for a GitHub pull request — high-signal correctness and maintainability findings only, scoped out of security when a security lane exists
  - the review plugin already documents this overlap organically in plugins/review/skills/quality-gate/context/pr.md's Boundary section, naming the bundled command, the marketplace plugin, and the managed service as three distinct surfaces
- **Observation:** extraction — extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded — counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release changes the bundled `code-review` skill's roster entry, its `review` alias, or its invocation mode — the alias was re-pointed at 2.1.220 and the alias-under-shadowing fix landed at 2.1.233, so this pair has moved twice in one quarter (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure — it is the best available routing surface, not a guaranteed one

### `doctor` → `claude-ops:audit-install-state`

- **Verdict:** `complementary` — Bundled `doctor` is the quick native health-and-fix pass over an installation — and it offers to fix, which puts it outside the read-only contract audit-install-state holds. audit-install-state is the deep read-only inventory of the install tree: every file classified, product-managed retention separated from genuinely unmanaged state, filename schemes resolved before any liveness check, and a deliberate-or-experimental state detected before anything is called stale. Prefer the native pass for a fast check; ours when the question is what is actually in the tree and what nothing manages.
- **Native surface:** `doctor` (bundled skill; markers: gated)
- **Our component:** `claude-ops:audit-install-state` (skill)
- **Evidence:**
  - `doctor` present in the extraction as bundled-skill
  - markers: gated
  - aliases: checkup
  - native description: Health-check your setup and fix issues: installation, unused extensions, duplicated or bloated memory files, slow hooks, updates, permissions
  - the native surface offers to fix; audit-install-state is report-only by contract and never writes to the target tree
  - shared listing budget measured at ~13.0x over the documented 8,000-char default across 153 listing-eligible skills (check-listing-budget.sh, 2026-08-23), so the baked phrase is the best available routing surface, not a guaranteed one
- **Observation:** extraction — extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded — counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release changes `/doctor`'s status as a bundled skill or its gating switch — it became a bundled skill at 2.1.205, which retargeted DISABLE_DOCTOR_COMMAND, and it is the one bundled skill `disableBundledSkills` does not remove (verified 2026-08-23)
- **Baked:** description phrase yes · Boundary section yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure — it is the best available routing surface, not a guaranteed one

### `doctor` → `claude-ops:audit-performance`

- **Verdict:** `complementary` — Same native surface, a different one of our lanes. audit-performance is a timed diagnostic capture taken at the moment something feels slow — CLI version, retention-sweep health, a timed stat-walk standing in for the product's own sweep cost, session and plugin-fleet counts, a process census — interpreted against a bundled known-issues reference. Bundled `doctor` reports health and offers fixes; it does not capture a timed slowness profile. Registry-row only: the routing line for this pair lives on audit-install-state, which owns the shared surface description for the plugin.
- **Native surface:** `doctor` (bundled skill; markers: gated)
- **Our component:** `claude-ops:audit-performance` (skill)
- **Evidence:**
  - `doctor` present in the extraction as bundled-skill
  - markers: gated
  - native description: Health-check your setup and fix issues: installation, unused extensions, duplicated or bloated memory files, slow hooks, updates, permissions
  - our description: read-only slowness-diagnostic capture run AT THE MOMENT the machine or a session feels slow, before restarting or deleting anything
- **Observation:** extraction — extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded — counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release gives `/doctor` a timed or profiling mode, or changes its status as a bundled skill (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure — it is the best available routing surface, not a guaranteed one

### `run` → `testing:run-e2e`

- **Verdict:** `complementary` — The bundled skill answers 'did this change work when I ran the app'; run-e2e drives named UI and API flows, captures evidence (screenshots, responses, logs), and carries a non-UI smoke playbook for libraries, MCP servers, hooks, and scripts — surfaces that have no app to launch. Prefer the native surface for the quick look; ours where the verification has to be reproducible or the target is not an app.
- **Native surface:** `run` (bundled skill; markers: none)
- **Our component:** `testing:run-e2e` (skill)
- **Evidence:**
  - `run` present in the extraction as bundled-skill
  - native description: Launch this project's app to see your change working
  - our description: End-to-end live app verification — check prerequisites, start the app, drive UI/API flows, and capture evidence; includes a non-UI smoke-test playbook
  - the non-UI smoke lane has no native counterpart in this extraction
- **Observation:** extraction — extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded — counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release changes the bundled `run` skill's roster entry or invocation mode, or gives it an evidence-capture or non-app target mode (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure — it is the best available routing surface, not a guaranteed one

### `simplify` → `code-tidying:batch-simplify`

- **Verdict:** `complementary` — Scale is the whole difference. The bundled skill handles the change in front of it; batch-simplify fans the same job across a time- or branch-scoped window of changed files, grouped by ecosystem and dependency order, for the catch-up case after a multi-session sprint. Its description already sends single-file cleanup to the native surface.
- **Native surface:** `simplify` (bundled skill; markers: none)
- **Our component:** `code-tidying:batch-simplify` (skill)
- **Evidence:**
  - `simplify` present in the extraction as bundled-skill
  - native description: Clean up the changed code without changing behavior
  - our description already carries `Skip for single-file cleanup — use /simplify instead`
  - seeded rationale: same cleanup job at batch scale across many files
- **Observation:** extraction — extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded — counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release gives the bundled `simplify` skill a multi-file or time-window argument form, which would collapse this pair's only distinction (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure — it is the best available routing surface, not a guaranteed one

### `simplify` → `code-tidying:tidy`

- **Verdict:** `complementary` — Different trigger, not a different job. The bundled skill refines the code a change already touched; tidy proactively hunts unfiled structural drift across a rotated, glob-scoped lane and ships one structure-only PR per invocation. tidy's own description already routes current-diff work away to the native surface, which is the routing this row records rather than replaces.
- **Native surface:** `simplify` (bundled skill; markers: none)
- **Our component:** `code-tidying:tidy` (skill)
- **Evidence:**
  - `simplify` present in the extraction as bundled-skill
  - native description: Clean up the changed code without changing behavior
  - our description already carries `Skip when: /simplify refines the current diff`
  - seeded rationale: both clean up code without changing behavior
- **Observation:** extraction — extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded — counts are floors) (2026-08-23)
- **Recheck trigger:** a Claude Code release adds, removes, or changes the invocation mode of the bundled `simplify` skill, or the skill gains a lane-scoped mode that overlaps tidy's proactive hunt (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure — it is the best available routing surface, not a guaranteed one

## Plugin-backed built-ins

### `security-review` → `review:security-review`

- **Verdict:** `complementary` — The native side is not a bundled skill at all — the extraction reports it under `plugin_backed`, backed by the `security-review` plugin — and it runs in-session over the change at hand. review:security-review is the CI lane a reusable workflow invokes for a pull request, targeting logic, trust-boundary, and Actions findings static analysis misses. Reading the wrong extraction key is the failure this row exists to prevent: under `builtin_commands` the surface looks absent.
- **Native surface:** `security-review` (plugin-backed built-in; markers: none)
- **Our component:** `review:security-review` (skill)
- **Evidence:**
  - `security-review` present in the extraction as plugin-backed-builtin
  - the extraction's `plugin_backed` map reports {"security-review": "security-review"}; the name appears in neither `builtin_commands` nor `bundled_skills`
  - our description: CI security-review lane for a GitHub pull request — logic, trust-boundary, and Actions security findings static analysis misses
- **Observation:** extraction — extracted from binary v2.1.232 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (integrity: degraded — counts are floors) (2026-08-23)
- **Recheck trigger:** an extraction stops reporting `security-review` under `plugin_backed` — it moves into the bundled-skill or built-in-command lane, or its backing plugin name changes (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure — it is the best available routing surface, not a guaranteed one

## Session-provided skills (observation-only)

### `morning` → `claude-ops:morning-brief`

- **Verdict:** `defer` — Undetermined, and deliberately so. `morning` was observed in a session roster, not in any binary extraction, so the only evidence available is one environment's roster on one day — not a basis for a routing line shipped to every consumer. The overlap is real enough to record and too thin to rule on: nothing is known about what the session-provided skill reads, whether it is gh-based, or whether it exists outside the surface it was seen on. Observation-only, never baked, until an in-session capture protocol exists.
- **Native surface:** `morning` (session-provided skill; markers: none)
- **Our component:** `claude-ops:morning-brief` (skill)
- **Evidence:**
  - `morning` is absent from this extraction — absence from the extraction is a statement about the extraction, not the product
  - observed in this repository's cloud session roster on 2026-08-23, alongside other session-provided skills (docx, pdf, pptx, xlsx, design, artifact-*) that the local-CLI bundled roster does not carry
  - our description: prints the operator's read-only morning view for the current GitHub repo in one pass — queue-label counts, merge-ready PRs, parked decisions, loop-lane telemetry freshness
- **Observation:** live-roster — observed in a Claude Code cloud session's own skill roster; one environment, one day, no second observation (2026-08-23)
- **Recheck trigger:** an in-session roster capture protocol lands and can observe this surface repeatably, or `morning` appears in a binary extraction's bundled-skill set (verified 2026-08-23)
- **Baked:** description phrase no · Boundary section no

<!-- native-surfaces:end -->
