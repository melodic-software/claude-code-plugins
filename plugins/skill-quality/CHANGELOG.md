# Changelog

All notable changes to the `skill-quality` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.1]

### Fixed

- **Check 8 (vendor/ byte-identical vs HEAD) no longer blocks a legitimate
  maintainer-run sync.** It previously failed on ANY `vendor/` diff vs the
  base ref, with no way to distinguish a hand-edit from a genuine upstream
  refresh via a vendored skill's own `update` action — the exact workflow
  those skills document as the sanctioned way to advance `vendor/`. The check
  now passes a `vendor/` diff when it is paired with a bumped
  `metadata.upstream-version` (the signal every such sync flow already
  produces in the same change) and still fails an unpaired diff, preserving
  the original hand-edit guard. Added `skill_frontmatter::metadata_field` (a
  new indentation-tolerant reader for `metadata:` sub-keys) since the
  existing `skill_frontmatter::field` anchors at column 0 and cannot see
  them. Two new regression tests cover both branches.

## [0.7.0]

### Added

- **Check 18 (precompute opportunity) — advisory WARN.** Flags a `SKILL.md` that gathers
  deterministic, read-only context by telling Claude to run shell commands at invocation, when that
  output could instead be inlined at load time via `!`command`` / ```! dynamic-context injection (one
  preprocessing pass, no per-invocation tool round-trip). It is a heuristic, never a FAIL: it scans
  fenced shell blocks whose command lines are all read-only context-gatherers. Classification fails
  closed: a pure-reader allowlist plus a read-only-subcommand allowlist for `git`/`gh` (so an unlisted
  mutation like `git stash` or `gh pr merge` is never read-only), and any shell construct that can hide
  a second command or a write disqualifies the line — redirection, command/process substitution
  (`$(...)`, backticks), backgrounding/chaining (`&`, `&&`, `;`), a bare pipe into a sink
  (`git status | tee f`), and side-effecting or external-program options on an allowlisted reader
  (`find -exec`, `git diff --output`, `git diff --ext-diff`/`--textconv`). The `|| echo "<fallback>"`
  fallback form is the one preserved continuation.
  The check stays silent when the skill already uses any `!` injection. A static scan cannot tell an instruction-to-run block from
  an illustrative example, so the WARN is a candidate to hand-verify, not a defect; it reads fenced
  blocks only (not prose) and under-reports by design. Points at the official
  `#inject-dynamic-context` docs rather than any other plugin, so it stays valid in any consumer repo.

## [0.6.0]

### Added

- **Check 1 now enforces that frontmatter `name` matches the skill directory name.**
  `docs/PLUGIN-PHILOSOPHY.md` has always required it, but nothing verified it — check 1 asserted
  only that `name:` was present and non-empty. The directory name is what Claude Code namespaces the
  skill by, so a divergent frontmatter `name` silently relocates the invocation the doctrine says
  the skill has, and because the slash-command picker labels rows by the resolved leaf name the
  drift never surfaced in the listing either. Lands as a deterministic FAIL rather than a warning:
  the whole catalog (144 skills) already conforms, so there is no debt to grandfather and no
  baseline file. A quoted value is unquoted before comparison, and an absent `name` still reports
  only the existing missing-`name` failure rather than a spurious second one.

## [0.5.0]

### Changed

- **`setup` skill refactored onto the uniform check/apply contract** (fleet conformance wave).
  `/skill-quality:setup` replaces the interactive-validation shape with `check` (default, read-only:
  resolves `skills_root` through the ladder, verifies the directory exists and enumerates skills,
  reports PASS/FAIL/INFO) and `apply` (non-interactive: routes a `skills_root` change through Claude
  Code's native prompt with the fresh-install-only `--config` headless semantics). The resolution
  ladder, the one-run `CHECK_SKILL_SKILLS_ROOT` override (still never persisted), the
  `/skill-quality:check` verification pointer, and the dated `pluginConfigs` claim are unchanged.

## [0.4.1]

### Changed

- **Freshness rider on the setup skill's `pluginConfigs` claim** (fleet
  conformance wave). The claim is re-verified, dated, and pinned to the
  release that introduced the behavior (≥ 2.1.207).

## [0.4.0]

### Changed

- Renamed the `skill-quality` skill → `check`. Update any `/skill-quality:skill-quality` invocations
  to `/skill-quality:check`; the plugin ID (`skill-quality`) is unchanged, only the skill's leaf name
  moved.

## [0.3.0]

### Added

- **Post-commit audit ref.** `CHECK_SKILL_BASE_REF` (default `HEAD`) selects the ref the git-backed
  checks (3 trigger-preservation, 8 vendor byte-identity, 9 stale-tracking metadata) diff the working
  tree against. The default still catches an uncommitted rewrite; pointing it before a change (e.g.
  `HEAD^` or a merge-base) and running on a clean tree catches an already-committed change that the
  `HEAD` == working-tree comparison would miss.

### Changed

- **Block-scalar descriptions are unfolded.** A `description: |` / `>-` block scalar is now expanded to
  its text before the length (2), trigger-preservation (3), and phrasing (12) checks, which previously
  operated on the `|` / `>` marker instead of the content.
- **Frontmatter must open on line 1.** The YAML frontmatter fence is required at line 1; content before
  it is no longer treated as frontmatter, closing a path where a stray `---` further down could satisfy
  check 1.
- **Unquoted `Use when:` triggers warn (check 12).** Trigger-drop protection (check 3) tracks only
  single-quoted `'phrase'` triggers; an unquoted `Use when:` list now raises a warning so those phrases
  get quoted and covered, rather than silently going unprotected.
