# Changelog

All notable changes to the `skill-quality` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.12.0]

### Added

- **Check 21 — fresh-eyes declaration conformance.** A skill step whose text reads as
  same-context judgment (curated POSIX-ERE heuristic, WARN-only) is expected to carry
  fresh-context delegation wording (`fresh-context` / `fresh context`) or a
  `fresh-eyes-exempt` directive within a per-file proximity window. Directive syntax is
  enforced: an unknown class or a missing `-- <reason>` FAILs; a directive with no
  judgment-language hit nearby WARNs as stale (advisory). Both detectors are fence- and
  inline-code-span-aware (literal examples in docs never trip them) and tolerate CRLF.
  Contract spec for authors: `skills/check/reference/fresh-eyes-declarations.md`; the
  heuristic list's curation policy lives there too. Fence matching follows CommonMark
  (an info-string line inside a fence is content, not a closer; a backtick opener
  carrying a backtick in its info string is prose, not a fence; opener indentation caps
  at three spaces; blockquote and list-marker prefixes are stripped first, so a
  container-nested fence still suppresses its body, while only a prefixed opener strips
  them in-fence so a quoted run cannot close an unprefixed fence, and a nested fence ends
  with its container — blockquote DEPTH, not mere marker presence — so an unclosed one
  cannot swallow the rest of the file), spans pair
  backtick runs of exactly equal length and carry an unclosed opener across line boundaries
  to the end of the paragraph (multi-backtick and multi-line spans hide their content).
  Escapes and spans resolve in one pass because CommonMark couples them: outside a span a
  backslash escape makes the next character literal (`` \` `` opens no span, `\<!-- ... -->`
  is text rather than a directive), while inside a span nothing is escaped, so a literal
  backslash before the closing run does not stop it closing. Each directive on a line is
  classified independently (a malformed one cannot borrow a valid neighbour's class), and
  delegation wording only counts when the same line names the worker or dispatch as a whole
  word — embedded stems satisfy neither half ("agentless" is no worker, "Refresh context" is
  not the fresh-context wording).
- **Check 21 ships a stated parsing contract**
  (`skills/check/reference/fresh-eyes-declarations.md`, "Parsing contract"). It enumerates the
  markdown constructs the scanner models, names the ones it does not attempt (indented code
  blocks, mixed container stacks, paragraph-interrupting headings, multi-line HTML comments,
  reference definitions and link syntax), and states what happens when structure cannot be
  resolved. The scanner is a hand-written `awk` structure pass, not a CommonMark implementation,
  because the check has to run with nothing but a POSIX shell and `awk`; the contract makes that
  a bounded claim instead of an implicit promise to parse everything.
- **Structurally ambiguous placement withholds the hard verdicts.** A four-space-indented
  directive is either indented code or a list-item continuation, and the scanner cannot tell, so
  it emits neither `DIRECTIVE_MALFORMED` nor `DIRECTIVE_NOREASON` there (nor the stale WARN)
  rather than failing an author on a parser artifact. The judgment path still runs. The asymmetry
  is the whole argument: those two verdicts are hard FAILs, while the judgment verdicts are WARNs
  where a miss costs one nudge. This posture is specific to check 21 — it must not be carried into
  a gate whose verdict is a security decision.

### Fixed

- README check-count references were stale (still "eighteen"/"seventeen" after checks
  19–20 shipped); counts now derive from the current twenty-one and the checks list
  includes the injection-portability and fresh-eyes rows.

## [0.11.0]

### Added

- **`listing-budget` action + `check-listing-budget.sh`: reports the SHARED skill-listing budget,
  the aggregate limit nothing in the gate previously checked (#1404).** `check-skill.sh` check 2 only
  ever guarded the per-skill entry cap (`skillListingMaxDescChars`, 1536 chars); the shared budget
  every loaded skill draws from together (`skillListingBudgetFraction`, default 1% of the model's
  context window) had no check at all — measured evidence found the aggregate overflowing by a large
  multiple with no gate ever reporting it. The new script pools one or more skills roots into one
  aggregate estimate against a documented, overridable default (8000 chars — the harness's own
  `SLASH_COMMAND_TOOL_CHAR_BUDGET` fallback) and reports the biggest contributors on overflow. It is
  always advisory (exit 0) since the live budget depends on a model's context window and a consumer's
  own settings, neither of which a static check can observe — never hardcode
  `skillListingBudgetFraction`'s documented default as a resolved live value; `/doctor` is the
  authoritative source per machine. Wired into this repo's `skill-quality-gate` CI job as a report-only
  step pooling every plugin's `skills/` root into one marketplace-wide aggregate.

  The report counts only **listing-eligible** skills. A skill with `disable-model-invocation: true`
  is skipped: the invocation-control table at <https://code.claude.com/docs/en/skills> records
  "Description not in context" for that frontmatter, and "Hide individual skills" states it
  "removes the skill from Claude's context entirely" — such a skill spends none of the shared
  description budget, so counting it overstates the aggregate. A consumer's `skillOverrides` can
  free further descriptions via `"name-only"`, which repository content cannot reveal, so the
  figure is an upper bound for anyone who sets it. On this marketplace the filter excludes 51 of the
  183 `SKILL.md` files, leaving a reported **132 listing-eligible skills / 83,611 characters** as
  measured at this commit — still an order of magnitude over the 8000-char default, so the finding
  the check exists to surface is unchanged. (A figure without its commit goes stale: the population
  itself moves, so re-measure rather than quoting this one forward.)

  The flag is read through a normalizing comparison rather than an exact string match, since valid
  YAML can spell the same boolean as `true # manual-only`, `"true"`, `TRUE`, or with surrounding
  whitespace, and a bare `== "true"` silently re-counted every one of those. Comment-stripping is
  scoped to the boolean and deliberately never applied to `description` / `when_to_use`, where a
  whitespace-preceded `#` is content rather than a comment. YAML 1.1's `yes` / `on` aliases are not
  folded — the documented spelling is `true`, and over-matching would risk dropping a skill over a
  value the harness may read as a plain string.

  Input handling is fail-closed on operator error, while the budget verdict stays advisory: every
  numeric override is validated as a positive number and every explicit root must exist, both
  reported as the documented environment error (exit 2). Previously a nonnumeric override was
  either coerced to zero by `awk` — fabricating a zero-character budget and a bogus overflow WARN
  while still exiting 0 — or crashed with an undocumented exit 1, and a misspelled root among
  several was silently skipped while its subtree vanished from an "OK" aggregate. A fixed
  `CHECK_SKILL_LISTING_BUDGET_CHARS` now takes precedence over the token/fraction reconstruction as
  its own documentation always claimed, announcing the ignored input rather than discarding it
  silently, and is labelled an override instead of the "documented default". The report header
  counts roots actually scanned rather than arguments given, and `--help` derives its range from the
  header block so editing that block can no longer clip or overrun the help text.

### Fixed

- **Check 2 now counts the description/when_to_use joiner (#1404).** The harness assembles a skill's
  listing entry as `description` + `" - "` + `when_to_use` — a literal 3-character joiner. Check 2
  summed only `len(description) + len(when_to_use)`, under-counting by 3 whenever `when_to_use` is
  populated, so an entry sitting exactly at the boundary could pass a cap it had actually crossed. Not
  currently binding at present description lengths in this repo, but wrong in exactly the direction
  the listing-budget work is about.

## [0.10.2]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.10.1]

### Documentation

- **`check` gotcha: markdownlint (check 6) defers to the consuming repo's markdownlint config —
  run the checker from inside that repo (`#1153`).** Running the gate from outside the target
  repo, or against a marketplace-installed skill in the plugin cache (which carries no config),
  applies markdownlint DEFAULTS, so rules a repo deliberately disables (commonly `MD013`
  line-length, `MD041` first-line-heading, `MD060` table-pipe) fire as spurious failures on a
  skill that passes in-repo. This is the usual cause of a "shipped marketplace skill fails the
  marketplace's own gate" report — a wrong-config artifact, not a regression. The note also
  records the deliberate decision the report asked for: **injection blocks are not special-cased**
  — a declared `shell:` block with long lines is `MD013`-subject like any other content, and
  whether it fails is the consumer's markdownlint config's call (this gate never overrides it) —
  and documents this marketplace's own CI division of labor (the skill-quality gate skips
  markdownlint; the hygiene lane lints all repo markdown, SKILL.md included, under the repo
  config). No behavior change; the CI gate over changed skills already exists.

## [0.10.0]

### Changed

- **`check` gives actionable guidance for a marketplace-installed skill instead of a bare
  "not found" (`#1152`).** A `plugin:skill` argument (e.g. `source-control:setup`) — the common
  case when gating an installed skill — now prints exactly how to run the gate against the
  install: point `CHECK_SKILL_SKILLS_ROOT` at the cache skills dir, with the note that the cache
  is a **copy, not a git checkout**, so the git-backed checks (3 trigger-preservation, 8 vendor,
  9 stale-metadata) correctly no-op there (a "new skill / skipped" result is expected). A missing
  bare name now names the `CHECK_SKILL_SKILLS_ROOT` remedy too. SKILL.md documents the
  installed-skill resolution path.

  **Scope note — the originating report (`#1152`) is partly falsified.** It claimed the plugin
  cache "IS a git checkout of the marketplace repo, so HEAD exists" and asked to wire check 3 to
  it. Primary-source evidence contradicts this: Claude Code *copies* marketplace plugins into
  `~/.claude/plugins/cache` (docs: "rather than using them in-place"), and the on-disk cache
  carries no `.git`. Check 3's "new skill / skipped" on a cache path is therefore **correct
  behavior, not a bug** — there is no rewrite baseline in a copy — and is not "fixed." The cache
  sub-layout (`<marketplace>/<plugin>/<version>`) is also undocumented and version-dir-churning,
  so the checker deliberately does **not** reverse-engineer it to auto-resolve a `plugin:skill`
  name; the target root stays operator-provided. First-class installed-skill resolution is left
  as a tracked follow-up.

## [0.9.0]

### Changed

- **Check 3 (trigger-keyword preservation) — move exception.** A quoted trigger phrase
  dropped from a skill's listing text but present verbatim in a SIBLING skill's
  `description`/`when_to_use` under the same skills root now WARNs ("moved to sibling
  skill '<name>'") instead of failing — provided the sibling did NOT already carry the
  phrase at the base ref (a phrase it carried all along is coincidental overlap, not a
  move, and still FAILs). Rationale: the check exists to catch listing coverage loss —
  a deliberate trigger partition (a phrase relocating to a new sibling skill in the
  same change, e.g. session-flow's `--bg` cutover, #233) preserves routing, and the
  gate previously had no sanctioned path for it. Phrases absent from every sibling
  still FAIL. New regression tests cover the move path and the coincidental-overlap
  path.

## [0.8.0]

### Added

- **Check 19 (dynamic-context injection shell declaration) — FAIL/WARN.** A `` !`command` `` /
  ` ```! ` injection defaults to `shell: bash`; on a host without Git Bash it falls through to
  the PowerShell tool, so a bash-only pipeline silently breaks (a 2026-07-21 fleet census found
  64 such skills across 26 plugins). When a skill carries injections and declares no `shell:`
  frontmatter, the check FAILs on detectable bash-only syntax (`/dev/null`, `command -v`, a pipe
  into a Unix text tool with no same-named PowerShell cmdlet) and WARNs on portable-looking
  commands (portability is not statically provable). A `shell:` declaration is trusted as the
  author's explicit choice — no per-shell syntax validation. The scan is scoped to injected
  command text only, never prose or a plain ` ```bash ` example.
- **Check 20 (injection defensive fallback) — WARN.** Injection failure/timeout/stderr semantics
  are undocumented, so an unguarded command can inline an error string into the prompt. The check
  WARNs on any injected command lacking a `|| <fallback>` continuation, per the pinned
  precompute convention. It matches the `||` continuation, not the literal `echo` (`|| printf` /
  `|| true` are valid fallbacks).

## [0.7.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

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
