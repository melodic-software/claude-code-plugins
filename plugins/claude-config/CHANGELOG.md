# Changelog

All notable changes to the `claude-config` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.10.0]

### Added

- **`audit-instructions` checks I12–I14**, extending the existing `reference/criteria.md` catalog
  rather than standing up a second one. Each row carries its must-not-flag cases, and the three new
  official sources (CLI reference, subagents, skills) join the catalog's source list.
- **I12 — stale or misattributed harness-capability claim.** The subject is the product, not the
  model, which separates it from I8. Detection needs an official page stating something incompatible
  with the claim, or a failed reproduction — and each arm is bounded so the check cannot manufacture
  findings. **Documentation silence is not drift**: pages are rewritten and condensed, and this
  repository keeps empirical tests for behaviors the docs never specified. **A reproduction must
  match every stated precondition** — version, OS, setting, account tier, feature flag, launch mode —
  and a failure without them is inconclusive rather than a finding.
- **I13 — prose written on the assumption that an `@path` imported**, on a surface where `@` carries
  no import meaning. The finding is the false premise, not the citation form: an inert `@path` is
  still a legible path, so "follow `@reference/rules.md`" works and flagging it would report a
  working instruction. Remediation rewrites the assertion into an explicit read, because swapping the
  syntax alone leaves the claim false — no citation form imports anything on these surfaces.
- **I14 — an instruction to read a surface the main conversation already loads at startup.** Bounded
  to the root `CLAUDE.md`, the user `CLAUDE.md` at the **resolved** `${CLAUDE_CONFIG_DIR:-~/.claude}`,
  the root `CLAUDE.local.md`, unconditional project rules and managed policy files. Nested
  `CLAUDE.md` and `CLAUDE.local.md` files and path-scoped rules load lazily and are exempt, as is any
  read where **the file is the operation's subject** — the startup copy is a launch-time snapshot, so
  cutting a pre-edit read produces a patch against stale content.
- **`audit-instructions` check I15 — cross-surface instruction conflict.** Two live instructions
  that cannot both be satisfied, where no official layering rule already picks a winner. Scoped by
  routing around the incumbent, and only as far as the incumbent can actually see: a contradiction
  wholly inside the memory surfaces `claude-memory:audit` check C6 discovers — the project-root
  `CLAUDE.md`/`CLAUDE.local.md` and the project `.claude/rules/` tree — is C6's and is not reported
  here, while one reaching a surface C6 never reads (user-scope memory, a nested `CLAUDE.md`), one
  with a side outside the memory layer — a skill body, an agent definition, a prompt-type hook, an
  output style — or any side in the managed-policy tier, is I15's. When `claude-memory` is absent, the
  run says memory-layer contradictions go unchecked and names the skill that performs them.
  Remediation splits by scope and never defaults to deletion: reconcile where both sides are
  operator-owned, report-only against managed policy, route user-scope findings as recommendations.
  Ships six must-not-flag cases — including a co-activation filter, since only the selected output
  style applies to a session and agent definitions execute in separate subagent contexts — plus a
  separate `info` report for shadowed same-named skills and subagents, which are resolved overrides
  rather than conflicts. MCP servers are deliberately outside that report: the skill inventories no
  MCP configuration and routes `.mcp.json` mechanics to `claude-config:audit`. The comparison set is
  resolved before it is compared — `@path` imports expanded and symlinks followed, since imported
  files load at launch and a detector reading only the importing file would compare a different
  surface than the model sees. Expansion is scoped to the surfaces that implement imports —
  `CLAUDE.md` at every scope, `CLAUDE.local.md`, and `.claude/rules/`; an `@path`-shaped reference in
  a skill body or agent definition points at a file read on demand, so it stays an ordinary pointer
  rather than putting never-loaded text into the comparison set. `AGENTS.md` is affirmatively
  excluded and the reason recorded: the memory doc states Claude Code reads `CLAUDE.md`, not
  `AGENTS.md`, so a stock install never loads it, and its content enters only through an import or
  symlink.
