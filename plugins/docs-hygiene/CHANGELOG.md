# Changelog — docs-hygiene plugin

## [0.16.0]

### Added

- **New skill `audit-progressive-disclosure`:** read-only classifier grading
  agent-facing instruction markdown against a three-tier load-cost model
  (always-loaded / invocation-loaded / on-demand). Seven finding shapes in two
  lanes — split opportunities (`oversize`, `mixed-concerns`, `tier-mismatch`)
  and hub/spoke structure defects (`blind-pointer`, `orphan-spoke`,
  `deep-nesting`, `missing-toc`) — with audit-noise-style Tier 1/2/3 semantics
  and per-shape treatment guidance. Ships a deterministic `detect.sh` fact
  emitter (sizes, heading census, load-tier classification, pointer inventory,
  orphan/chain detection) with a 28-case contract test, a
  `context/tier-model.md` reference (official numbers, split triggers,
  pointer-quality criteria, citation posture), evals with three fixture sets,
  and participation in the shared clean-tree fallback. Design contract locked
  via interview + verified multi-source research over Anthropic's prescribed
  progressive-disclosure model (#2888; the contract slice was pruned before
  merge per the topic-docs convention). Notable postures: thresholds advisory
  (ceilings, not targets),
  two-band TOC treatment reflecting the official 100-vs-300-line
  inconsistency, never flagging small single-file skills for lacking spokes,
  and flagging pointer chains deeper than one level.

## [0.15.2]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.15.1]

### Fixed

- **audit-derivability route follow-ups:** point the status board's
  `templates/sources.md` row at the knowledge skill's renamed `video-digest`
  path.

## [0.15.0]

### Fixed

