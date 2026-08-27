# Changelog

All notable changes to the `instruction-placement` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.11.9]

### Changed

- **`glob-tools.sh` collapses a bracket-negation if/elif chain.** The two branches computed the
  same result; one expression now does. `render-index.sh` merges two consecutive `sed` passes
  into one. Output is byte-identical in both scripts. Code-tidying sweep, behavior-preserving.

## [0.11.8]

### Changed

- **The `@import` rule in `realign`'s apply recipes states the positive.** It said only what fails.
  It now says to cite the shared file by path, carrying the same prohibition and the same rationale.
  Docs-hygiene sweep, L5-noise.
- **The generated options block sits under `## Configuration`.** It was under `## Revisit triggers`,
  a maintainer watchlist whose own lead sentence says so. The generated table itself is unchanged; a
  `## Configuration` heading was added above it. Docs-hygiene sweep, L8-write-for-humans.

## [0.11.7]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.11.6]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** Corrected
  `hooks/index-drift.sh`'s header to the kill switch's real
  `CLAUDE_PLUGIN_OPTION_INDEX_DRIFT_HOOK_ENABLED` spelling; removed dead `tier` plumbing
  from `scripts/detect.sh`'s `emit_file_facts` (the awk program never read it); removed a
  redundant array re-initialization in `scripts/glob-tools.sh`; `scripts/lib/discover.sh`'s
  rule emitter streams to stdout instead of staging through a temp file (all consumers read
  to EOF and no caller runs errexit, so failure semantics are unchanged); dropped
  doubly-redundant `|| true` at two `branch()` call sites in `scripts/precompute.sh`.
  All seven suites green (38/40/56/23/61/18/17); independent refutation pass including a
  mid-failure streaming experiment found no counterexample reachable in this codebase.

## [0.11.5]

### Changed

