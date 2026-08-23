# Changelog

All notable changes to the `instruction-placement` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.1]

### Fixed

Hint precision, measured by running `detect.sh` over a real 1,137-file corpus rather than over
fixtures. Both over-firings were invisible at fixture scale and obvious at repository scale.

- **Directory names were being reported as file extensions.** `.claude` was the single most common
  "extension" in the corpus at 840 hits, with `.work`, `.github`, `.git`, and `.local` close behind.
  Three rules now apply: a token followed by `/` is a directory component, a known config dotdir or
  dotfile is never an extension, and an extension must be lowercase — which also drops `.NET` and
  `.DS_Store` without listing either.
- **Language hints matched ordinary English.** Lowercase `go` produced 338 false hits from the verb,
  and `shell`/`bash` produced 675 more from prose about shells. The table is now case-sensitive and
  split in two: spellings that are never ordinary English (`TypeScript`, `PowerShell`, `C#`) match in
  any case, while names that collide with common words (`Go`, `Rust`, `Swift`, `Java`) match only in
  their conventional capitalized form.

Net effect on the same corpus: 9,528 hints → 7,217, with the removed entries being false positives
and the genuine signal intact (`Go` mentions fell 338 → 33). Also confirms the detector handles
repository scale: 1,137 files and 11,084 sections in 11 seconds, with clean stderr.

## [0.4.0]

### Added

- **`scripts/verify-load.sh` — empirical load verification (16 tests, including a live one).** Every
  other check in this plugin is static: the glob parses, it matches tracked files, the index is in
  sync. None of them observes Claude Code actually loading anything — and that gap is precisely
  where this plugin's own four bugs lived. A rule can pass every static gate and still never enter
  context.

  It runs the real CLI with an `InstructionsLoaded` hook attached, reads a file the surface claims
  to cover, and reports which instruction files actually loaded and why. The repository under test
  is never modified: the hook lives in a temporary `--settings` file, the probe is read-only and
  confined to `--allowedTools Read`, and the log is written outside the tree.

  It is honest about not knowing. Absent CLI, missing `jq`, a timeout, or a hook that produced no
  records all report `VERDICT UNKNOWN` and exit 3 — never a pass. A verification tool that reports
  success because it could not measure is worse than no tool.

  Its own suite drives the real CLI, and asserts **both directions**: reading a `.cs` file loads the
  C# rule and the imported root surface, and does *not* load the TypeScript rule. The negative case
  is what actually demonstrates that path scoping defers rather than assuming it.

  Wired as an escalation in `check` (for "why is my rule not firing despite a green gate") and as an
  optional post-apply step in `realign` (worth it on the first move of a migration, not on every
  finding, since it costs a model call).

## [0.3.0]

### Added

- **`scripts/detect.sh` — deterministic fact emitter for the audit (38 tests).** The judgment layer
  decides *where* content belongs; it should not also be enumerating the corpus, finding section
  boundaries, or counting normative markers by reading. Emits `FILE` / `SECTION` / `SIGNAL` / `HINT`
  / `RULE` / `SKIP` / `SUMMARY` records as sorted TSV and adjudicates nothing.

  Two consequences make this more than tidiness. **`realign` excises by the line range the finding
  carries**, so a range that came from a model reading a file is a guess about which text gets
  deleted from someone's instruction file; now it is a fact. And two audit runs over an unchanged
  repository now produce the same candidate set, which no amount of careful reading guarantees.

  `HINT` records are raw material for glob derivation, deliberately not decisions: literal `ext` and
  `dir` tokens found in the prose, plus `lang` hints from a small documented language→extension
  table. The skill derives a glob from them and still has to validate it.

### Fixed

- **`detect.sh` regex portability, caught before release.** The first implementation used an
  interval expression (`{0,7}`) in a hint pattern; mawk 1.3.4 does not merely mismatch it, it
  panics — and with stderr suppressed the script emitted an empty fact set, which reads exactly like
  "this file has no sections". Rewritten without intervals, stderr is no longer suppressed, and the
  suite asserts both that no panic reaches the output and that a headed file yields a non-zero
  section count.

## [0.2.0]

### Fixed

Four discovery-layer bugs, all found by probing 0.1.0 rather than by its own test suite. The suite
covered glob *semantics* exhaustively and file *discovery* barely — every bug lived in one
open-coded `find .claude/rules` line, which is why discovery is now a shared `lib/discover.sh` with
its own fixtures and 24 tests of its own.

- **Nested `.claude/rules/` trees were invisible.** Only the root tree was scanned, so a monorepo's
  per-package rules passed `check` while being entirely unverified, and never reached the index.
- **Symlinked rules were invisible.** `find -type f` never matches a symlinked file and does not
  traverse a symlinked directory. Since symlinking is the *documented* way to share one rule set
  across projects, a team using it got zero coverage and zero index entries, silently.
