# Changelog

All notable changes to the `claude-memory` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.1]

### Fixed

- **The shared concern-value parser no longer reads a declared key as absent over YAML key spacing.**
  `parse-concern-value.sh` anchored on the exact regex `^<key>:`, so `memory_dir : .work` (YAML
  permits whitespace before the `:`) and a root block mapping written at a uniform indent both
  resolved to the caller's fallback — substituting a value the repo never chose for one it did.
  Both shapes now resolve, matched at the document's own base indentation so a same-named key
  nested under another mapping never answers for the root one — including when the root key is
  present but deliberately empty. Synced from `lib/parse-concern-value.sh`; version bumped so installed
  copies receive it.

## [0.5.0]

### Fixed

- **The C3 placement eval no longer rewards moving an unspecified remainder.** Its prompt left the
  other half of the 300-line `CLAUDE.md` unstated, so removing the running log alone already brought
  the file under the line budget — and if that remainder were always-on project conventions, C3 says
  they belong in `CLAUDE.md`. The expectation nevertheless demanded a skill or path-scoped rule for
  it, rewarding a move that can make required instructions unavailable after compaction. The prompt
  now says what the remainder is (a Terraform walkthrough relevant only under `infra/`), and the
  expectation requires the destination to be justified by relevance rather than by the budget.