- **compress (plugin-quality audit #2745):** rewrite caveman Step B as
  cross-tool-call steps (no EXIT trap / non-persistent `$tempdir`); map
  detector `unknown` → Edit fallback; require `enabled: true` (prefer
  `caveman@caveman`) in `detect-caveman.sh`; fix pre-computed `|| echo none`
  pipeline; name audit-table destination under `${CLAUDE_PLUGIN_DATA}/audit/`;
  reword signal 6 as an owned curated token list; annotate taxonomy/LATITUDE
  drift (batch = word-level; Edit fallback = full matrix); note drifted-skill
  matrix niche is unreachable via signal 1; add yield circuit breaker + top-10
  interview default; ship `scripts/audit-scan.sh` + contract tests; point eval 8
  at `evals/fixtures/terse-agent.md`; widen fixture-gate conventions; soft-block
  wording in `integration.md`; record deliberate `disable-model-invocation:
  false`.

## [0.14.7]

### Added

- **audit-derivability route follow-ups:** in-tree status board
  (`context/derivability-route-followups.md`) for the 174 route-to-sibling
  annotations from the 2026-08-15 repo-wide sweep — noise routes closed after
  re-scan + one Sources relocation; extract-ssot routes triaged
  (synced-cluster / functional-scaffold / changelog-parity / pending) without
  opening new issues (#2735).

## [0.14.6]

### Added

- **Shared clean-tree / no-scope fallback contract**
  (`context/clean-tree-fallback.md`): the offer → confirm → prescribed-defaults
  → decline-or-silence-no-op skeleton that audit-noise 0.12.0 introduced, now
  cited by `audit-noise`, `audit-derivability`, `audit-encapsulation`,
  `compress`, and `extract-ssot`, with deliberate divergences recorded
  (compress stays mutating/audit-first; encapsulation triggers on "no inherited
  scope", not only a clean tree).

### Changed

- **compress `audit` on a clean tree** offers the confirmation-gated free
  corpus audit (report-only) instead of the friendly no-op, matching the
  sibling audit skills (#2734).

## [0.14.5]

### Fixed

- **audit-noise detect:** scanner exemption gaps — skip YAML frontmatter; require
  opt-out markers to be well-formed HTML comment lines (prose mentions no longer
  swallow following content); skip fenced code blocks and strip inline-code spans
  for citation/enum/scope matching (ghost-ref still sees unwrapped path text);
  toggle section exemption on any ATX heading level so `### Sources` exempts and
  an H1 after `## Sources` ends the exemption. Also resolve relative targets
  before `cd` to the repo root and parse spaced filenames from `git status`
  porcelain without `$NF` (#2742).

## [0.14.4]

### Fixed

- **audit-noise detect:** hoist + export convention-root resolution once per
  run so `AUDIT_NOISE_CONTRACT_ROOT` survives into the ghost-ref exemption
  check (auditor F6 — a configured contract root's bare `reviews/` /
  `handoffs/` / `running-retros/` child no longer inherits the memory-root
  exemption). Per-line shape detection now uses nameref helpers instead of
  command substitutions in the hot loop (the root cause of repo-wide scan
  timeouts). `--offset` / `--limit` chunk the sorted target list so
  orchestration can fan out one process per chunk without a per-file shell
  loop (#2741).
  Missing values for `--offset`/`--limit`/`--paths-file` now exit 2 instead of
  hanging; leading-zero chunk values are normalized as decimal before arithmetic.

## [0.14.3]

### Fixed

- **audit-encapsulation detect:** relative-path cites into skill-private surfaces
  are no longer invisible. The detector matches bare `skills/<x>/...` (plugin
  README short links, including heading anchors) and `../`-prefixed cites whose
  lexical resolution lands on a private skill surface (sibling-skill links that
  never spell `skills/` in the cite text). Scripts/ carve-out and self-citation
  filtering cover the relative forms; scripts/ carve-out matches citation text
  only (not the citing file path). Regression fixtures pin both shapes so a
  future pattern regression cannot return a silent empty again (#2716).

## [0.14.2]

### Fixed

- **audit-encapsulation detect:** treat `detect.sh` as a candidate enumerator —
  summary keys are `raw` / `mech-filtered` / `candidates`, exit 1 means
  candidates exist (not adjudicated violations), and contract/SKILL/`--help`
  language no longer invites hard-gating CI on that exit code alone. Widen the
  ERE path class so uppercase / single-char / digit-leading / underscore-leading
  skill and subdir names match (F3), while restricting segments to
  `[A-Za-z0-9_.-]+` so multi-root prose lists cannot span whitespace/punctuation
  into a false hit. Document `plugins/` in the scan-scope
  sentence and add a Recheck-triggers row for detect.sh scope drift (F5). Drop
  the unreachable `plugins/cache/` mechanical-filter branch and fix the docs
  that claimed it fired (F7). Disclose the relative-path blind spot as #2716
  (not fixed here) (#2728).

## [0.14.1]

### Fixed

- **audit-noise:** bare concern-scoped root exemption now includes
  `.work/running-retros/` alongside `.work/handoffs/` and `.work/reviews/`,
  matching the topic-docs Memory, concern-scoped tier roster (convention 2.4.4).
  Concrete children under any of those roots still flag as ghost-refs. A
  sentence-ending period after the trailing slash (`.work/running-retros/.`)
  stays bare; a hidden-file child (`.work/running-retros/.keep`) still flags
  (#2730).

## [0.14.0]

### Added

- **extract-ssot: bare invocations confirm scope before surveying.** A bare
  `/docs-hygiene:extract-ssot` with no working notes, no argument, and no conversation-implied
  scope now asks the user (prescribed defaults, recommended option first) instead of
  auto-dispatching the exhaustive survey; non-interactive sessions without an explicit scope report
  options and stop.
- **extract-ssot: orchestrated whole-repo mode (`context/orchestrated-mode.md`).** Defaults for
  multi-agent batches at whole-repo scale: single-survey inventory, worker tiering, a static
  conservative concurrency ceiling (default 2 — subscription rate-limit windows are shared and
  usually unobservable), the verbatim-inlined rate-limit-guard operable floor with
  between-dispatch checks when the guard's snapshot is present, and wave-committed cadence.
  `actions/batch.md` Step 6 and the identify pre-flight now route through it.
- **extract-ssot:** eval 7 covers the bare confirm-scope gate (no auto-dispatch; prescribed
  defaults including path/glob-scoped survey; orchestrated-mode reference).
- **extract-ssot orchestrated-mode:** rate-limit capability detection matches the reader
  contract's per-window fail-open (one malformed window does not suppress a valid sibling trip)
  and reactive-only mode consumes `stop-events.jsonl` as well as local error text.

## [0.13.0]

### Changed

- **`audit-derivability`: the empty-target no-op now offers a repo-wide sweep.** With no argument
  and a clean tree the skill previously dead-ended ("no uncommitted .md files"). It now reports
  that, then offers — confirmation-gated, never unprompted — escalation to a corpus sweep of all
  tracked markdown, with prescribed defaults (tracked `.md` scope, batched read-only subagents, low
  bounded concurrency, capped spot-tests) presented as pre-filled interview answers. Decline or
  silence preserves the old no-op outcome.
- **`audit-derivability`: `sweep` batches large corpora.** Doc-by-doc fan-out stays for a small
  corpus; a large one now groups ~15-25 documents per subagent by directory affinity, so a
  1000-doc repo needs tens of agents rather than a thousand. Default concurrency is pinned low
  (3-4) — rate-limit headroom over wall-clock.
- **`audit-derivability`: fixes from a plugin-quality audit of the skill's first full-repo run**
  (1131 docs; 7 of 11 actionable verdicts were judged wrong or inapplicable on apply). The scoped
  `sweep` enumeration used two OR'd pathspecs and silently escalated to the whole repo — now one
  combined pathspec, with the trap named, plus a report-scope-and-count-before-fan-out guard.
  Functional artifacts (checklist templates, eval fixtures, scaffolds a component consumes at
  runtime) are now an explicit `out-of-scope` disposition with a one-line test — the source of five
  wrong verdicts. Actionable verdicts on empty/near-empty files now require a `git log`
  deliberate-state check (the empty unhobble-baseline `CLAUDE.md` case). `convert-to-pointer`
  verdicts must verify their recommended anchor exists (one shipped citing nonexistent scripts).
  Sweeps route same-basename/near-identical files into one batch and reconcile divergent verdicts
  (the linux/macos placeholder split), sample keep verdicts so false-keeps are bounded, and defer
  scope exclusions to `extract-ssot`'s codified list instead of a drifted paraphrase. The
  read-only hard rule is scoped to the repository (scratchpad ledgers are sanctioned); concurrency
  is a ceiling the runtime may cap below; the internal #1258 citation is qualified as internal;
  the pre-computed pipeline's dead `|| echo` fallback is fixed; the aggregate line gains
  routed-to-sibling and out-of-scope slots; three regression evals added (scaffold, deliberate
  state, anchor verification) and eval ids reordered.
- **`audit-derivability`: corpus output is bounded and the spot-test cap defers, never waives.**
  Sweep subagents write per-document detail to batch ledger files; the reply carries only the
  aggregate, the actionable subset (confirmed vs provisional), and ledger pointers — so a large
  corpus cannot blow the parent context or one reply. A load-bearing `delete`/`convert-to-pointer`
  verdict past the spot-test cap is provisional and excluded from actionable routing until its
  deferred spot-test runs, reconciling the cap with the mandatory spot-test hard rule (Codex
  review, #2695).

## [0.12.2]

### Added

- **compress:** Audit heuristic signal 6 — flavor-token density per kilo-word. A repo authored
  under standing prose discipline is lean without citing any convention: the 2026-08-15
  authoring-repo run sent 9 signal-5-classified files (0-7 flavor-tokens/kw) to compression and
  all 9 reverted at 0.02-0.4% yield, while the skill's deliberately-verbose fixtures measure
  50-60/kw. Density < 5/kw now forces SKIP (expected ≤ 3%). This is the "add a 6th signal"
  branch of the pre-existing recheck trigger for consistently under-yielding signal-5 files.
- **compress:** Target-validation gate 5 — during the mutating action's ENUMERATED sweeps
  (any target set the user did not name file-by-file: the empty-arg uncommitted-`.md` batch,
  directory expansion, or the repo-wide interview), paths under `evals/fixtures/` skip with
  `reason=fixture`. Fixture verbosity is deliberate test input; compressing it corrupts the eval.
  Explicitly-named single-file targets and the read-only audit action bypass the gate (naming a
  fixture is an intentional act, same philosophy as `--force`).
- **compress:** Eval scenarios 7-9 covering the three new branches: the interview fallback
  (offer, decline-exits-no-op, bounded audit output, no edit before confirmation), a signal-6
  density SKIP, and a fixture-path skip (review finding on #2700).

### Changed

- **compress:** Empty-target + clean-tree invocations in interactive sessions now fall back to a
  confirmation-gated repo-wide interview — offer, free mechanical audit (aggregates + a
  deterministic top-20 excerpt inline; full per-file table lexically sorted to a file, per the
  determinism hard rule), scope/concurrency interview with prescribed defaults
  (all COMPRESS-classified highest-yield-first; 2 concurrent subagents; always-loaded files
  excluded) — instead of dead-ending at the friendly no-op. Non-interactive contexts (subagent,
  headless/CI) keep the no-op. Entry path only; per-file hard rules (semantic-diff dispatch,
  revert pass, markdownlint, `<3%` rule) are unchanged.
- **compress:** The interview fallback's audit step bounds its inline output — aggregate counts,
  dispatch-cost estimate, and top-20 highest-yield rows inline; the full per-file table goes to a
  file. On a large repo the full table runs to hundreds of KB and would truncate the confirmation
  prompt it feeds (Codex review finding on #2700).

## [0.12.1]

### Added

- **`audit-encapsulation`: no-scope confirmation + `sweep` action.** A bare invocation with no
  inherited working set — no diff in flight, no prior audit notes, nothing narrowing the scope —
  now asks ONE confirmation before the repo-wide run, presenting prescribed defaults (scope: entire
  tracked repo; mode: detect + classify only; worker fan-out: off, capped at 2–3 concurrent workers
  when the user opts in and no rate-limit telemetry is readable — pacing resolves from the
  `rate-limit-guard` plugin's reader contract when its snapshot is present). The new `sweep`
  argument is the explicit opt-in that skips the confirmation and runs the repo-wide detect
  immediately. Eval cases 7–8 pin both behaviors.

## [0.12.0]

### Fixed

- **audit-noise:** `detect.sh` now honors the documented scope of the opt-out markers.
  `<!-- markdown-discipline-ignore -->` suppresses the whole next paragraph (through the next blank
  line) instead of only the next line, and `<!-- markdown-discipline-ignore-line -->` is
  distinguished from the bare form. Found when repo-wide-run markers on multi-line paragraphs
  failed to suppress their wrapped lines.

### Changed

- **audit-noise:** hard rules tightened from first-run findings — Tier 3 explicitly carries no
  treatment; the `-line` opt-out marker's exact-next-line semantics are documented; the ghost-ref
  treatment accepts a carrying/pruning PR number as a durable pointer alongside commit-SHA
  permalinks; the judgment pass's recurring dismissal grounds (fictional example slugs, vendored
  baselines, delete-instruction targets, self-matches) are codified; and `detect.sh` now skips
  `CHANGELOG.md` by basename, matching the long-documented exemption.
- **audit-noise:** the clean-tree default is no longer a silent no-op. With no target and a clean
  tree the skill now offers a confirmation-gated repo-wide audit with prescribed defaults
  (fixture/changelog exclusions, slice sectioning, chunked scan, flagged-files-only judgment
  fan-out with a fresh-context verification pass, report-first order). Unattended runs surface the
  offer as blocked instead of launching. Shaped by the first repo-wide run (2026-08-15: 1027 files,
  55 scanner candidates, 37 verified findings).

## [0.11.3]

### Changed

- **rename-references:** Form 13 `/plugin configure` examples and eval fixtures now use the
  marketplace-qualified id (`<old>@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360).
- **Fleet docs sweep:** actionable `/plugin configure` guidance across consumer-facing plugin
  READMEs and setup skills now uses `@<marketplace>` (or `@<marketplace>` in generated blocks).

## [0.11.2]

### Fixed

- **`rename-references` Form 14 missed title-cased ATX headings (#1394).** The ATX and Setext
  title alternatives now carry `(?i)` so `# Re-Anchor` matches a container named `re-anchor`
  instead of falling through to bare Form 2. Declaration alternatives stay case-sensitive;
  `audit.md` warns against global `-i`.

## [0.11.1]

### Fixed

- **`audit-encapsulation/detect.sh` scanned vacuously in marketplace monorepos (#1889).** The
  private-surface pattern anchored only on `.claude/skills/`; this repository authors skills under
  `plugins/<plugin>/skills/`. The detector now matches both layouts, includes `plugins/` in the scan
  scope, applies the scripts/ carve-out and self-citation filter to plugin paths, and ships a
  positive-control fixture test so a future pattern regression cannot return a silent empty again.

## [0.11.0]

### Fixed

- **`/docs-hygiene:audit-noise`'s detector grant worked, but only by accident.**
  `Bash(bash *audit-noise/scripts/detect.sh*)` matched the body's
  `bash "${CLAUDE_SKILL_DIR}/scripts/detect.sh"` because its leading and trailing wildcards absorbed
  both the `bash` wrapper and the quotes around the path. That is the wildcarded-interpreter shape
  auto mode drops outright, and a rule anchored on a bare wrapper name matches that name at *any*
  path, including an unvetted copy.

  The obvious repair — drop `bash` from the rule — would have been a straight **regression** here,
  from a working grant to a broken one. `bash` is not among the wrappers Claude Code strips before
  matching (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`), so a rule
  without it stops matching a body that still says `bash <path>`; and removing the wildcards without
  unquoting the body breaks the match a second way. The change is therefore **paired**: the body
  invokes the script directly and unquoted, and the rule names that same string,
  `Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)` — narrow, anchored to this skill's own directory,
  and carried over into auto mode rather than dropped.

### Changed

- **The skill now grants the read-only commands its pre-compute pipes through** (`grep`, `head`,
  `echo`). A permission rule must match each subcommand of a compound command independently, so the
  script grant alone left the surrounding pipeline uncovered and the pre-compute prompted anyway.

### Added

- **`scripts/allowed-tools-pairing.test.sh`**, asserting the contract the fix establishes: no
  interpreter-led grant and no `${CLAUDE_PLUGIN_ROOT}` in `allowed-tools`, every bundled-script
  invocation in the skill's markdown unquoted and free of a `bash` wrapper, and every granted script
  present, executable, and actually invoked by a body.

## [0.10.1]

### Changed

- **`/docs-hygiene:compress`'s trigger phrases are now single-quoted.** Same cause as the debugging
  plugin's: escaped double quotes inside a double-quoted YAML scalar are not tracked by the
  skill-quality gate's trigger-drop protection, so `'compress this doc'`, `'tighten markdown'`,
  `'cut prose'`, `'shorten without losing meaning'` and `'trim onboarding doc'` carried no
  regression cover. Quoting only; wording unchanged.

## [0.10.0]

### Changed

- **`audit-derivability`: listing description tightened (1,161 → 876 chars)** — trimmed the
  explanatory prose from the frontmatter `description` toward the shared skill-listing budget
  (claude-code-plugins#2022, option 2). Every single-quoted trigger phrase is preserved verbatim
  (skill-quality check 3); the four-factor rubric and verdict classes are unchanged in the body.

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.9.6]

### Changed

- **`extract-ssot`'s `identify` survey prompt drops two emphasis decorations.** "Apply STRICT Tier 0
  discipline" and the "— CRITICAL" heading suffix on the discrimination rules are redundant with the
  structure that already carries that weight: the numbered forms table and the required per-candidate
  evidence fields. The load-bearing requirements — each candidate MUST be classified by repetition
  form, and Pass B semantic clustering being required rather than optional — are untouched.

## [0.9.5]

### Fixed

- **`extract-ssot`'s volatility gate no longer rests on a cache-invalidation mechanism that does
  not operate on the surface it scopes to** (docs-hygiene 0.9.4 → 0.9.5). Anti-pattern #9 was
  "Cache invalidation cascade": extracting into an always-loaded file that gets edited often meant
  "downstream sessions' prompt caches invalidate on every edit", with a symptom of falling cache
  hit rate. Decision-framework test #3 carried the same leg, cited to the **API** prompt-caching
  page with the gloss "cache TTL hinges on stability".

  Both fail against the docs. The API page nowhere ties TTL to content stability — TTL is an
  explicit five-minute default with a one-hour opt-in — and it is the wrong surface besides: this
  skill scopes to a consuming repository's tracked markdown, which is consumed by Claude Code
  sessions. On that surface Claude Code's own prompt-caching page is the authority, and it says
  editing an always-loaded file mid-session "does not invalidate the cache, but the edit also
  doesn't apply", while sequential sessions "share the prefix only when the git status snapshot at
  startup matches" — so any commit already breaks cross-session prefix sharing and the SSOT's edit
  frequency is not the marginal driver.

  The real cost of a volatile always-loaded SSOT is propagation, and it is worth a gate. Pattern #9
  is now "Always-loaded SSOT propagation lag": a correction lands in the repo while every session
  already running keeps following the superseded version until its next `/clear`, `/compact`, or
  restart. Its symptom, mitigations, and the test #3 rationale are rewritten to that mechanism, a
  scope fence separates it from API-surface caching (where prefix volatility *does* cost an Agent
  SDK fleet sharing one prefix across machines), and a fourth mitigation tells the author to say so
  when a correction must reach live sessions. The slot number is unchanged, so the by-number
  citations to patterns #10-#13 across `actions/`, `lessons.md`, and SKILL.md are untouched;
  SKILL.md's taxonomy list carries the new name. Sources:
  <https://code.claude.com/docs/en/prompt-caching#editing-claude-md-mid-session>,
  <https://code.claude.com/docs/en/prompt-caching#cache-scope>, and
  <https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-storage-and-sharing>
  (verified 2026-08-04).

## [0.9.4]

### Fixed

- **`compress`'s scope-boundary list no longer calls `/code-review` and `/simplify`
  "built-in".** The "Not a `/code-review` / `/simplify` shadow" bullet read "The built-in
  `/code-review` and `/simplify` review code changes", mixing two categories the official
  docs keep apart: the commands reference states "Most are built-in commands whose behavior
  is coded into the CLI" and marks both `/code-review` and `/simplify` **[Skill]**, "a
  bundled skill", while the skills page adds that bundled skills are "prompt-based" and
  that `/doctor` was "a built-in command rather than a bundled skill" before v2.1.205 — the
  labels are mutually exclusive. Both surfaces are bundled skills; the bullet now says so
  (<https://code.claude.com/docs/en/skills#bundled-skills>). Scope is unchanged — the bullet
  still excludes code review from `/compress`'s markdown-prose remit.

## [0.9.3]

### Fixed

- **`audit-noise`: the `ghost-ref` shape no longer justifies itself with a premise that is false
  for a tracked memory tier.** The shape was named "ephemeral working-directory refs" and described
  its subject as paths into "the topic-docs convention's ephemeral tiers", resting the finding on
  the memory tier being gitignored. A consuming repo may deliberately track that tier — a real
  consumer does, by accepted ADR, with the citing files committed and reviewed — and such a reader
  could reasonably conclude the shape did not apply to them. It does: the durable reason is that
  the citing document outlives the slice, so slice retirement breaks the reference regardless of
  git posture. The row is renamed to "refs into slice-scoped working paths" and states that reason
  explicitly. Detection is unchanged — `noise-shapes.sh` never encoded the gitignore premise, so
  no path's verdict moves, and every existing exemption (slot variables, bare concern-scoped roots,
  the retired `.claude/notes/` location) is preserved.

## [0.9.2]

### Fixed

- **The shared concern-value parser no longer reads a declared key as absent over YAML key spacing.**
  `parse-concern-value.sh` anchored on the exact regex `^<key>:`, so `memory_dir : .work` (YAML
  permits whitespace before the `:`) and a root block mapping written at a uniform indent both
  resolved to the caller's fallback — substituting a value the repo never chose for one it did.
  Both shapes now resolve, matched at the document's own base indentation so a same-named key
  nested under another mapping never answers for the root one — including when the root key is
  present but deliberately empty. Synced from `lib/parse-concern-value.sh`; version bumped so installed
  copies receive it.

## [0.9.1]

### Fixed

- **Form 1's trailing boundary excludes a hyphen.** `\b` treats a hyphen as a word boundary, so
  `\B/<old>\b` matched `/context-guard` when renaming `context` — and Form 1 is Certain and sits
  on container mode's Certain allowlist, so an unrelated command went through the default
  auto-apply path and was rewritten. Slash-command and container names are kebab-case, so this
  fires constantly rather than rarely. Now uses the same consumed `([^\w-]|$)` terminator as
  Forms 13 and 15; a namespaced `/<old>:sub` still matches, a colon being a valid terminator.
- **`SKILL.md`'s slash-token gotcha states Form 1's corrected expression.** It still prescribed
  `\B/<old>\b` — the exact defect above — and `SKILL.md` is always loaded, so an agent following
  the gotcha would reintroduce it while `patterns.md` claimed it fixed.
- **Occurrence enumeration is bounded by a per-form REFERENCE REGION.** The survey emits a record
  for every `<old>` span inside a match; once the declaration alternatives accepted a trailing
  comment, a comment that mentions the thing it documents (`name: <old> # <old> before
  publishing`) produced a second record attributed to Form 14 — Certain, and exempt from the
  common-word demotion inside a manifest — so apply mode rewrote the prose. The region for those
  alternatives is the declaration VALUE; Form 7's stays the whole quoted field, whose occurrences
  are all genuine references.
- **Manifest declarations may carry an inline comment.** `name: <old> # package name` and
  `name = "<old>"  # package name` are ordinary self-documenting manifests, and the end-anchored
  declaration alternatives rejected the whole line — while filesystem evidence still selected
  container mode, so the registration went unmatched and was suppressed as residue while apply
  mode reported completion. The YAML form requires whitespace before `#`, since YAML starts a
  comment only after whitespace and `name: <old>#x` is a single scalar; TOML allows optional
  whitespace, its value being quoted. JSON is excluded, having no comment syntax.

## [0.9.0]

### Fixed

- **Precedence no longer launders a demotion into a Certain rating.** The dedup rule said a
  deduplicated line "enters the Certain bucket" unconditionally, which contradicted Form 14's
  scope rule demoting out-of-scope title matches to Ambiguous — and made eval 11's own
  expectation unachievable. A deduplicated line now enters **the owning form's bucket after its
  scope rules apply**. Precedence decides WHICH form owns a line, never how safely it is rated.
- **Apply mode terminates under container-rename mode.** `apply.md` Phase 6 completed only at
  `count == 0`, but the residue the mode rule deliberately leaves unrenamed still matches the
  token forever, so Outcome B looped indefinitely. Phase 6 now evaluates the ACTIONABLE count —
  the survey after precedence and mode — and reports residue in the hand-off summary.
- **`--include-bare-token` is registered where flags are parsed.** Phase 0b named it as the way
  to inspect suppressed residue, but it appeared in neither `SKILL.md`'s `argument-hint` nor
  `audit-modes.md`'s override table, whose contract errors on unknown flags — so the only
  documented path to the residue failed. Registered in both, audit-mode only, always Ambiguous.
- **Coverage keys on the CAPTURED token span, not the whole match span.** A match usually spans
  more than the token: Form 13's two alternatives span `/plugin install <old>@` and
  `<old>@acme-tools`, which overlap without either containing the other — so the whole-span
  coverage test kept both and scheduled two Edits on one token, the second failing because the
  first already rewrote it. Everything outside the captured `<old>` is context, not the thing
  being replaced.
- **Form 14 recognizes Setext titles.** A README may underline its title instead of using `#`.
  Both render as the primary heading, so missing the Setext shape left a container's own title
  with only a Form 2 hit — excluded by container mode — and the rename could report completion
  with the landing-page title stale.
- **Form 15's appositive accepts sentence-initial `The`.** Container prose routinely opens a
  sentence with "The `<old>` plugin ships…"; a lowercase-only `the` missed it, leaving the token
  with only a suppressed Form 2 hit. Only the article is case-flexible — the token stays
  case-sensitive, per `#1394`.
- **The survey emits one record per OCCURRENCE, not per line.** The span-dedup rule had no spans
  to compare: Grep's content mode returns matching lines and `--column` reports only the first
  match on a line, so a line-shaped record silently degraded the rule back to line-keyed dedup
  and restored the false completion it was written to prevent. Phase 2 now re-scans each returned
  line for every occurrence and emits `{file, line, start, end, pattern_form, snippet}`.
- **Form 13 matches the `marketplace` subcommand shape.** A marketplace's name sits after
  `/plugin marketplace add|update`, not directly after `/plugin` — so renaming a marketplace
  matched no position-anchored form, container mode suppressed its Form 2 hits as residue, and
  the sweep could report zero actionable stragglers while executable install instructions stayed
  stale.
- **The bare qualified-id alternative is Chain-context, not Certain.** Excluding dots is
  necessary but not sufficient — a dotless address is still an address, and this tree contains
  `auth_email: "a@b"` and `user.email t@t`, which containers named `a` or `t` would match and
  auto-rewrite. The management-verb alternative keeps Certain because its verb anchors it; the
  unanchored one is promoted only when a neighbor confirms it.
- **Form 14 recognizes JSON name declarations.** When the manifest or catalog is JSON the
  declaration is `"name": "<old>"` — quoted key, indented, trailing comma — which the
  column-zero YAML alternative reaches not at all. No other container-position form reached it
  either, so container mode reduced the container's own REGISTERED name to excluded residue and
  the sweep could report zero actionable stragglers with the registration stale. The Form 14
  scope rule is now explicitly scoped to the TITLE alternatives: a manifest or catalog `name`
  declaration is exempt from it and from the common-word demotion, because the key is the
  registration rather than evidence of one — without that exemption a repository-root catalog
  entry demotes to Ambiguous and the defect survives the fix.
- **Form 3 keeps terminal container directory paths actionable.** Every earlier path alternative
  requires something AFTER the token — an extension, a trailing slash, a known subdirectory — so
  a catalog's `"source": "./plugins/<old>"` and a README link `[…](plugins/<old>)` reached none
  of them, and apply mode could complete with the marketplace pointing at a vanished directory.
  The new alternative anchors on a bounded container-root segment and excludes an adjacent
  hyphen at both ends.
- **The survey enables multiline for Form 14's Setext alternative.** Phase 2 listed
  `multiline: true` for Form 7 only. The Setext pattern contains a literal `\n`, which ripgrep's
  single-line default REJECTS outright rather than under-matching, so the form was not
  executable through the documented pipeline at all.
- **Form 13's Chain-context demotion is stated consistently across files.** The precedence rule
  enumerated only Certain and Ambiguous, and `triage.md`'s Chain-context criteria never listed
  Form 13 — so the classifier apply mode follows flattened the demotion back to Certain and
  would still auto-rewrite a dotless address. Precedence now carries a per-alternative bucket
  table, container mode defers to it, and `triage.md` registers the alternative in Bucket 2 with
  its own promotion test and a Chain-context floor.
- **Form 14 matches TOML manifest declarations.** TOML delimits with `=`, so `name = "<old>"` in
  `pyproject.toml` or `Cargo.toml` reached neither the YAML nor the JSON alternative — while the
  mode ladder already names `pyproject.toml` as evidence for selecting CONTAINER mode. The skill
  therefore routed such a package into the mode that suppresses bare-token residue while being
  unable to match the one declaration that mode makes load-bearing.
- **Form 14 matches a catalog KEYED by the container, and YAML declarations at any indentation.**
  The mode ladder names both catalog shapes — a manifest's `name`/`id` field or a key in a
  registry catalog — but only the field shape had a pattern, and the YAML alternative was anchored
  at column zero so a nested manifest entry missed. Both selected container mode while their own
  registration stayed excluded residue. The key-position alternative requires the value to OPEN an
  object or array, and is Ambiguous outside a manifest or catalog unconditionally: `"<key>": {` is
  the commonest line shape in JSON (569 in this repository alone), so the file condition is what
  keeps it from becoming a mass-rewrite vector. A YAML block-mapping catalog key stays a
  documented gap: it opens with nothing, so the only pattern reaching it would match every nested
  YAML key.
- **The survey enumerates every token span INSIDE each match.** Form 7's pattern swallows a whole
  frontmatter field and its greedy prefix binds the capture to one occurrence, so
  `description: "first <old> and then <old>"` produced a single match for two references — and no
  cursor advance recovers the other, since re-matching from inside the field cannot reproduce the
  `description:` prefix. The whole-pattern match now establishes THAT a form applies and over what
  extent; the token spans within it are the references.
- **Form 14 accepts closed ATX headings.** `# <old> #` is valid ATX and its entire content is
  still the token, but the anchor rejected the trailing hash run, leaving the title as Form 2
  residue. The run is decoration, not reference: only the token span is replaced.
- **The default hand-off discloses confirmed skips.** Phase 7 required reporting them; the success
  template at the bottom of `apply.md` listed only the residue count, so a normal run said "0
  actionable stragglers" without disclosing that occurrences were preserved by request.
- **The rescan cursor advances to the end of the captured token, not the end of the match.**
  Forms 3, 13, 15 and both delimiter-anchored Form 14 alternatives CONSUME a trailing delimiter
  rather than asserting it, because ripgrep's default engine rejects look-around — and that
  delimiter is often the LEADING one the next occurrence needs. On
  `{"name":"<old>","id":"<old>"}` a global rescan therefore emitted only the first declaration
  and the second survived as suppressed residue. Fixed once in the survey rather than in each
  regex; dropping the terminator is not an option, since without it the qualified-id form matches
  inside an email domain again.
- **Skip spans are remapped as edits apply.** A span recorded before Phase 5 does not survive the
  edit: `<old>` and `<new>` differ in length, so rewriting an accepted occurrence shifts every
  later occurrence on that line and the stored skip no longer subtracts — the non-terminating
  loop again, defeated by the bookkeeping added to close it. Each Edit now shifts the later
  stored spans on its line by the delta, and a carried snippet catches any mismatch.
- **The JSON declaration is delimiter-anchored, not whole-line-anchored.** A minified or compact
  manifest — `{"name":"<old>","version":"1"}` — is perfectly valid and still selects container
  mode by filesystem evidence, but a `^…$` anchor required the field to occupy the whole line and
  left the registration unmatched. Now uses the same `(^|[{,])` / `(,|}|$)` delimiters as the
  key-position shape; precision on this repository is unchanged. The YAML and TOML alternatives
  keep their end-of-line anchor deliberately, being line-oriented grammars for the shapes
  manifests actually use.
- **The mode-ladder lead-in no longer says "stop at the first rule that fires".** The conflict
  rule added below the list said to collect rules 2–4 in full and compare; the sentence
  introducing the list still said the opposite, so the contradiction stood in one file.
- **A confirmed skip no longer blocks completion.** The actionable count excluded the container
  mode's residue but not the matches a user declined at Phase 4, so a deliberate "skip this"
  re-entered Outcome B on every re-sweep and the only exits were rewriting a known false positive
  or aborting — the same non-terminating loop the residue rule closes, reached through the other
  door. The allowlist change above made it routine rather than rare by demoting Forms 4–12 to
  per-match prompts. Skips are now recorded by occurrence span, subtracted from the count, scoped
  to the sweep that asked, and reported on their own hand-off line: residue was never proposed, a
  skip was proposed and declined.
- **The catalog key anchors on the JSON delimiter, not the line start.** `^\s*` reached only the
  pretty-printed shape where the key sits alone on a line — not the compact
  `plugins: { "<old>": { … } }` that the form's own motivating example uses. The anchor is now
  `(^|[{,])`: a JSON key follows a line start, an opening brace, or a comma, and nothing else.
- **Container mode's Certain rule is enforced as an allowlist over forms.** It was applied only to
  the bare-token residue, leaving Forms 8 and 12 — both Certain by default — on the auto-apply
  path: renaming a `context` plugin would rewrite the unrelated dotted key `context.timeout` and a
  `{a,context,b}` glob. Forms 1, 3 and 13–15 are the whole eligible set; every other form demotes
  to Ambiguous, reported per match rather than folded into the aggregate.
- **The survey rescans multiline matches as blocks.** Per-occurrence records were extracted by
  re-running each form's pattern against a single returned line, which reproduces nothing for
  Form 7 and Form 14's Setext alternative — so no record was emitted and the reference vanished
  between survey and triage, silently, on the two forms added because their references were being
  missed.
- **Form 14's declaration alternatives accept `id`, not only `name` and `title`.** The mode ladder
  already selects container mode on `<old>` appearing as the `name`/`id` field of a manifest, so a
  manifest identifying the container by `id` routed into the mode that suppresses bare-token
  residue while its `id` declaration stayed unmatched and excluded. The manifest/catalog condition
  on the declaration exemption is what keeps the widened key set safe — `id="$1"` is ordinary
  shell assignment syntax — so outside a manifest an `id` match takes the scope rule and the
  common-word demotion.
- **Qualified-id promotion binds to the occurrence, not the line.** "A management verb somewhere
  on the line" promoted an unrelated dotless address to Certain — `/plugin install foo@acme;
  email t@t` — undoing the demotion. A verb that governs the occurrence is already Certain under
  the management-verb alternative, so the line-level check added no recall and only laundered.
  The sole promotion signal is now structural and per-occurrence: the occurrence IS a key in an
  `enabledPlugins` / `pluginConfigs` map.
- **The mode ladder collects conflicting evidence instead of taking first-match.** Renaming the
  `/test` action while an unrelated manifest declares `name = "test"` fired the manifest rule for
  container and never inspected the `/test` invocations — container mode then suppressed exactly
  the actionable bare references and the rename falsely completed. Only the explicit override
  short-circuits; the filesystem, manifest and invocation rules are now collected in full and
  compared, and disagreement routes to the ask rather than to the earliest rule.
- **A raw `rg` fallback needs `--hidden`.** Container manifests live in dot-directories
  (`.claude-plugin/`), which bare `rg` skips — so the two alternatives above would return zero on
  exactly the files they exist to reach. The Grep tool and `git grep` need no flag; the
  cross-platform note now says so.
- **`--container` / `--identifier` are registered.** The Phase 0b ladder advertised them as the
  correction mechanism when evidence picks the wrong mode, but they appeared in no flag contract,
  and unknown flags are rejected — so the documented override could not be honored.
- **Forms 13 and 15 no longer match inside a hyphenated superstring.** Container IDs are
  kebab-case, but a word boundary counts a hyphen as a boundary — so renaming `guard` matched
  `context-guard@marketplace`, and renaming `context` matched `/plugin configure context-guard`.
  On Certain-rated forms that silently auto-rewrites a DIFFERENT plugin's identifier. Both ends
  of both forms now exclude an adjacent `-`. Verified against a marketplace where 32 plugin names
  are hyphenated.
- **Span coverage collapses COEQUAL matches, not only weaker ones.** Two alternatives of the same
  form can hit one occurrence — `/plugin install <old>@marketplace` matches both of Form 13's.
  Left uncollapsed the count doubles and Phase 5 schedules two targeted Edits, the second failing
  because the first already rewrote the token. Keep one per `<old>` span, widest first, earlier
  form on a tie.
- **Eval 9 no longer contradicts the span rule it predates.** It still required deduplication by
  `(file, line)` and dropping the bare-token duplicate for the whole line — so a correct
  span-based implementation would FAIL it while the line-based behavior that can falsely declare
  completion was rewarded. Rewritten around `(file, line, start, end)`.
- **Container-rename mode has a concrete selection ladder.** The mode was defined by what is
  being renamed, but nothing said how to determine that — Phase 1 resolves only the two strings,
  so an invocation like `/rename-references re-anchor to discipline` left the mode undetermined.
  Both defaults are costly: identifier mode on a container restores the Form 2 flood, container
  mode on an identifier suppresses genuinely actionable bare references. Resolution now runs an
  evidence ladder — explicit override, then a container-shaped directory with a manifest, then
  the manifest/catalog `name` field, then namespaced-invocation shape — and **asks** when none
  fires. Inferring from the token's shape is explicitly banned (hyphenation and word-likeness are
  uncorrelated with what the thing is), and the resolved mode plus the rule that fired are
  reported so a reader can see which applied. Resolved in Phase 1 by both audit and apply, before
  anything depends on it.
- **Every site stating a changed rule now agrees.** This skill states the same contract across
  `SKILL.md`, five `context/` files, and `evals/evals.json`, so a rule changed in one place left
  the others asserting its opposite. `SKILL.md` still gated the re-sweep on `count == 0` in two
  places (the always-loaded surface — that alone would have shipped the non-terminating loop the
  `apply.md` fix was meant to close), an eval still asserted the raw count and would have failed
  against the corrected skill, `triage.md`'s bucket criteria never learned that Forms 13–15 can
  be demoted, and `audit.md` defined Certain without the scope qualifier. All reconciled.
- **`patterns.md` "Phase 6" now requires that reconciliation.** After changing a rule, grep the
  whole skill directory for the claim just changed and fix every hit, evals included — an eval
  asserting superseded behavior is worse than a stale sentence, because it fails against the
  corrected skill and reads as a regression.
- **Deduplication keys on the occurrence SPAN, not the line.** A line can carry two independent
  references — `Use <old> via /plugin install <old>@marketplace`. Collapsing by `(file, line)`
  dropped the bare one, and because Phase 5 replaces a single span at a time, the survivor was
  then reclassified as residue, excluded by container mode, and the re-sweep declared completion
  with a live stale reference still in the file. A weaker match is now suppressed only when its
  span is COVERED BY a more-specific match's span.
- **Form 13's boundary uses no look-around.** The natural way to exclude a trailing dot is a
  negative lookahead, but ripgrep's default engine — the one this skill instructs — rejects
  look-around without `-P/--pcre2`, and `patterns.md`'s own cross-platform note already bans
  lookbehinds for the same class of reason. The form now CONSUMES a terminator,
  `([^\w.@-]|$)`, the same shape Forms 4 and 5 use.
- **`--include-bare-token` no longer over-promises on Orphans.** The override table said it
  applied to all sub-modes, but Orphans sweeps only Forms 1 and 3 and so has no bare-token
  residue to surface — the flag silently returned the default result there. Scoped explicitly,
  and reported as not-applicable rather than silently ignored.
- **Both Phase 7 hand-off templates carry the residue count.** The actionable-count rule
  promised users an aggregate, but neither success template had a field for it and the default
  hand-off still said `0 stragglers` — so the fix prevented the loop while hiding the number it
  committed to. Emitted only under container-rename mode and only when non-zero.
- **Form 13's qualified-id form no longer matches email addresses.** `<old>@[\w.-]+` has no
  management verb anchoring it, so for a container named `info`/`admin`/`support` it matched
  contact addresses on a Certain-rated form — a silent auto-rewrite. A marketplace slug is
  kebab-case with no dots while an email domain carries a TLD dot, so the form now accepts
  `[\w-]` with a `(?![\w.-])` lookahead. Verified: `info@acme-tools` matches;
  `info@acmetools.com` and `info@example.co.uk` do not.

### Added

- **`rename-references` gains three container-position pattern forms (13–15), closing the gap
  that let six stale references survive three sweep passes (`#1283`).** Forms 1–12 assume the
  renamed token is a skill/mode identifier. When a CONTAINER renames — a plugin, a marketplace
  entry — the token also appears in positions none of them reach: as the argument to a
  management command (`/plugin install <old>@marketplace`, `/plugin configure <old>`), as a
  document title that IS the token (`# <old>`), and in possessive or appositive prose
  (`<old>'s effective configuration`, `the <old> plugin`). Form 1 cannot fire on the first
  shape because the slash anchors `plugin`, not `<old>`.

  Each new form is high-precision because the SURROUNDING SYNTAX admits only the naming sense:
  a management verb before the token, a `$`-anchored heading, the possessive clitic. That is
  what lets them stay Certain where bare-token Form 2 cannot be. Measured on the real fixture
  (the `re-anchor` → `discipline` rename, over that plugin's own tree): Form 2 matched **134**
  lines for **8** real defects; Forms 13–15 matched **9** — the 8 defects plus one frozen
  CHANGELOG-history line the existing "Frozen historical records" rule already excludes.

  Command-argument hits are called out as FUNCTIONAL breaks, not cosmetic ones: a reader
  following `/plugin install <old>@marketplace` gets `plugin-not-found`.

- **Container-rename mode (`patterns.md` Phase 0b) — the rule that actually removes the prompt
  flood.** Precedence (below) resolves only lines the container forms ALSO matched: 8 of Form 2's
  134 on the measured fixture. The other 126 are ordinary verb uses no container form touches,
  and they fall through to Form 2's Certain default. The sweep now declares a MODE at Phase 0
  from what is being renamed. For a container — a plugin, a marketplace entry, a package — the
  renamed thing is a proper name, so a bare-token occurrence is evidence of nothing; the residue
  is excluded from Certain **regardless of blocklist membership** and reported as one aggregate
  count, surfaced only behind an explicit widen and then as Ambiguous. Mode is a property of what
  is being renamed, which is why it works where the static blocklist cannot: it does not depend
  on anyone having listed the token in advance. Fixture result with mode + precedence: 8 Certain
  findings, 126 reported-not-proposed, 0 confirmation prompts.

- **Form 14 is scoped to container-owned documents.** "A heading that IS the token can only be
  naming it" holds for a coined or hyphenated name and FAILS for an ordinary-word one — verified
  against this repository: renaming a `testing` plugin matches `README.md:86` (`### Testing`, a
  marketplace category heading) and renaming `architecture` matches `plugins/miro/README.md:39`
  (`## Architecture`, an unrelated design section). Under precedence a false Certain there is
  worse than a plain Form 2 hit, because it discards the safer classification. A title match is
  Certain only in plausibly container-owned files, and always Ambiguous when the token is a
  common English word.

- **Container-position precedence, without which the new forms only ADD hits.** Forms 13–15 are
  strictly more specific than Form 2 — every line they match, Form 2 matches too. The sweep now
  deduplicates by `(file, line)` after collecting and before triage: a container-position match
  takes the Certain path and its bare-token duplicate for that line is dropped as the same
  reference seen through a weaker lens, not a second finding. Only lines the container forms did
  NOT match fall through to Form 2's blocklist rule. The audit report carries the superseded
  count so the suppression is visible rather than inferred. This is what makes position an actual
  remedy for the verb collision instead of an additional lens over an unchanged prompt flood.

### Changed

- **`triage.md` records the collision class the English-verb blocklist cannot serve.** The
  blocklist holds tokens that are English verbs in general; it cannot cover a token that is a
  verb *in the consuming codebase*. Both branches fail there — omitted, every bare-token hit is
  rated Certain and the sweep proposes rewriting the verb uses; added, every hit lands ambiguous
  and the per-match confirmation rule turns a handful of defects into hundreds of prompts.
  Extending the blocklist swaps one unusable bucket for another; the remedy is position. The
  section routes to Forms 13–15 and carries the measured figures.
- **`patterns.md` Phase 6 now requires validating a new form on BOTH axes.** Recall alone is not
  evidence — Form 2 already has perfect recall on every form in the library and is still
  unusable when the token is a verb. A candidate is measured against the commit that FIXED the
  missed references (its removed lines are the defect set) for recall, and against the whole
  pre-fix tree for precision, reporting its hit count beside Form 2's on that same tree.
- **`audit.md`'s pattern-form breakdown** lists Forms 13–15 and the superseded-hit count, and its
  Survey phase applies the precedence dedup before triage runs.
- **Form 14 accepts single-quoted YAML** (`name: '<old>'`) alongside bare and double-quoted
  values, with the quotes required to PAIR — a naive `["']?` would match the invalid `"<old>'`.
- **Form 15 allows the token to be inline code** before the possessive clitic, which in markdown
  is the common case rather than the exception: the literal `<old>'s` sequence never appears when
  the token is a code span, so without this the form missed its own motivating example.

## [0.8.7]

### Fixed

- `audit-derivability` fork-mechanism disambiguation now reads in one voice: the Hard Rules bullet
  adopts the "is the opposite" phrasing already used by the spot-test bullet, `context/rubric.md`,
  and `evals/evals.json`, replacing its divergent "is unrelated". The Gotchas self-grade bullet,
  previously the one bare "non-fork subagent" site, now names the Agent tool's `fork` subagent type
  as the forbidden mechanism — matching what `evals/evals.json` already grades on — without
  repeating the full `context: fork` explanation.

## [0.8.6]

### Fixed

- `audit-derivability` Hard Rules "never by a fork" now names the Agent tool's `fork` subagent
  type inline and distinguishes it from a skill's own `context: fork` frontmatter (which starts
  blank), matching the disambiguation already in the spot-test bullet — the Hard Rules section is
  now self-contained for a reader landing there first.

## [0.8.5]

### Fixed

- `audit-derivability` spot-test wording no longer inverts the fork mechanism: the contamination
  risk is attributed to the Agent tool's `fork` subagent type (which inherits the invoking
  conversation), not to a skill's own `context: fork` frontmatter (which starts blank with no
  conversation access). Corrected across SKILL.md, `context/rubric.md`, and `evals/evals.json`;
  the fresh-context non-fork recommendation is unchanged.

## [0.8.4]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.8.3]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.2] — 2026-07-21

### Fixed

- **`audit-noise`'s convention-roots scan no longer truncates a quoted
  `memory_dir`/`contract_dir` at an interior `#`, collapses interior
  whitespace, or leaves quotes unstripped.** The hand-rolled
  `${val%%#*}` + `${val//[[:space:]]/}` + ad hoc quote-peel in
  `scripts/lib/noise-shapes.sh`'s `audit_noise_convention_roots_pattern` is
  gone; resolution now routes through the shared `parse-concern-value.sh`
  helper (materialized from `lib/parse-concern-value.sh`), which resolves
  surrounding quotes and a comment-aware strip in the correct order and
  never mangles interior whitespace. Held behavior: trailing-slash
  normalization, and the `.`/`.work`/`docs/topics` default-root exclusions.

## [0.8.1] — 2026-07-21

### Added

- **`audit-noise` gates its five in-page NOISE shapes behind a whole-page
  existence pre-check** (#505). Before line-level classification, the skill
  now asks whether a reader with repository search could derive the page's
  content from the code itself; a FAIL is a deletion candidate (recommend
  relocate-then-delete, never auto-delete) and skips the in-page tier table.
  Decisions, domain language, thin navigation, and policy/wiring pages always
  pass admission. Reuses `/docs-hygiene:audit-derivability`'s rubric by
  reference for contested calls (optional namespaced skill invocation,
  degrading to the admission question standalone when unavailable). Ships as
  a portable-baseline default; a consuming repo's own declared
  documentation-existence convention overrides it via
  `/re-anchor:follow-our-standards`'s resolution ladder. Read-only, matching
  the skill's existing contract.

## [0.8.0] — 2026-07-20

### Added

- `/docs-hygiene:audit-derivability` — a read-only, document-level worth
  classifier. It asks whether a whole documentation file earns its existence:
  could a fresh agent re-derive the document's conclusions by natively exploring
  the code, config, metadata, and structure? Verdicts weigh four factors
  together (derivability, re-derivation cost, drift risk, fact ownership) and
  never derivability alone — `delete`, `convert-to-pointer`,
  `keep-as-derivation-cache` (which demotes when it carries no drift-control
  condition), or `keep-owns-facts` (rationale, decisions, constraints, and
  external facts are non-derivable). Audience-aware (agent-facing surfaces get
  the full axe; human-facing docs clear a higher bar), and load-bearing or
  contested deletions are confirmed by a fresh-context, non-fork spot-test that
  has not seen the document. Distinct axis from the siblings, which trim
  *inside* a document worth keeping.

## [0.7.1] — 2026-07-20

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.0] — 2026-07-18

Changed:

- `/docs-hygiene:compress`: `markdownlint-cli2` absence is now classified
  required-for-correctness — the skill stops at the entry point with an install
  remediation instead of treating a missing ship gate like a lint failure
  (prerequisite-visibility wave).
- README gains a Requirements section declaring the runtime (Bash/git/jq
  ambient, Git Bash on native Windows), the compress-only `markdownlint-cli2`
  requirement with its absence behavior, and the optional `caveman` backend.

## [0.6.0] — 2026-07-17

Changed:

- Renamed the `declutter` skill → `audit-noise` (breaking). Update any
  `/docs-hygiene:declutter` invocations to `/docs-hygiene:audit-noise`; the
  plugin ID (`docs-hygiene`) is unchanged, only the skill's leaf name moved.
  The skill is a read-only classifier — per the marketplace naming grammar
  `audit` = read-only report — and "declutter" remains a description trigger
  word. The detect-script env vars moved with it:
  `DECLUTTER_REPO_ROOT` → `AUDIT_NOISE_REPO_ROOT`.

## [0.5.0] — 2026-07-15

Changed:

- Renamed the `encapsulation-audit` skill → `audit-encapsulation`. Update any
  `/docs-hygiene:encapsulation-audit` invocations to `/docs-hygiene:audit-encapsulation`; the plugin ID
  (`docs-hygiene`) is unchanged, only the skill's leaf name moved.

## [0.4.0] — 2026-07-15

Added:

- Self-contained, bundled eval fixtures: compress's `audit-classification-table`
  case (`evals/fixtures/audit-fixture-dir/`) and declutter's
  `opt-out-and-section-exemptions-respected` case
  (`evals/fixtures/legit-optouts.md`) — both previously unfalsifiable prose
  prompts referencing nonexistent files.
- The "add an eval case" clause, re-added to the two Gotchas/Recheck-trigger
  bullets in rename-references/SKILL.md.

## [0.3.0] — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0) in the declutter
ghost-ref detector:

- Concrete `docs/topics/<slug>/` contract-slice paths are ghost-ref
  candidates alongside `.work/<slug>/` memory slices — contract slices
  are pruned before merge, so a durable doc citing one breaks.
- Any `.claude/notes/` citation is a ghost-ref candidate, placeholder
  form included — the location is retired under the convention.
- The exemption widens from the bare `.work/<slug>` / `.work/<sub-slug>`
  / `.work/<TS>` tokens to the convention's citable surfaces:
  angle-bracket slot variables under `.work/` and `docs/topics/`, the
  reserved concern-scoped roots `.work/handoffs/` and `.work/reviews/`,
  and the tracked concern file `.claude/topic-docs.yaml`.
- Exemptions apply per matched path, not per line: the detector scans
  each candidate path individually, so a convention token (placeholder,
  bare concern root, concern file) no longer masks a concrete ghost ref
  sharing its line.
- The concern-root exemption narrows to the bare roots: `.work/handoffs/`
  and `.work/reviews/` are exempt only with nothing concrete after them
  (or an angle-bracket placeholder child) — a concrete child such as
  `.work/reviews/pr-123-auth/20260101T000000Z-self.md` flags.
- Candidate slugs accept a digit-leading first character, matching the
  convention's `[a-z0-9-]` slug spec and its recommended date-suffixed
  slugs (`docs/topics/2026-migration/PLAN.md` flags).
- The `.claude/topic-docs.yaml` exemption clause is removed: the concern
  file matches no ghost-ref pattern, so under the per-path model it
  passes naturally instead of exempting whole lines.
- The ghost-ref block short-circuits: a literal prefilter on `.work/`,
  `docs/topics/`, and `.claude/notes/` gates the scan, which stops at
  the first flagged path.