- **Untracked and gitignored files were indexed.** `corpus.md` promises neither is swept, but both
  reached the generated index — including vendored third-party `AGENTS.md` files, which put someone
  else's instructions into the consuming repository's always-loaded surface.
- **The index could be written where Claude Code never reads it.** Claude Code reads `CLAUDE.md`,
  not `AGENTS.md`. A repository carrying both with no import between them got a correct, in-sync
  index that never entered context — the entire subagent-gap mitigation inert while every gate
  reported green.

### Added

- **`render-index.sh reachable`** — answers whether Claude Code would load a given index target at
  all, by walking the import graph from each root memory file (depth-bounded at the documented four
  hops, skipping fenced blocks and inline code spans, and honoring the `CLAUDE.md`-symlinked-to-
  `AGENTS.md` form). `write` now warns on stderr when it writes into an unreachable target rather
  than leaving it for a later gate, and the `check` skill gates on it. Sync and reachability are
  independent questions and a repository can pass one while failing the other.
- **`lib/discover.sh`** — the shared discovery layer, with the two asymmetries documented in
  `corpus.md`: rules follow symlinks and do not require tracked status; nested instruction files
  require tracked status and skip vendored trees.

### Changed

- **Two previously-inferred claims are now measured** on 2.1.238 and recorded in
  `verified-mechanics.md`: an undocumented `description:` key in rule frontmatter is harmless, and
  block-level HTML comments are stripped from an `AGENTS.md` reached by `@import` — which is what
  makes the index markers genuinely free.

## [0.1.0]

### Added

- **`audit` — read-only placement sweep.** Two lanes over a two-tier corpus: **demote** (content in
  an always-loaded `CLAUDE.md`/`AGENTS.md` or an unscoped rule whose real scope is one file kind or
  one subtree) and **promote** (normative conventions stranded in ordinary markdown that Claude
  loads never). Candidates are classified against a decision ladder, every path-scoped proposal
  carries a machine-validated `paths:` glob, and every proposal is priced with its cost as well as
  its saving. Emits a diffable findings artifact under a project-keyed plugin-data path; mutates
  nothing in the repository.

- **`realign` — per-item human-gated apply.** Consumes the audit's artifact and never re-judges the
  surface. Five recipes (path-scoped rule, nested `AGENTS.md` plus shim, promote-by-move or
  promote-by-pointer, re-scope in place, delete) each create before excising, so an interruption
  leaves content duplicated rather than deleted. Every accepted move regenerates the always-loaded
  index. No blanket-approve path exists, including on request.

- **`check` — deterministic gate.** Verifies every `.claude/rules/` glob still resolves and that the
  index matches the rules on disk. Read-only, CI-shaped, and deliberately blind to the findings
  artifact so a stale audit can never make a broken repository look healthy.

- **`scripts/glob-tools.sh` — glob validation engine (45 tests).** Validates `paths:` globs against
  the repository's tracked files: zero-match, malformed bracket expression, and the documented
  1,000-pattern / 4 MiB brace-expansion budget are all hard failures, over-broad is a warning. Brace
  expansion is hand-rolled rather than delegated to shell `eval`, because the input is repository
  content and a crafted rule file must not be able to run commands — covered by a test asserting
  exactly that.

- **`scripts/render-index.sh` — always-loaded index generator (47 tests).** Renders, checks, and
  writes a marked block listing every instruction surface that loads on demand. Indexes only
  surfaces that defer: an unscoped rule already loads every session, so indexing it would spend
  always-loaded budget restating what is already present. Delimited by HTML comments, which Claude
  Code strips from memory files before injection, so the markers cost no context.

- **First-party loading measurements on Claude Code 2.1.238**, recorded in
  `context/verified-mechanics.md` with the `InstructionsLoaded` payloads they came from. Four
  findings shape the design: an `@import` inside a *nested* `CLAUDE.md` defers with its parent
  (unlike one inside a path-scoped rule, which does not); a nested `AGENTS.md` with no `CLAUDE.md`
  shim is never loaded; a subagent sees only the root instruction pair, inheriting none of its
  parent's on-demand loads; and the index is therefore the only mechanism that reaches a subagent.

- **Hard-deny classes.** Irreversible actions, secret handling, data integrity, external
  publication, legal and compliance obligations, and bounds on the agent's own authority are
  excluded from the candidate set entirely rather than surfaced as risky options. `audit` reports
  what it held back; `realign` has no code path that can apply one. Two further structural denies
  come from the mechanics rather than from consequence: creation-governing content cannot use a
  path-scoped destination (the trigger is a read), and a candidate whose body is only an `@import`
  is never routed to one (the import inlines at session start and defeats the scoping).