- **A dedicated cross-surface conflict lane in `audit-instructions` Phase B.** A conflict is a
  relation between two surfaces, so a per-surface lane cannot see the other side and a lane that
  rescans everything re-derives the same pair in every lane. Per-surface lanes now run their checks
  minus I15, and one cross-surface lane runs I15 alone over the whole resolved inventory, emitting
  each conflict once. Phase A backs it with a read-only inventory tier: org-managed policy (the
  managed `CLAUDE.md`, a `claudeMd` settings value, and managed prompt-type hook text), upstream-owned
  but live instruction text (skill bodies and agent definitions from an enabled plugin's cache,
  managed materializations, and `type: "prompt"` handler text in an enabled plugin's
  `hooks/hooks.json` — effective `enabledPlugins` gates all three alike, since a disabled plugin's
  cache stays on disk while none of its components load), and
  every out-of-scope I15 counterpart — a scope argument narrows which side may produce a finding,
  never which surfaces are read, and the `Arguments` section now says so rather than describing the
  filter as narrowing the inventory. Read-only inventory changes no ownership: those surfaces still
  propose nothing and still route upstream. Prompt-hook text is extracted from
  `.claude/settings.local.json` and managed settings as well as project and user `settings.json`,
  prompt text only, never a command line or secret-bearing value.
- **A no-change representation in the `audit-instructions` report contract.** A finding whose check
  forbids proposing an edit — the I15 managed-policy case, anything routed to an owning repository —
  records `no change proposed` and who owns the resolution instead of a fenced diff, so the per-finding
  diff requirement no longer contradicts the checks that forbid an edit.
- **`audit-instructions` check I16 — definition-site locality.** An instruction governing one named
  thing while living somewhere other than that thing's own definition. A different axis from I3:
  I3 is load *timing*, I16 is *locality*, and an instruction can be correctly deferred and still
  misplaced. `OPINION`-tier, off by default, enabled by `--opinion`, capped at `info`, never applied.
  The destination is constrained to a surface Claude loads: where the subject's definition site is an
  ordinary README or reference file, the proposal colocates the text *and* retains a one-line pointer
  on a loaded surface, so a locality fix never silently drops the behavior the instruction enforced.
- **`audit-instructions` stopping condition on I6 and I8.** Neither carried an a-priori bound, so
  both trimmed without a floor. It withholds a proposal where the instruction guards a
  high-consequence area (safety gate, irreversible action, security boundary, external contract,
  genuine ordering) and reports every withholding. `OPINION`-tier but **enabled by default** with an
  explicit `--no-stopping-condition` opt-out, because it withholds rather than emits — defaulting a
  suppressor off would delete the only bound on two trimming checks.
- **`OPINION`-tier enablement policy in the catalog.** Emitting rules default off, `info`-capped,
  never fix-applied; withholding rules default on; `OPINION`-derived advice inside a backed check
  follows its host's enablement and is labelled inline. Every run reports how many `OPINION` checks
  were available, how many did not run, and the argument that enables them.
- **YAML frontmatter on `reference/criteria.md`** carrying `version` (1.2.0) and `last-updated`,
  replacing the body-prose version line — a contract surface with three parse paths now stamps its
  version machine-readably.

### Changed

- **`audit-instructions` I3 detection now names its real criterion — loaded more broadly than the
  content is relevant.** The old wording said "always-loaded surface", but none of the non-memory
  surfaces this check runs on are literally always loaded: a skill body or agent definition loads in
  full on every use of its component. The second detect case covers exactly that, and requires
  establishing the component's breadth first — a skill or agent that exists only for the content's
  concern loads it precisely when it is relevant and is not a finding.
- **`audit-instructions` I3 remediation now qualifies its destination and prices the move.** A
  destination qualifies only if it defers loading, so `@path` imports do not — a split into imports
  satisfied the check's letter while changing the load profile not at all. A finding must also state
  that a `paths:`-scoped rule or a nested `CLAUDE.md` is lost after compaction until a matching file
  is read again. A move into a **new** skill is priced too: the body defers, but the listing entry it
  adds — `name` plus the combined `description` and `when_to_use`, truncated at 1,536 characters — is
  always in context, so "move it to a skill" moves part of the cost into the always-loaded tier
  rather than out of it. A move into a skill that already exists adds no entry and is not charged.
  `disable-model-invocation: true` is the only field that keeps a description out of context, and it
  makes the skill user-invocable only; `skillOverrides` does not reach plugin skills. Stated as a
  cost on the recommendation, never as a budget threshold.
- **`audit-instructions` I9 remediation names the interface destination.** Where an example block
  exists to enumerate what a caller may pass, the finding names an argument enumeration, a
  frontmatter field, or a typed `argument-hint` instead. `OPINION`-derived, labelled as such in the
  finding, never fix-applied; the detection is unchanged and stays officially backed.
- **Recheck triggers now watch every page in the catalog's source list**, not the three originally
  named. Each check cites one of those pages, so a subset left the new harness-behavior rows
  depending on pages nothing watched.