- **`reference/official-guidance.md` no longer claims Claude Code loads `AGENTS.md`.** The
  "Compaction by steering method" table carried a `CLAUDE.md / AGENTS.md` row, but the memory doc's
  own `AGENTS.md` section states "Claude Code reads `CLAUDE.md`, not `AGENTS.md`" and prescribes an
  `@AGENTS.md` import or a symlink as the way to make one load
  (<https://code.claude.com/docs/en/memory>). The row is now `CLAUDE.md` alone, with its nested-file
  on-demand reload spelled out, and a following note records how an `AGENTS.md` actually reaches
  context. Left as written, the snapshot contradicted the sibling `claude-config` catalog, which
  excludes `AGENTS.md` from its comparison set on the doc's authority.

### Changed

- **`audit` check C3 (Content Placement): three gaps closed in one revision.** The routing table
  answers one question, so these land as one edit rather than three checks that would emit three
  findings on one misplaced section. (1) **Auto memory becomes a destination** — the plugin audits it
  as a first-class entity in M1–M4 but never routed content to it, so the destination set predated
  auto memory; the row states that Claude writes it and that asking Claude to remember something
  lands there rather than in CLAUDE.md — gated on the destination's effective enabled state, because a
  disabled auto memory neither loads nor accepts writes, so an ungated recommendation to move
  accumulated learnings out of CLAUDE.md would delete them from every future session rather than
  relocate them. The gate reuses the resolver the sibling `stateless` skill already owns instead of
  reading one scope: `CLAUDE_CODE_DISABLE_AUTO_MEMORY` is authoritative wherever set (`1` off, `0` on
  even against `autoMemoryEnabled: false`), and settings precedence decides `autoMemoryEnabled` only
  when the variable is unset.
  (2) **`@path` imports are named as a non-destination** —
  imported files load at launch, so a split into imports reorganizes and saves nothing, and the same
  holds for an import inside a path-scoped rule, where the rule's own body defers and the imported
  file does not — carried as an explicitly provenance-marked empirical extension (first-party repro
  on Claude Code 2.1.219) so the `update` action cannot overwrite it with doc-sourced text.
  `reference/official-guidance.md` already recorded the launch-load behavior and no check cited it. (3) **Every move recommendation now prices the destination** against the "Compaction by
  steering method" table that same reference file ships and no check cited — path-scoped rules and
  nested CLAUDE.md return only when a matching file is read again, so a rule that must persist across
  compaction stays unscoped or in root CLAUDE.md. Pricing extends past compaction to the skill
  destination the routing table already recommended: a **new** skill defers its body but adds a
  listing entry — `name` plus the combined `description` and `when_to_use`, truncated at 1,536
  characters — that is always in context, so part of the cost moves into the always-loaded tier
  instead of out of it. A move into a skill that already exists adds no entry and is not charged.
  `disable-model-invocation: true` is the only field that keeps a description out of context, and it
  makes the skill user-invocable only; `skillOverrides` does not reach plugin skills. Catalog
  version 1.3.0.

## [0.4.1]

### Fixed

- **`audit` reference: the path-scoping status claim was false.** `reference/official-guidance.md`
  asserted (dated 2026-04-01) that `.claude/rules/` files "load unconditionally at session start
  regardless of `paths:` frontmatter", citing four open issues. A first-party repro on Claude Code
  2.1.219 disproved it: a rule scoped `paths: ["**/*.tsx"]` was absent at session start, present
  after reading a matching `.tsx` file, and absent again after reading a non-matching one — deferral
  works in both directions. The cited evidence failed independently too: two of the four issues are
  closed NOT_PLANNED and never supported the claim (#38487 asks that Write/Edit *also* trigger
  injection, which presupposes deferral works; #32906 is a docs issue about subagents), and the two
  still open assert opposite failure modes. The passage now states path scoping as verified working
  on 2.1.219 as of 2026-07-24, with no version floor claimed since no changelog entry or maintainer
  comment pins when it changed, and keeps the caveats that do survive: an `@import` inside a
  path-scoped rule still inlines at session start and defeats the rule; path-scoped content is
  invisible to subagents, teammates, and skill-forked contexts (#32906, closed NOT_PLANNED —
  accepted behavior); a new-file Write does not trigger the rule; and before v2.1.211 on-demand
  rules loaded even when `project` was excluded from `--setting-sources`.

## [0.4.0]

### Added

- **`stateless`: machine-wide mode (`status all` / `purge all`).** The skill's name and
  description invite "am I stateless everywhere on this machine?", but every action was
  single-project — a machine-wide audit had to hand-roll a loop over
  `~/.claude/projects/*/memory/`. New `scripts/enumerate-all-projects.sh` lists every
  per-project store under `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/` with MEMORY.md line
  counts and topic-file counts (enumeration-only, never exits non-zero on absence, reusable
  by the sibling `audit` skill; ships with its own test script). `status all` appends the
  machine-wide table to the posture report, with explicit caveats that per-repo settings
  overrides and relocated `autoMemoryDirectory` stores are not visible from enumeration
  alone. `purge all` runs the same manifest → gate → optional-backup → delete flow with
  every per-project store as the candidate set, one combined manifest, and ONE combined
  confirmation gate stating the machine-wide total and every directory with per-dir counts;
  the backup offer covers the whole manifest with per-dir sibling snapshots. (#981)

## [0.3.5]

### Changed

- **`stateless` disable: dotfile-manager backfill detection beyond chezmoi.** Step 3 claimed
  to be repo-agnostic but only checked chezmoi, with a hand-wave to "check any other dotfile
  manager". It now carries concrete detectors for chezmoi (managed-output check — the previous
  bare `&&` chain reported TRACKED whenever the binary existed), yadm
  (`ls-files --error-unmatch`), and GNU stow / symlink managers (settings file is a symlink,
  or its parent dir is — the stow tree-folded layout), plus a fingerprint fallback
  (`.chezmoiroot`, `~/.local/share/chezmoi`, `~/.local/share/yadm`, `.stow-global-ignore`,
  `~/.dotbot`) that reports "manager fingerprint
  present but unconfirmed" instead of silently concluding the file is unmanaged when a
  manager's artifacts exist without its binary on PATH. Backfill routing now names each
  manager's own flow and warns against any `apply`/`restow` from the live session. (#980)

## [0.3.4]

### Added

- **`stateless` purge: opt-in backup-before-purge escape hatch.** The confirmation gate now
  offers to snapshot the manifest's exact files to a sibling `<memory_dir>.bak-<UTC>/`
  directory before deleting ("yes, with backup"). The copy follows the same
  manifest-exact/no-re-glob discipline as the delete, verifies the copy count before any
  deletion, and Step 5 reports the snapshot path. (#979)

### Changed

- **`stateless` purge: bundled-consent does not satisfy the confirmation gate.** Step 3 now
  states explicitly that consent gathered earlier via a bundled or multi-option answer — an
  upstream `/interview` round, a numbered menu selection whose option happened to include the
  purge, or a "purge" given before the manifest was known — does not satisfy the gate; it must
  restate the concrete now-known scope (file count, directories) and receive a fresh,
  scope-referencing confirmation. A worked anti-pattern example is included. (#979)

## [0.3.3]

### Fixed

- **Non-repo memory-dir resolution implemented (the documented fallback).** The shared
  `resolve-memory-dir.sh` hard-required a git repo (`exit 1` when `git rev-parse --show-toplevel`
  was empty) and the `stateless` skill's `scope-report.sh` pre-emptied it with a bail-out telling
  the user to run from within a repo — but the official memory doc (re-verified 2026-07-22)
  says "Outside a git repo, the project root is used instead", so a non-repo directory is a
  fully valid case with a real memory store the skill could neither find nor report. The
  resolver now derives the project slug from the current directory (same Windows-form
  normalization as the repo-root path) when no repo is found, `scope-report.sh` calls it
  unconditionally (with an informational note that the cwd is the project key), and the
  regression test that had locked the bail-out in as a spec now asserts the resolved
  cwd-derived path. The `audit` skill's deterministic M2 checker
  (`memory-index-refs-check.sh`) carried its own now-redundant git-repo guard that would have
  kept the audit from checking a non-repo store's index integrity — the guard is removed
  (the shared resolver owns the non-repo case) with a non-repo regression test added. (#978)

## [0.3.2]

### Added

- **`audit` skill: reciprocal scope-boundary note.** Model-era instruction-content findings
  (prior-model workarounds, over-prescriptive scaffolding, bare prohibitions, reasoning-echo
  directives, stale example scaffolding) now route to the `claude-config` plugin's
  `audit-instructions` skill when that plugin is installed; absent it, such observations stay
  in the audit report criteria-free rather than being judged against this checklist or
  silently dropped. Completes the partition that skill declared toward this one.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- **New `stateless` skill (`/claude-memory:stateless`)** for inspecting and disabling Claude
  Code auto memory — the notes Claude writes for itself per repo under
  `~/.claude/projects/<project>/memory/` (relocatable via `autoMemoryDirectory`). Actions:
  `status` (default, read-only — effective on/off state and store contents across all settings
  scopes), `disable` (sets `autoMemoryEnabled: false` and `CLAUDE_CODE_DISABLE_AUTO_MEMORY` in a
  confirmed scope, and flags a dotfile-manager backfill for a tracked `settings.json`), and
  `purge` (destructive — reads `autoMemoryDirectory` at every scope, shows a deletion manifest,
  and deletes auto-memory `*.md` files only after explicit confirmation). Scope is auto-memory
  only; the instruction layer stays with `audit`, and transcripts/history are out of scope
  (auto-cleaned by `cleanupPeriodDays`). Claude Desktop / claude.ai account memory is a
  server-side store the skill gives direction for rather than deleting locally. Per the
  env-vars doc, `CLAUDE_CODE_DISABLE_AUTO_MEMORY` overrides `autoMemoryEnabled` (the env var is
  authoritative when set); `disable` writes the env var (`1`) plus `autoMemoryEnabled: false`,
  and `status` treats a set env var as authoritative. The bundled `scope-report.sh` reuses the
  plugin's single-source memory-dir resolver rather than re-deriving the path.

### Fixed

- **`resolve-memory-dir.sh` now honors `CLAUDE_CONFIG_DIR`.** The shared resolver (used by both
  the `audit` and `stateless` skills) resolved the config root as `$HOME/.claude`, so a machine
  that relocates its Claude Code config via `CLAUDE_CONFIG_DIR` had its memory directory resolved
  to the wrong path. It now uses `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, per the official
  `.claude-directory` doc, so the relocated `projects/<project>/memory/` tree resolves correctly.

## [0.2.3]

### Fixed

- **`orphan-rule-check` no longer truncates a quoted `memory_dir` at an interior `#`.**
  Seam resolution now routes through the shared `parse-concern-value.sh` helper
  (materialized from `lib/parse-concern-value.sh`), which resolves surrounding quotes
  *before* stripping comments: `memory_dir: ".scratch#dir"` keeps its `#` and the correct
  tier is excluded from the reference search, rather than collapsing to `.scratch` and
  masking an orphan rule. The naive `${seam%%#*}`-first strip is gone; an unquoted
  whitespace-preceded trailing `# comment`, surrounding whitespace, and trailing-slash
  handling are unchanged. As a
  non-interactive detector it still degrades to the documented `.work` default when the
  seam is unset — the contract's inferred/interactive rungs stay the calling skill's job.
- **A comment-only `memory_dir` now resolves to the fallback, not a literal directory.**
  `memory_dir: # use default` is YAML-null; the parser previously kept `# use default`
  as the value (its comment strip only fired on a whitespace-*preceded* `#`), so the
  detector searched `# use default/` and stopped excluding the default `.work/` tier —
  letting a `.work` reference mask an orphan. A `#` that starts the unquoted value is now
  treated as a comment, so resolution falls through to the caller's fallback / documented
  default.

## [0.2.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.1]

### Fixed

- **`orphan-rule-check` now resolves the excluded memory tier from the topic-docs seam**
  instead of hardcoding `.work/`. The reference search reads `memory_dir` from
  `.claude/topic-docs.yaml` (falling back to `.work/` when unset) and excludes that path,
  so a consumer that overrides `memory_dir` no longer has its real memory tier scanned —
  ephemeral files there can no longer register false references that mask an orphan rule.

## [0.2.0]

### Changed

- **BREAKING — the `health` skill renamed to `audit`** (fleet conformance wave, naming grammar):
  `/claude-memory:health` → `/claude-memory:audit`. The old invocation stops resolving; update any
  saved references. Actions (`audit` / `fix` / `update` / `report`) are unchanged.

## [0.1.0]

### Added

- Initial release. The `health` skill was extracted from the `claude-config-audit` plugin — where it
  shipped as the `memory-health` skill — into this standalone plugin, invoked as `/claude-memory:health`.
  It audits the Claude Code instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`,
  and auto-memory) against a checklist derived from official Claude Code documentation, with a
  deterministic script-backed spine (MEMORY.md index integrity, orphan always-loaded rules) and
  `audit` / `fix` / `update` / `report` actions. Audit reports stay contributor-local in the plugin's
  data directory.