- **Instruction-surface de-slop (#2891, instruction-placement cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.11.4]

### Fixed

- **Vendored `hook-utils.sh` skip latch (#3128).** The shared notice latch now
  keys on session and agent (a subagent gets its own first notice), stores a
  skip count in the marker (independent of `HOOK_TELEMETRY_SINK`), and emits a
  one-line re-notice every 8 skips instead of going silent after the first.
  The first `PATH probed:` dump omits other plugins' bin dirs. Copies stay
  byte-identical via `scripts/sync-hook-utils.sh`.

## [0.11.3]

### Fixed

Four defects raised in review on #3225, each reproduced before it was fixed.

- **The index-drift kill switch read a variable nothing sets, so the option did nothing.** The hook
  called `hook::check_enabled "INSTRUCTION_PLACEMENT_INDEX_DRIFT"`, which resolves to
  `CLAUDE_PLUGIN_OPTION_INSTRUCTION_PLACEMENT_INDEX_DRIFT_ENABLED`. The declared userConfig key is
  `index_drift_hook_enabled`, which Claude Code mirrors as
  `CLAUDE_PLUGIN_OPTION_INDEX_DRIFT_HOOK_ENABLED` -- the name `README.md` already documented.
  `hook::is_enabled` treats an unset variable as enabled, so setting the option `false` had no
  effect. The suite hid it twice over: the case set the same wrong name the implementation read, and
  it ran against a repository an earlier case had already brought in sync, so the hook was silent
  either way. Now `INDEX_DRIFT_HOOK`, tested on a freshly drifted fixture, with a control case
  proving the fixture drifts and a negative case proving the old spelling does **not** silence it.

- **`validate` pooled the brace budget across unrelated `--glob` flags.** Every CLI glob was tagged
  with the same `<cli>` source, and the budget resets on a source change, so two independently legal
  512-expansion globs in one invocation charged 1,024 against one budget and the first was reported
  `over-budget`. The budget belongs to a rule's whole `paths:` list; a standalone `--glob` is nobody's
  list. Budget grouping is now a key distinct from the displayed source.

- **The symlink backfill re-admitted files the corpus exclusions had just rejected.** `detect.sh`
  skips an excluded path in the tracked walk, then the backfill loop that recovers symlink-only rules
  added it back because it only asked whether the path was already in the file list -- emitting a
  `SKIP` row *and* a `FILE` row for one path and counting it in both summary totals. `context/corpus.md`
  states exclusions are absolute and applied before any classification; the second entry point now
  enforces the same rule.

- **An absolute index target outside `--root` was reported as not existing.** `ip_index_target_loaded`
  prefixed the root unconditionally, building `<root>//abs/path`, which collapses to a path under the
  root that is not there -- so `reachable` and `write`'s post-write check both said "does not exist"
  about a file plainly present. Easy to hit with the default `--root .` and a `--file` elsewhere.

### Known issue, not fixed here

- `lib/state-key.sh`'s `sha256` helper runs as a non-last pipeline stage, so its `exit 2` on a host
  with neither `sha256sum` nor `shasum` exits only that stage: `cut` reads nothing and the caller
  returns a malformed key with status 0 instead of failing cleanly. The file is byte-identical to the
  canonical `plugins/claude-config/lib/state-key.sh` and shared by six plugins, so the fix belongs
  with the canonical copy and its sync cluster rather than in this plugin's PR. Raised on #3225.

## [0.11.2]

### Fixed

- **`awk -v` mangled every value carrying a backslash, and it broke the suite on CI.** POSIX requires
  a `-v` assignment to process escape sequences, so the two awks disagree on any value containing
  one: gawk drops an unknown escape's backslash (`\[` becomes `[`, with a warning on stderr) and
  reads `\t` as a tab, while mawk passes both through untouched. Three sites were exposed.

  `glob-tools.test.sh`'s `row_field` helper passed the pattern under test through `-v`, so the
  escaped-literal case this suite exists to pin -- `photos \[2024/**` -- had its backslash stripped
  before the field comparison, matched nothing, and returned empty. **This was the real cause of the
  red `plugin-gate` on every CI run of this branch**, and it was invisible locally because this
  container has mawk and the runner has gawk.

  `render-index.sh` passed the generated index block through `-v repl=`, and `detect.sh` passed each
  file path through `-v path=`. Both carry repository-derived text: a rule path containing a
  backslash would have been silently rewritten on the way in, corrupting the written index in the
  first case and misattributing every emitted fact in the second.

  All three now travel through `ENVIRON`, which both implementations pass through literally. The
  whole suite is now run under **both mawk and gawk** -- 242 cases, 0 failures in each -- rather than
  under whichever one the box happens to have.

## [0.11.1]

### Fixed

- **Skill-header orientation counted rules with the open-coded pattern the shared layer replaced.**
  `precompute.sh audit` and the `check` skill's inline injection both ran a bare
  `find .claude/rules`, which is the exact line whose four bugs motivated `lib/discover.sh` in
  0.2.0: it sees only the root tree and only real directories. On a repository with a nested
  `packages/*/.claude/rules` and a symlinked shared set it reports **1** where the gate walks
  **3**. Nothing downstream used the number — the engines were already consolidated — but the
  header is what the model reads before any work starts, and an orientation that understates the
  repository by two thirds sets the wrong expectation for the sweep it introduces. Both sites now
  count through `ip_discover_rules`, and the nested-instruction count through
  `ip_discover_nested_instructions`, so the header and the gate tell one story. Raised in review on
  #3225.

### Changed

- `precompute.sh` gains a `check` mode, so the `check` skill composes its header through the one
  script like every other skill in the plugin rather than open-coding three inline injections.
  Its presence probes drop their backticks to match the `audit` mode's wording.

### Added

- `precompute.sh` gets its own suite (23 cases), covering the count agreement on a fixture that
  hides rules from a root-only `find`, the corpus rules for nested instruction files, and the
  degradation contract every mode owes a skill header: exit 0 and a printable value even where
  there is nothing to read.

## [0.11.0]

### Fixed

Five defects raised in review on #3225, each reproduced first and then fixed. Four were P1.

- **A `.claude/rules` that is itself a symlink was invisible.** The outer `find` required `-type d`
  without `-L`, so a symlinked rules root never matched and the inner symlink-following scan was
  never reached. This is strictly worse than the symlink bug fixed in 0.2.0: that one lost a single
  linked rule, this one loses an **entire shared rule set** — and sharing a whole set by symlink is
  the documented layout. A symlinked `.claude` directory had the same shape one level up. Both are
  now covered.

- **Brace commas inside an inline flow list were treated as list separators.** A valid
  `paths: ["src/*.{ts,tsx}"]` was split into `src/*.{ts` and `tsx}` — two zero-match failures
  reported against a rule that was correct. The parser now splits only at brace depth zero and
  outside quotes.

  **The same bug existed in three copies**, in `glob-tools.sh`, `render-index.sh`, and `detect.sh`,
  so the fix is one parser (`ip_parse_paths` in `lib/discover.sh`) and the deletion of all three.
  Three copies meant three places to fix and three places to drift — the same reasoning that moved
  discovery into that file in 0.2.0.

- **The brace budget was charged per pattern instead of per rule.** The documentation is explicit
  that "a rule's whole `paths:` list shares one budget of 1,000 expanded patterns" — quoted
  correctly in the script's own header while the code reset the counter for every pattern. A rule
  with two 512-expansion globs passed the gate while its combined 1,024 expansions exceed what the
  loader will expand, so `check` reported green for a rule Claude Code silently leaves unexpanded.
  Now tracked as a running total per rule, with a test that the budget does not leak between rules.

- **`verify-load.sh --expect` matched a bare substring.** `rules/rule.md` was reported `MET` when
  the only loaded path was `.../old-rules/rule.md`, letting the empirical verifier emit
  `VERDICT PASS` for a surface that never loaded. For a tool whose entire job is not lying about
  what loaded, a false `MET` is the worst available defect. Matching is now whole-path or
  path-component suffix, with a live-CLI test asserting the near-miss is `MISSING`.

- **The declared `userConfig` options did nothing.** `breadth_max` and `index_max_rows` were
  advertised in the manifest and reported by `setup`, while both scripts hardcoded their defaults
  and only command-line flags had any effect — an option that is documented and inert is worse than
  one that does not exist. Both scripts now read the native `$CLAUDE_PLUGIN_OPTION_<KEY>` mirror,
  fall back to the default on a non-numeric value, and still let an explicit flag win.

### Changed

- `declare -A` replaced with a running counter in `glob-tools.sh`: associative arrays are bash 4+
  and macOS ships 3.2, the same portability trap that `mapfile` hit in 0.4.0.

## [0.10.1]

### Changed

- **The findings artifact declares its stability guarantees, and its owner doc is deliberately not
  written.** Promoting the contract to a `docs/conventions/` cross-plugin seam was considered and
  declined *for now*: the artifact has three consumers, all inside this plugin, so a shared seam
  would fix a shape against requirements that do not exist yet — an interface with one
  implementation is a guess. The convention registry's rule is a deadline ("before a second plugin
  adopts it"), not an instruction to publish early.

  What landed instead is the part that is defensible today: explicit guarantees a future consumer
  can hold (`schema: 1` is a real version; field names and the status vocabulary are fixed within a
  version; fields may be added; identifiers are stable and never reused; the location formula is
  fixed), and the three prerequisites promotion would need — a real second consumer with stated
  needs, a decision on the auto-apply boundary that does not launder the per-item gate, and the
  owner doc landing before that consumer ships.

## [0.10.0]

### Added

- **`delta` skill — report only what moved.** A full audit is worth running rarely and reading
  carefully; this is the lane for the other times. The failure it exists to prevent is specific: a
  re-run that re-presents the same forty findings the operator already worked through trains them to
  skim, and a skimmed report is how a bad migration gets approved.

  Five movement shapes — `new`, `changed`, `broken-glob`, `index-drift`, `stale` — and an explicit
  list of what is *not* movement. **`broken-glob` is the shape that most justifies a cadence**: a
  glob breaks when the code it described is renamed or moved, which is an ordinary refactor nowhere
  near the rules tree, produces no signal at the time, and leaves the rule silently not firing.
  Nothing else in the plugin notices between `check` runs.

  Decisions are respected rigorously: `declined` stays declined and is never resurrected as `new`,
  `changed`, or "for review". Suppression below the noise budget is always **counted in the report**
  — a delta that hides its own filtering is precisely the failure it was built to avoid. A quiet run
  is one line, with no padding to look useful.

## [0.9.0]

### Changed

- **Route-out is operative, not decorative.** The six sibling-plugin boundaries were prose in the
  README and nothing in the skill. They are now presence-gated Skill-tool invocations with a
  documented fallback each, owned by
  [`skills/audit/context/routing-out.md`](skills/audit/context/routing-out.md), plus two rules that
  keep routing from degrading into silent dropping: a routed candidate is reported *as routed*, and
  routing one question never cancels a placement finding on the same section — a section can be both
  misplaced and duplicated.

- **The audit skill practices the disclosure it preaches.** Adding the routing table pushed
  `SKILL.md` to 224 lines, past the soft target, in a plugin whose entire subject is progressive
  disclosure. The routing table and the gotchas moved to spokes behind conditioned pointers; the hub
  is back to 181 lines. `context/gotchas.md` remains a recognized gotchas surface, so the signal is
  relocated rather than lost.

## [0.8.0]

### Added

- **`PostToolUse` index-drift hook (14 contract tests).** Index drift is silent by construction: a
  rule added without regenerating the index is a rule no subagent can reach, and nothing about the
  repository looks wrong until someone runs the gate. This shortens the feedback loop from "next CI
  run" to "next tool call". Advisory and non-blocking — always exits 0, and
  `/instruction-placement:check` remains the authoritative gate.

  **The matcher is `Write|Edit`, which the fleet hook-budget convention counts as always-on**, so
  the hot path was designed and then measured rather than assumed. After the kill switch, the first
  thing the hook does is a substring test on the written path; every write outside a `.claude/rules`
  tree returns before any subprocess, git call, or index render. Measured cost on that path: **~9 ms
  per invocation including bash startup**, against a ≤1 s per-tool-call budget. The suite asserts a
  generous ceiling so an accidental git or render call landing on the hot path fails a test.

  It stays quiet where quiet is right: an in-sync index emits nothing, and a repository that never
  adopted an index is never nagged into adopting one. Kill switch: `index_drift_hook_enabled`.

### Fixed

- **`hook::repo_root` was handed a file path instead of a directory** during development. It returns
  the input unchanged with a non-zero status, which an `|| true` swallowed into a silent no-op — the
  exact failure shape (`hook_non_blocking_error`, hook enforces nothing, nobody notices) that this
  repository's hook conventions exist to prevent. Caught by the drift-detection tests failing while
  every robustness test passed.

## [0.7.1]

### Changed

- **Eval fixtures replace narration.** Four of the audit's six cases were graded against a described
  situation rather than real content, which grades the description as much as the skill. They now
  run against two committed fixtures: a bloated `AGENTS.md` carrying the full spread the rubric has
  to separate — safety rails, path-local conventions, a creation-governing checklist, a derivable
  directory listing — and a contributor guide with genuine conventions buried among history, setup
  prose, and release process, which is the promote lane's actual discrimination problem.

  The two remaining cases keep `narration: true` honestly: both describe repository state (a repo
  with no Rust files; a bare invocation's coverage report) that no single fixture file can express.

## [0.7.0]

### Added

- **`setup` skill and consumer configuration.** The plugin earns one on all three of the setup
  contract's criteria, but one carries the weight: **the index target is an external referent whose
  validity a configuration prompt cannot establish.** A prompt stores the path you typed; it cannot
  tell you Claude Code will never read it. `check` runs the reachability probe and leads with that
  verdict, because it is the single failure every other gate reports green through.

  Also verifies `git` (tracked-file discovery degrades without it) and reports the Claude Code CLI
  and `jq` as *optional* prerequisites that affect only the empirical load probe — "optional,
  absent" and "missing" are stated as different things.

  Configuration reporting names each value's **source**, not just its value: "75 (default)" and
  "75 (configured)" are different facts about a repository, and only one of them explains a
  surprising result.

  `apply` writes nothing on its own. Every remediation here edits a file that steers agent behavior,
  so it presents the exact change and asks — then re-verifies, because an apply that does not
  re-verify has not finished.

- `userConfig`: `breadth_max` (default 75) and `index_max_rows` (default 40). Both have defaults that
  behave, so the plugin still runs with no configuration at all, and `setup` says so rather than
  presenting configuration as a prerequisite to a first audit.

## [0.6.0]

### Added

- **The index has a size posture.** It had none: no cap, no ranking, no truncation. Since the index
  is always-loaded, a large monorepo would have turned the mechanism that *frees* always-loaded
  budget into a consumer of it — and with the adherence claim gone (0.5.0), reachability is now the
  main thing the index is for, so it cannot be allowed to become the bloat it prevents.

  Past `--max-rows` (default 40, roughly a screenful), the index lists that many surfaces
  individually and groups the remainder by directory with a count. What was collapsed is **stated**,
  never silently dropped: a truncated index that reads as complete is the failure mode, and the
  grouped tail still tells a reader where to look and what to do.

## [0.5.0]

### Changed

- **The adherence claim was measured and removed.** This plugin shipped asserting that a convention
  delivered when a matching file is read is followed more reliably than the same text buried in a
  large always-loaded file. `evals/adherence-experiment.sh` tested exactly that, and it did not
  reproduce: **32 trials, two bloat levels, 100% compliance in every cell.** Even a 1,927-line
  always-loaded file — nearly ten times the official 200-line guidance — produced no measurable
  difference against a path-scoped rule.

  The claim is removed from the README and from the audit skill's framing rather than hedged; an
  unmeasured claim that measurement contradicts does not get to survive as a caveat. The plugin's
  justification now rests only on what is demonstrable: context economy, the promote lane (content
  Claude loads *never* has no presence to lose), and index reachability.

  The run's limits are stated as plainly as its result in
  [`evals/adherence-results.md`](evals/adherence-results.md) — the control arm scored 100%, so the
  experiment had a ceiling and could not have detected a smaller effect. Untested: conventions that
  conflict with a strong default or with each other, many rivalrous conventions at once, weaker
  models, and instruction shapes subtler than a crisp checkable rule.

### Added

- **`evals/adherence-experiment.sh`** — the harness, kept so the result can be re-derived rather
  than trusted. Interleaves arms so service drift hits both alike, defines compliance before any
  trial runs, and takes `--filler` to vary bloat. It is built to be able to fail, and did.

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