- **The surface partition no longer widens a row.** It said the full catalog applies on non-memory
  surfaces while I13 and I14 declare narrower surface sets, so a lane could emit I14 findings on
  prompt-type hooks and output styles the criterion excludes. Each row's own declaration bounds it.
- **The `description` carries the new checks' trigger vocabulary.** It framed the skill purely as
  finding instructions the model no longer needs, and only the description is available during skill
  selection — so a request about a stale harness claim, a non-loading `@path`, or a redundant
  startup-surface read would not have selected the catalog that answers it.
- **`Authority` gloss restated descriptively.** The axis is a closed three-value set, not a rule
  that every row is `ANTHROPIC-DOCS` — `TALK` and `OPINION` stay reachable, and the two
  `OPINION`-tier rules this release adds are the first to use one.

### Fixed

- **`audit-permission-grants` no longer points outside the plugin root.** Both `SKILL.md` and
  `reference/criteria.md` reached the permission-rule-hygiene convention through a `../` relative
  link. An installed plugin runs from an isolated cache holding only the plugin's own tree, so the
  link normalized above the cache root and resolved to nothing — the skill directed a read that
  cannot succeed in installed form, while resolving fine in a full-repo checkout, which is why it
  survived. Both now point at the convention's published URL, the form sibling plugins already use
  for marketplace conventions. Nothing was copied into the plugin: the convention stays the single
  owner of the principle, the three anti-patterns, and the correct pattern. What a run actually needs
  was already in-plugin — each check's **Recommend** line — and both files now say so, so a report
  never depends on fetching anything.

## [0.9.3]

### Added

- **`setup` evals.** The skill shipped none, against the repo's own rule that a skill carrying
  behavioral warrants demonstrates them. Four cases cover the behaviors its SKILL.md asserts and
  nothing else: a bare invocation routes to `check` and writes nothing; a missing `curl` FAILs
  scoped to `check-plugin-drift.sh` alone rather than downgrading the rest of the audit surface;
  an install request under `apply` yields platform instructions without executing a package
  manager, and never reports a prerequisite resolved on an install command's exit code; and an
  audit request under `setup` routes to the audit skills by name instead of being performed.

## [0.9.2]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.9.1]

### Added

- **`audit-instructions` eval: `step-list-culled-not-preserved`.** Exercises check I8's
  step-list nuance: a mechanical numbered procedure is culled to intent plus hard constraints
  (genuine ordering, safety gates, external contracts kept) rather than preserved verbatim.
  Absorbed from the superseded `audit-model-fit` suite (its C2 analog), per the follow-up
  material recorded when 0.9.0 removed that skill.

## [0.9.0]

### Added

- **`audit-instructions` skill** (`/claude-config:audit-instructions`). A read-only audit of the
  locally-owned Claude Code instruction surfaces — user + project `CLAUDE.md`, `.claude/rules`,
  skill bodies, agent definitions, prompt-type hooks, output styles — for instructions current
  models no longer need: prior-model workarounds, over-prescriptive scaffolding, bare prohibitions,
  reasoning-echo directives, and approach-pinning example blocks. It ships an eleven-check catalog
  (`reference/criteria.md`) cited to current official prompting doctrine, tiers every finding
  mechanical vs behavioral, and packages proposed removals/rewrites as human-gated diffs — never
  auto-applied. An advisory grep-only scanner (`scripts/instruction-scan.sh`) seeds the mechanical
  tier. It partitions with `claude-memory`'s `audit` skill: on memory-layer surfaces it runs only
  the model-era checks and routes hygiene findings there; on non-memory surfaces the full catalog
  applies. Upstream-owned plugin-cache and managed-materialization findings route to the owning
  repository rather than being edited in place.

### Fixed

- Corrected stale `claude-memory` skill-name references (`health` → its current name `audit`)
  across the plugin's skills and README — the `audit`, `audit-automation-gaps`, and
  `audit-permission-grants` route-out notes and the README's instruction-layer and migration
  sections. The `claude-memory` memory-layer skill was renamed `health` → `audit`; the old
  `/claude-memory:health` invocation no longer resolves.

### Removed

