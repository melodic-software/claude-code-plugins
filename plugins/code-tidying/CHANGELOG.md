# Changelog

All notable changes to the `code-tidying` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.2]

### Changed

- **Doc reference updated for the `config-cascade` seam rename (#1188).** The layering-contract link in
  `tidy/SKILL.md` and `tidy/lanes/docs-prose.md` now points at `docs/conventions/config-cascade/`
  (formerly `consumer-config-layering`). No behavior change.

## [0.7.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.7.0]

### Changed

- **`docs-prose` lane decomposed to conform with the consumer-config layering contract (#701).**
  A project lane at `.claude/tidy-lanes/docs-prose.md` no longer replaces the bundled lane wholesale.
  It now merges **per section** via a declared `## Merge semantics` block: the `Scope` block is a
  per-section override (retargets doc globs), while the generic watch-for patterns (P-1..P-6) are
  **additive** (a project's entries append to the bundled set), so bundled pattern improvements keep
  reaching consuming repos instead of being frozen out. The `tidy` lane-resolution engine now reads
  **both** the project and bundled layers and merges per the project lane's declared semantics; a lane
  with no `## Merge semantics` declaration still resolves project-only (legacy path), so lanes not yet
  migrated (`shell-tooling`, tracked in #724) are unchanged. Follow-up: the single-layer gap — no
  user-global or `*.local.*` overlay — is tracked in #723, not folded in here.

## [0.6.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.6.0]

### Changed

- **BREAKING — the `comment-residue` skill renamed to `audit-comment-residue`** (fleet conformance
  wave, naming grammar): `/code-tidying:comment-residue` → `/code-tidying:audit-comment-residue`. The
  old invocation stops resolving; update any saved references. The in-code `comment-residue-ignore`
  opt-out marker is unchanged.

## [0.5.1]

### Changed

- **batch-simplify resolves verification commands through the registered
  ecosystem-command owner** (fleet conformance wave, registry single-home).
  The baked per-ecosystem command table is gone: `/toolchain:build` when
  installed, else the project's own canonical commands, else manifest-derived
  entry points — never a memorized list.

## [0.5.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects the tracked
  `.claude/tidy-lanes/<lane>.md` project lanes read-only (presence — absent is INFO, since `tidy`
  falls back to the bundled lanes — required sections, unreplaced `<placeholder>` tokens, and
  tracked-not-ignored via `git check-ignore`) and reports a PASS/FAIL/INFO table; `apply` runs the
  interview-and-scaffold flow, then re-runs `check` to verify each written lane. The lane/template
  scaffolding logic is unchanged; the read-only inspection path and the `check | apply` argument-hint
  are new, and `apply <lane>` targets a single lane.

## [0.4.3]

### Changed

- README declares the Bash 4+ requirement of the bundled scripts (`mapfile`,
  case-conversion expansions) with its Windows path (Git Bash) — cross-platform
  declaration wave. Script behavior unchanged (CRLF and drive-letter handling
  already present).

## [0.4.2]

### Changed

- Updated cross-plugin references for the `docs-hygiene` skill rename
  `declutter` → `audit-noise`: `comment-residue` now routes markdown noise to
  `/audit-noise` (SKILL.md, evals, detect script help text).

## [0.4.1]

### Changed

- Synced work-item filing routes to the reorganized `work-items` taxonomy:
  `/work-items:work-items add` is now `/work-items:track add` (README, `tidy`,
  `batch-simplify`, and the scope-budget reference).

## [0.4.0]

### Added

- Stdlib-only frontmatter-fence integrity check in the self-update lane's verification commands: a portable python one-liner that confirms every SKILL.md's `---` fences are present and the frontmatter between them is non-empty, since a broken fence would block the next session's skill discovery.
