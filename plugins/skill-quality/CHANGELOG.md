# Changelog

All notable changes to the `skill-quality` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.17.3]

### Changed

- **`setup`: the post-reconfiguration verification names the Skill tool (#3002).** "verify with
  `/skill-quality:check`" became "verify by invoking `/skill-quality:check` via the Skill tool".
  Wording only.

### Notes

- **No new check for cross-skill phrasing, deliberately (#3002).** The sweep considered a
  criterion enforcing the rubric's cross-skill phrasing rule and declined it: a static scan
  cannot separate an operative chain from a mention, and the separation is the whole rule.
  Measured at the sweep, 1,129 body lines fleet-wide carry a cross-skill `/plugin:skill` token
  and roughly 120 were operative. The reasoning lives in
  `docs/conventions/invocation-mode/README.md` ("Cross-skill invocation phrasing"); check 24 is
  unchanged.

## [0.17.2]

### Changed

- **`check-skill` replays a failed script test's output instead of discarding it.** Check 7 ran each
  `scripts/*.test.sh` with stdout and stderr sent to `/dev/null` and reported only
  `script test failed: <name>`. That is undiagnosable wherever the failure cannot be reproduced by
  hand — a gate whose one CI-visible signal is its own name sends the reader guessing at
  environment differences instead of reading the case that broke. Found the hard way: a generator
  test that passed locally under a fresh clone, the PR merge result, a minimal environment, four
  working directories, and with and without the optional lint tools, while failing only in CI. With
  the output replayed, the cause was one line — an older ShellCheck rejecting `--rcfile` and exiting
  3 ("invoked with bad syntax"), which the test was reading as a lint failure. Success stays silent:
  the reason to suppress was log noise, and that reason does not apply to the run that just went red.

## [0.17.1]

### Fixed

- **`check`: Check 21 no longer silently passes under mawk (#3005).** The fresh-eyes scanner's
  embedded awk program used ERE interval expressions, two of them immediately followed by a group
  (`^ {0,3}(...)`). mawk 1.3.4 panics on that construct — `REcompile() - panic: values still on
  machine stack` — and dies before emitting a single record, so on a stock Debian/Ubuntu box every
  malformed `fresh-eyes-exempt` directive PASSed and the whole check reported a clean run over a
  file it never scanned. mawk 1.3.3, which does not implement intervals at all, degrades the same
  way for the same regexes by matching the braces as literal text. The scanner is now written
  interval-free throughout — the three-space indent cap as three optional spaces, the ordered-marker
  digit cap as one digit plus eight optional ones — preserving the exact CommonMark bounds it
  already enforced. This is the portability shape Check 23 was written to in `#2963`; gawk behavior
  is unchanged, and `check-skill.test.sh` gains 21 passing assertions on mawk with no regressions.
  A source-level guard assertion now fails the suite if an interval returns to any awk-consumed
  regex — the embedded programs' regex literals and the judge regex passed with `-v` — in `{n}`,
  `{n,}` or `{n,m}` form, since mawk panics on an exact-count interval before a group exactly as it
  does on a bounded one. It is scoped to awk rather than the whole file because Bash's own `[[ =~ ]]`
  regexes may use intervals freely, and it is deliberately source-level rather than behavioral
  because a gawk CI runner cannot observe this class of break any other way.

## [0.17.0]

### Added

- **`check`: Check 24 — explicit invocation mode (#2968).** Every skill states
  `disable-model-invocation` explicitly. A marketplace plugin skill (`plugins/*/skills/*`) that
  omits the key FAILs; anywhere else it WARNs, since the absent-key default is already `false` and
  a consumer skill should be informed by this fleet convention rather than broken by it. A
  non-boolean value FAILs everywhere. Class attribution stays hand-verified against
  `docs/conventions/invocation-mode/README.md`: only a `setup` skill's `true` is decidable by a
  static scan (class (ii), setup contract), so every other `true` emits a note rather than a
  warning no scan could clear.

## [0.16.0]

### Added

- **`check`: Check 23 — completion-criteria signal (WARN; advisory heuristic; #2963).** Flags a
  numbered procedure of three or more steps (outside fenced code blocks) whose text carries no
  completion-criteria signal token — the premature-completion shape where a step is markable
  done at the first plausible output. Detects only the absence of any done-condition, never
  grades a stated criterion; broad token set, so only genuinely signal-free procedures fire.
  Fence-aware for both CommonMark fence forms with matching-marker close semantics;
  independent lists split at a numbering restart across a blank line (loose ascending lists
  stay one block). Seven test cases: signal-free warns, done-condition silent, both fence
  forms ignored, mixed fence markers stay masked, adjacent short lists split, loose list
  still warns.
  The audit-side half of the course lane 7 completion-criteria adoption — the write-side
  doctrine is `docs-hygiene:write-for-agents` 0.17.0 (#2962), and the check's SKILL.md gotcha
  entry points authors there via the Skill tool.

## [0.15.13]

### Added

- **`check`: cross-skill invocation doctrine (#2940).** Documents one-skill-per-call and the
  invocation-reach invariant (do not Skill-tool-invoke `disable-model-invocation: true`
  targets — tell the user to run `/plugin:skill`). Standing automated check deferred; eval
  coverage extended.

## [0.15.12]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.15.11]

### Fixed

- **Eval-quality Q4 no longer silent on `files: []` + prose-only paths (#2746).**
  `check-evals-quality.sh` still FAILs unresolvable/`..`/absolute entries in the
  declared `files` array. It now also WARNs when `files` is empty/absent, the case
  is not `narration: true`, and `prompt`/`expected_output` contain a path-shaped
  token (`dir/…/file.ext`) that resolves to nothing under the skill or evals
  directory — the dodge that let compress evals 3/8/10 clear the gate while naming
  unreachable paths. Opt out with `narration: true` (schema field added) or declare
  a real fixture in `files`. Branch-like tokens and bare filenames stay out of scope.
  Host-shaped skips require a DNS-like first segment ending in an alphabetic label
  (so `v1.2/schema/config.json` stays in scope); the PROSE escape gate keeps only
  the reachable `../` check before the existence WARN.

## [0.15.10]

### Fixed

- **Static gates run against non-git plugin-cache installs (#2619).** `check-skill.sh` and
  `check-listing-budget.sh` no longer exit 2 with `Error: not in a git repo` when cwd is outside
  a git repository. Marketplace cache trees are plain directories; with
  `CHECK_SKILL_SKILLS_ROOT` (or `CLAUDE_PROJECT_DIR`, or an explicit listing-budget root) the
  non-git checks still run. Git-backed checks (3/8/9/13) skip with a note. Exit 2 remains only
  when no skills root can be resolved at all.

## [0.15.9]

### Changed

- **Docs:** qualify actionable `/plugin configure` examples in README and setup SKILL
  (`skill-quality@<marketplace>`; generated blocks use `@<marketplace>`) per Test E (#1360).

## [0.15.8]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.15.7]

### Added

- **Evals-presence ratchet for changed skills (#530 stage 1).** `check-skill.sh` accepts
  `--require-evals` (or `CHECK_SKILL_REQUIRE_EVALS=1`) and FAILs when `evals/evals.json` is
  missing for any skill shape. `check-changed-skills.sh` forwards that flag when a PR's
  changed set includes a new or modified `SKILL.md`, so untouched legacy skills stay green
  until edited. Default ad-hoc check behavior remains WARN-only for action-router-shaped
  skills.

## [0.15.6]

### Changed

- **Check 21 parsing contract narrowed (#1493).** Inline code spans, backslash escapes, and
  cross-line span carries are no longer modeled — a line with a backtick run or a backslash-escaped
  `<` declines directive hard verdicts and is skipped by the Form 1 and judgment detectors rather
  than attempting CommonMark pairing in `awk`. Fenced code blocks, container-nested fences, and
  indented-code ambiguity handling are unchanged. Spec:
  `skills/check/reference/fresh-eyes-declarations.md`.

### Fixed

- **Check 21 carries multi-line HTML comment state.** Delegation wording split across a multi-line
  comment (`<!--` on one line, body on the next, `-->` on a third) no longer satisfies Form 1 while
  the judgment line still WARNs. Directive classification still runs before comment stripping so
  `fresh-eyes-exempt` directives remain visible.

## [0.15.5]

### Fixed

- **Check 12 accepts a populated `when_to_use` with single-quoted triggers.** Skills no longer need
  a redundant `Use when:` prefix in `description` when triggers are already declared in
  `when_to_use`.

## [0.15.4]

### Changed

- **Two review findings on 0.15.3's single-pass scan, both verified before acting rather than taken
  on faith. Output is unchanged, and that was re-proved rather than assumed.**
  - The `strip_trailing_nl` wrapping the `disable-model-invocation` read was dead weight on every
    scanned file. `normalize_bool` opens with `trim_ws`, whose trailing `sub` uses `[[:space:]]` —
    a class that matches a newline — so the strip removed a strict subset of what the very next
    call removed. Confirmed by running both compositions over a value ending in newline plus
    spaces: identical output, and `[[:space:]]+$` strips a bare newline on its own.

    It is deliberately **not** removed from the `description` and `when_to_use` reads, where it runs
    before `strip_quotes`, which trims nothing: a value still ending in a newline has that newline
    as its last character, so the closing quote never matches and the quote marks would survive into
    the measured length. The asymmetry now carries a comment saying so, since it otherwise reads as
    an oversight worth fixing.
  - The FAIL check 2 message was an apostrophe dropped to avoid closing the enclosing
    single-quoted awk program, and read as a typo. Rephrased to refer to check 2 without
    an apostrophe rather than escaped — one apostrophe does not justify a `'"'"'` sequence
    inside an awk program.

  Whitespace handling is exactly where a "free" edit silently moves a number, so byte-identity was
  re-established rather than presumed: the per-file contribution rows were re-diffed against the
  pre-port baseline — **144/144 identical**, report identical.

## [0.15.3]

### Fixed

- **`check-listing-budget.sh` measures in ONE `awk` pass, so the command the quarterly routine tells
  an operator to run can actually finish (#2216).** `bash check-listing-budget.sh plugins/*/skills`
  took **289s** on Windows (Git Bash) and, run in the foreground by an agent, was **killed at 180s
  with exit 143 and zero output**. Re-measured at this branch's merge base before the port: **232s**
  for the same command. The cause was process-spawn cost, not the machine — the per-file loop spent
  at least **eleven forked subshells and five external process execs** (4x `awk`, 1x `tr`) on every
  one of the repo's ~200 `SKILL.md` files, on the order of 2,000 spawns. Process creation costs
  roughly two orders of magnitude more on Windows than on Linux, which is why CI (`ubuntu-24.04`)
  never surfaced it. That command is verbatim what #2023's procedure and
  `.github/recurring-schedule.json`'s `listing-budget-watch` row instruct, so on the one machine
  where the routine is actually driven, a report-only drift watch silently produced nothing.

  The same run now takes **2.2s** — and the output is **byte-identical**, which is the point rather
  than a hope. Both implementations were run over the same tree and their per-file contribution rows
  diffed, not just their reports: **144/144 rows identical**, aggregate 94,468 identical, top-10
  ordering identical. Per-file rows are the load-bearing comparison — two files with offsetting
  extraction errors produce a matching aggregate and a clean report diff while the parser is broken.

  This is a **port, not a rewrite**: the awk program reimplements, behaviour for behaviour, the four
  helpers the loop shelled out to — `skill_frontmatter::extract`, `::field` (block-scalar unfolding
  for `|` and `>`, and the quote-aware trailing-comment strip including the doubled-single-quote
  case), `::strip_quotes` (one outer layer, double OR single, never both), and
  `normalize_bool`/`trim_ws`. Two behaviours the old pipeline got free from command substitution are
  reproduced explicitly and commented as such: trailing newlines stripped from the extracted
  frontmatter (so a trailing blank line cannot add a separator inside a block scalar, and an
  all-blank block counts as no frontmatter), and trailing newlines stripped from each field's value.
  Because corpus equivalence is not parser equivalence, four new fixtures pin the shapes most likely
  to diverge: a literal `|` block with a trailing blank, a single-quoted scalar with a doubled quote
  plus a trailing comment, and a multibyte description asserted **as an equivalence against the
  shell's own `${#var}`** rather than a hardcoded count — awk `length()` and `${#var}` can disagree
  where awk counts bytes and the shell counts characters, and a fixed number would encode one
  environment's answer and fail elsewhere for the wrong reason.

  A fifth case bounds the wall clock over a 200-file corpus at **30s**. The bound is deliberately
  very loose against a ~1s target: this runs in required CI, and a tight timing assertion is a flaky
  gate — worse than the defect it guards. It fails only on a return to per-file process spawning,
  which is two orders of magnitude away.

  `skill-frontmatter.sh` is no longer sourced here (its helpers are the per-call execs that caused
  this); the library file is unchanged and `check-skill.sh` remains its consumer. No flag, no
  option, and no output format changed.

## [0.15.2]

### Changed

- **Two deferred judgment calls about `check-skill.sh` are now decided at their own sites**, so
  neither gets re-litigated from a false premise. No behavior changes — comments only.
  - **Check 5 keeps its backtick-form extraction.** #2179 deferred narrowing to markdown-link
    targets as "a separate call"; the call is made against measurement. Over the 196-skill corpus,
    122 unique backtick-form refs across 39 skills have no link form anywhere in the same
    `SKILL.md`, and all 122 resolve to a real file — narrowing would delete that coverage at zero
    observed false positives. The comment also corrects the premise that keeps resurfacing: this
    check never matched bare paths in prose, only backtick-delimited refs and `](…)` link targets,
    both scoped to the `INTERNAL_DIRS` allowlist.
  - **Check 12's standing 4-skill warning floor is intentional**, and no
    `disable-model-invocation` carve-out is added. Upstream states that a dmi-true skill's
    "Description not in context, full skill loads when you invoke", so trigger phrasing there
    cannot route anything; each of the four was re-checked for a stranded phrase and none is
    stranded. Exempting dmi-true would hide the `kindle-dedrm` failure mode — a phrase reachable
    only from a skill the model can never match.

## [0.15.1]

### Fixed

- **A cross-skill citation reported as a broken internal ref pointed at the wrong directory.**
  Check 5 resolves every bare `context/…`-shaped path against the CITING skill's own directory, so
  a skill citing a sibling skill's supporting file failed with "no such file under the skill dir"
  while the file plainly existed one directory over. The message sent the author looking for the
  file where it could never be. When the unresolved path does resolve under a sibling skill of the
  same skills root, the finding now also names that sibling and the citation form that works —
  `${CLAUDE_PLUGIN_ROOT}/skills/<sibling>/<path>` in a plugin-shaped root, `../<sibling>/<path>`
  outside one, where that variable is undefined. Still a FAIL: the bare form really does resolve
  against the citing skill, so it is wrong regardless of where the file lives. The sibling hit is
  evidence, not proof — this check deliberately extracts prose and inline-code refs, so a generic
  path can collide with an unrelated same-named sibling file — so the original hand-verify wording
  is kept and the suggestion is phrased conditionally. A path no sibling hosts is unchanged.
  Extraction is unchanged too: prose and inline-code refs are still in scope, deliberately.

## [0.15.0]

### Changed

- **Check 1 no longer requires a frontmatter `name`.** The field is optional and defaults to the
  directory name, which is already what the checker resolves a skill by. A declared name still has
  to be kebab-case and match its directory — a divergent one silently relocates the invocation.
- **Check 1 warns when a plugin skill's `name` repeats its directory.** There the field is not
  inert: it registers the bare `/<name>` alongside the namespaced command, and the picker appends
  that alias in parentheses to any row whose typed prefix matches it. Advisory, since a consumer may
  want the bare alias.

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.14.1]

### Fixed

- **A zero-padded integer override was parsed as octal.** `require_positive_number`'s
  `^[0-9]+$` accepts a padded value, but bash arithmetic and `printf %d` then read it in
  base 8: `CHECK_SKILL_LISTING_BUDGET_CHARS=0123` silently became 83, and `=08` was not a
  valid octal literal at all — it emitted invalid-octal diagnostics, rendered the budget as
  `0`, and still reported `OK` and exited 0. `CHECK_SKILL_LISTING_MAX_DESC_CHARS=010`
  likewise capped entries at 8 instead of the requested 10. Accepted integer overrides are
  now forced to base 10 at the one place the digits become a number. The ratio and fraction
  overrides are deliberately untouched — `0.01` is the documented default fraction and must
  keep its leading zero, and both reach only `awk`, which has no octal input.
- **A trailing YAML comment was measured as part of `description` / `when_to_use`.**
  `skill_frontmatter::field` returned the comment along with the value, which also hid the
  surrounding quotes from `strip_quotes` so the quoting was counted too — a fixture with
  commented `description` and `when_to_use` scalars measured 52 characters instead of 15,
  producing false overflow warnings and wrong contributor sizes. The field extractor now
  cuts a trailing comment quote-aware, matching the YAML reader the harness actually loads
  frontmatter with. Confined to the plain/flow branch: inside a block scalar a `#` is
  content, never a comment. This also corrects the per-skill entry cap (Check 2) and the
  trigger-preservation diff, which read the same fields.

## [0.14.0]

### Added

- **`check-evals-quality.sh` — deterministic eval-quality lint beyond the
  schema**, run by `validate-evals` after schema validation and by the
  marketplace's `skill-quality-gate` CI lane over every eval set. The
  schema proves a case is structurally gradeable; this lint (bash + jq,
  no model invocation) flags content that undermines grading. FAIL tier:
  duplicate case ids (Q1) and names (Q2), empty/whitespace-only
  `expectations`/`assertions` items (Q3), `files` fixture entries that
  resolve to no path under the skill or evals directory (Q4). WARN tier
  (advisory, never fails the run): a case carrying both `expectations`
  and `assertions` (Q5), two cases sharing an identical prompt and files
  (Q6), vague whole-item criterion phrasing like "the output is good"
  (Q7), a thin sole-criterion `expected_output` (Q8), and a set with no
  refusal/guardrail or anti-pattern case per the playbook's rich form
  (Q9). Deliberately does NOT flag low case count — the marketplace's low
  volume is a recorded divergence from Anthropic's evaluation guidance,
  revisited when the deferred eval runner lands. Ships with a black-box
  contract test (`check-evals-quality.test.sh`, one seeded defect per
  fixture). The repo-wide baseline run found 2 real Q4 defects (prose
  annotations inside `files` paths, fixed at source) and 11 accepted
  advisory warnings.

## [0.13.0]

### Changed

- **The evals schema now requires a non-empty grading criterion on every
  case**: at least one of `expected_output` (non-empty string),
  `expectations` (non-empty array), or `assertions` (non-empty array)
  must be present (`anyOf` on the case object). Previously a case
  validated with only `id` + `prompt` — an eval with no success
  criterion, which contradicts the eval anatomy in Anthropic's evaluation
  guidance (a case that cannot be graded is not an eval; guidance now
  indexed in `docs/OFFICIAL-DOCS.md`). The `check` skill's
  validator-free structural fallback and the README schema contract state
  the same requirement, so all three surfaces agree. All 1,050 existing
  cases across the marketplace already satisfy the requirement, so no
  fixture changes; downstream consumers with criterion-free cases will
  now get a validation failure from `validate-evals` pointing at the
  case to fix.

## [0.12.2]

### Fixed

- **The vendor-sync-age check (Check 17) had no BSD `date` fallback at
  all** — `date -u -d "$SYNCED_VAL" +%s` silently failed and the whole
  advisory check no-op'd on BSD/macOS with no warning. Added a co-located
  `date -j -f '%Y-%m-%d' ...` BSD fallback, annotated `portability-ok:`
  since the shell-portability-lint gate's `date -d` guard only recognizes
  the `readlink`/`realpath` shape today.

## [0.12.1]

### Added

- **Check 22 — `metadata.summary` length cap.** When the key is present, a value
  longer than 100 Unicode codepoints FAILs; an absent key emits nothing. The key is the
  generated skill cheat sheet's row source, and the cap keeps rows scannable. Length is
  counted in codepoints, not bytes — the measurement site pins a UTF-8 locale (fleet
  summaries carry em-dashes) — and the value is read via
  `skill_frontmatter::metadata_field` + `strip_quotes`, so the trailing-comment strip
  matches how the sheet generator reads it.

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
  where a miss costs one nudge. Ambiguity cuts both ways: such a directive also cannot satisfy a
  nearby judgment step, so a literal exemption inside an indented example does not silence the
  warning that step deserves. This posture is specific to check 21 — it must not be carried into
  a gate whose verdict is a security decision.

### Fixed

- **The directive name requires a terminator.** A prefix-only match read an ordinary comment about
  a longer identifier (`<!-- fresh-eyes-exemption is explained here -->`) as a directive and FAILed
  the skill on prose. The name must now be followed by `:`, whitespace, or `-->`.
- **YAML frontmatter is no longer parsed as markdown.** A block-scalar `description` carrying an
  example fence opened a fence that the closing `---` never ended, so the whole body was suppressed
  and the file passed silently with its judgment language and any malformed directive unexamined.
  The region is skipped and every structural carry resets at its terminator. Skipping it also drops
  four spurious judgment hits measured across this marketplace — all in a `description` field, which
  is listing metadata rather than a procedural step, so three advisory WARNs and one note go with
  them. No skill's pass/fail verdict changes.
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