- **`audit-model-fit` skill superseded by `audit-instructions`.** Both audits answer the same
  question — locally-owned instruction surfaces vs current model capability — and repo doctrine
  admits only one skill per question. `audit-instructions` carries the fuller catalog (eleven checks
  I1–I11 with authority tags and evidence tiers), the `claude-memory` hygiene partition, and the
  adversarial fresh-context verify pass, so it strictly covers `audit-model-fit`'s four checks and
  supersedes it. Both were built concurrently from the same underlying issue (#800); `audit-model-fit`
  (added in 0.8.0 below) is removed here.

## [0.8.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.0]

### Added

- **`audit-model-fit` skill** (`/claude-config:audit-model-fit`). A fourth audit that sweeps the local
  Claude Code instruction surfaces — user + project `CLAUDE.md`, skill `SKILL.md` bodies + context
  files, agent definitions, `.claude/rules/**`, prompt-type hooks and output styles — for deterministic
  constraints that hobble newer, more capable models, and proposes removals/rewrites. Check catalog:
  bare prohibitions with no rationale (rewrite to add the *why*, never blanket-delete), over-prescriptive
  step lists (cull to intent + hard constraints), over-constraining example blocks (trim toward the
  recommended 3–5, not a blanket ban), and stale model-era workarounds — each measured against "would
  removing this cause Claude to make mistakes?". A bundled `instruction-surface-scan.sh` enumerates the
  surfaces and flags the two grep-able smells as candidates; the judgment stays in the skill body.
  **Report-only and human-gated**: it presents findings plus proposed diffs and never edits any
  instruction file itself (no `--fix`). Findings inside `melodic-software/standards`-managed
  materializations route upstream per the sync-manifest rather than being edited in place. Composes with
  (distinct intents, pointers only) `claude-memory:audit` (instruction-layer *health*, same surfaces),
  `skill-quality:check` (structure), `docs-hygiene:compress` (token brevity), and the sibling `audit`
  (config-file correctness). The plugin `description` now reads "Four audit skills".

## [0.7.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.0]

### Changed

- **BREAKING — two skills renamed to the `audit-*` naming grammar** (fleet conformance wave, naming
  grammar): `automation-gaps` → `audit-automation-gaps` (`/claude-config:automation-gaps` →
  `/claude-config:audit-automation-gaps`) and `permission-hygiene` → `audit-permission-grants`
  (`/claude-config:permission-hygiene` → `/claude-config:audit-permission-grants`). The old
  invocations stop resolving; update any saved references. The `audit` skill is unchanged.

## [0.6.0]

### Added

- **`setup` skill on the uniform contract** (`/claude-config:setup`). Closes the doctrine-tracked
  setup gap: the plugin's audit scripts require external CLIs (`jq` for all three skills, `curl` for
  the plugin-drift check) but no setup shipped. `check` (default, read-only) probes `jq`/`curl`/the
  bash shell against the bundled scripts as source of truth and reports PASS/FAIL/INFO — `jq` missing
  is a plugin-wide FAIL, `curl` missing a scoped FAIL for the drift check only. `apply` gives platform
  install guidance and re-verifies; it installs no system package and writes nothing. README
  Requirements now names the bash/Git-Bash shell prerequisite alongside `jq`/`curl`.

## [0.5.0]

### Changed

- Renamed the plugin `claude-config-audit` → `claude-config`. Reinstall as
  `claude-config@melodic-software` and update any `/claude-config-audit:*` invocations to the
  `/claude-config:*` namespace.
- Renamed the `settings-audit` skill → `audit` (`/claude-config:audit`) and the
  `automation-deep-dive` skill → `automation-gaps` (`/claude-config:automation-gaps`).
  `permission-hygiene` keeps its name (now `/claude-config:permission-hygiene`).

### Removed

- Extracted the `memory-health` skill into the new standalone `claude-memory` plugin, where it ships as
  the `health` skill (`/claude-memory:health`). Install `claude-memory@melodic-software` for the
  instruction/memory-layer audit.

## [0.4.0]

### Added

- "Pre-computed context" blocks in the `automation-deep-dive`, `memory-health`, and `settings-audit`
  skills: `!`-executed commands inject live repo facts (automation inventory; memory/rules/CLAUDE.md
  counts and the RD1/M2 script-backed check counts; installed Claude Code version) at skill load, so
  each audit starts from guaranteed-fresh evidence instead of relying on the model to remember to run
  the bundled scripts. Every command carries an `|| echo` fallback so skill load never hard-fails.
  No `allowed-tools` self-grant ships with the blocks: a `Bash(bash <path>*)` grant is the
  interpreter-led P1 shape this plugin's own `permission-hygiene` criteria flag (auto mode drops it),
  and `!`-execution does not route through `allowed-tools`.
