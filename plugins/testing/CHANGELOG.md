# Changelog

All notable changes to the `testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.8]

### Changed

- **The `run-e2e` playwright pointer front-loads its subject.** Its bolded lead was the routing verb
  rather than the payload, and the sentence carried an em dash the house style does not allow on an
  instruction surface. Docs-hygiene sweep, L7-write-for-agents.

## [0.7.7]

### Changed

- **audit:** behavior-preserving simplification from the repo-wide
  batch-simplify sweep. cant-fail-scan.awk's `taut_scan` drops a dead
  `p > 0` guard that sat immediately after a successful `match()` call
  (a successful match guarantees `RSTART >= 1`), de-indenting the
  enclosed block; the later `index()`-based guard, which is genuinely
  fallible, stays. Verified by a fresh-context refutation pass:
  byte-identical output across the 92-check suite, crafted
  failed-inner-match inputs, and a 14,000-line fuzz differential.

## [0.7.6]

### Changed

- **Instruction-surface de-slop (#2891, testing cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.7.5]

### Fixed

- **A branch name beginning with a YAML indicator silently dropped every finding `audit`
  emitted.** `cant-fail-scan.sh --findings` interpolated the checked-out branch into its findings
  frontmatter as a bare plain scalar, and `git check-ref-format --branch` accepts `@foo`, `!foo`,
  `#foo` and `&foo`. Emitted bare, `#foo` and `&foo` parse to null and `@foo`/`!foo` are outright
  YAML parse errors, so the `branch:` value a consumer reads is not the branch name. The consumer
  admits a findings file only when that value matches the current branch exactly, so the whole
  file went unmatched — with no error, and nothing distinguishing it from "no findings". That is
  the hidden-findings failure mode this scanner exists to prevent, reached through the frontmatter
  rather than through the scan. Frontmatter now goes through a `yaml_scalar()` helper that quotes
  only when the plain form would misparse, so an ordinary branch name stays a byte-identical
  unquoted scalar and the wire format for the common path does not move. The predicate is
  deliberately identical to the one `claude-config`'s and `ai-slop`'s emitters use: three
  producers answer one frontmatter contract, and a consumer must not see three shapes.
  Implicit YAML types (`true`, `null`, `123`, `yes`, dates) are quoted the same way, because a
  bare scalar would type-coerce and the consumer's exact branch match would still drop the file.

## [0.7.4]

### Fixed

- **`audit`'s own unit suite carried a can't-fail assertion for the `date:` frontmatter
  field.** `cant-fail-scan.test.sh` asserted `date: 20` under the name "date frontmatter is
  present" — a truncated prefix of a structured value, so it passed for the emitter's real
  `2026-08-23T04:37:40Z` and equally for `2026-08-21T13-36-00Z`, a hyphenated time that is
  ISO-8601 in neither the extended nor the basic profile. That is the same assertion shape
  that pinned `ai-slop`'s emitter bug rather than catching it (#3097), sitting inside the
  skill whose whole purpose is finding tests that cannot fail. The assertion now anchors the
  full extended form with an explicit `Z`
  (`^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`), and was confirmed
  discriminating: it FAILS against both malformed shapes above and PASSES against
  `cant-fail-scan.sh --findings` output. Test-only — the emitter already stamped the correct
  format, so no scanner behavior changes.

### Added

- **`assert_matches <name> <haystack> <ERE>` in `cant-fail-scan.test.sh`.** An assertion about
  the *shape* of a field's value now has somewhere to go other than a substring test on part
  of that value, which is what produced the guard above. The file's sibling assertions were
  re-read at the same time: every other one pins an exact literal that a malformed value would
  not contain, so that was the only non-discriminating guard present and nothing else was
  rewritten.

## [0.7.3]

### Changed

- **Fixture-building tests clear inherited git environment (#2872).** Suites
  that build a git fixture now unset `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_CONFIG` so an inherited environment cannot write the fixture identity
  into the caller's repository. Test-only; no plugin behavior change.

## [0.7.2]

### Fixed

- **"Prefer no new test to a bad one" now carries its attribution.** The phrase and the six
  impracticality triggers 0.7.0 added are the upstream cursor/plugins `tdd` cost branch — the
  pinned file at `cursor/plugins@60c641e4` `pstack/skills/tdd/SKILL.md` states "Prefer no new test
  over a bad test" and lists the same six triggers. They are not in `/tdd:principles`: a search of
  that skill and its routed Khorikov files finds neither the phrase nor the triggers. The nearest
  sentence is Khorikov's "It's better to not write a test at all than to write a bad test" in
  `testable-architecture-khorikov.md`, the 2x2 / Humble Object chapter, which this port used as
  grounds to *reject* upstream's five-item bad-test definition as already owned
  (`docs/upstream/cursor-pstack.md`). Cited inline as `(upstream cursor/plugins tdd)`.

## [0.7.1]

### Changed

- **Cross-skill chains name the Skill tool (#3002).** `diagnose`'s build-first fix row in
  `context/investigate.md`, its genuine-bug fix route, and `context/loop.md`'s replan route;
  `run-e2e`'s three next-step arrows and the matching pair in `context/e2e.md`, plus its
  Playwright-CLI usage pointer; `write`'s run-the-tests / continue-implementation step and its two
  next-step arrows. Wording only — presence gates, fallbacks, and step order unchanged.

## [0.7.0]

### Added

- **`write`: a test worth having is not always worth *this* test.** Absorbed from an upstream
  cursor/plugins skill (`docs/upstream/cursor-pstack.md`, the `tdd` section) into the existing
  "When NOT to write tests" section.

  That list already covered code that needs no test — pure contracts, constants, one-liner
  delegation, config wiring. It said nothing about the other axis: code that genuinely needs
  covering, where the only available test would need broad harness setup, brittle mocks, slow
  end-to-end infrastructure, production-only state, a reproduction nobody can state precisely, or
  large unrelated fixture churn. Prefer no new test to a bad one there — a test that mostly
  exercises its own mocks, encodes today's implementation, or would be deleted the moment it has
  proved its point costs more to maintain than the confidence it buys.

  **Declining is not skipping.** The addition requires naming which trigger made the test
  impractical and then naming the closest executable check used instead — a targeted script, a
  reproduction command, a snapshot comparison, a log assertion, a focused integration check. That
  matches doctrine this repo already enforces mechanically in CI, where a silent skip is a defect.

  Landed here rather than in `debugging:debug`, which the plan originally proposed: an adversarial
  audit pointed out that this decline list is the incumbent for the concern and a second one in
  `debug` would split it. The two lists are different axes, verified by reading both, so this is an
  addition rather than a restatement.

## [0.6.2]

### Fixed

- **The README claimed four skills and documented four, in a plugin that has five.** `/testing:audit`
  landed in 0.6.0 and reached the plugin manifest's description but never the README — so the front
  page both miscounted the set and omitted a whole skill from its table, and a reader arriving there
  had no way to learn `audit` exists. Both halves are corrected: the count reads five, and `audit`
  has its table row. Found by `scripts/check-skill-count-claims.sh`, a new fleet gate that compares
  every hand-written skill count against the tree; this was one of four live drifts it surfaced on
  its first run.

## [0.6.1]

### Changed

- **Three verifier-earned known limits recorded in `/testing:audit`'s gotchas**, so the next reader
  meets them as documented boundaries rather than rediscovering them as bugs: the C# generic
  `Assert.Equal<T>(a, a)` recall gap in `recomputed-expectation` v1; the JS regex-literal masker's
  deliberately narrow trigger set (never after an identifier, so a regex directly after `return` is
  unmasked — chosen because misreading division as a regex would mask real code — with the known
  cost that an unmasked regex containing a brace can close the test block early and false-positive
  `rule-zero-assertion`); and the platform-skip blindness boundary — a platform-skipped assertion is
  unverified on the platform that skips it, the same defect family this detector hunts approached
  from the environment side and out of static reach, making the dropped skip rule's uncovered axis
  platform as well as ecosystem.

## [0.6.0]

### Added

- **New `/testing:audit` skill — the can't-fail test audit (#2684).** A deterministic script
  detector (`cant-fail-scan.sh` driving `cant-fail-scan.awk`) for tests that cannot fail, with
  three rules v1, each carrying a qualified rule id and a fixed threshold:
  `testing/audit/rule-zero-assertion` (a runnable test body with 0 assertion tokens),
  `testing/audit/rule-recomputed-expectation` (an equality assertion whose actual and expected
  sides are the identical expression — the decidable core of the recomputed-expected-value class),
  and `testing/audit/rule-mock-only-oracle` (every assertion in a mock-constructing test is a
  mock-interaction assertion; advisory by default because deliberate interaction-style tests are
  the known benign case, gating only under `--strict`). Ecosystems v1: JS/TS, Python, C#; bash
  `*.test.sh` is deliberately excluded — the marketplace repo's discriminating-skip gate is the
  incumbent for the skip-vacating shape there. Detection bias errs toward not firing (generous
  assertion tokens, string/comment masking, skipped tests unjudged), guarded by a negative fixture
  that must produce zero findings. `--check` is the fail-closed gate mode: exit 1 on a gating
  finding, exit 2 when inputs could not be fully read or when 0 test files were examined (an
  unread input is never a clean one, and a wrong or empty scan root must not share exit 0 with a
  healthy suite), exit 0 only for a fully read clean scan of at least one test file — the
  liveness-assertion contract's fail-loud limb.
  `--persist-findings` (explicit override; bare invocation stays read-only per the `audit` verb
  contract) writes a detector-findings-conforming file — `Tier` looked up flat per rule
  (IMPORTANT), `Confidence` high or omitted (never low), root-relative `Location`, cell escaping,
  `## Surfaces` coverage — that the `review:fanout` `fix` action consumes. Every run reports a
  coverage denominator, so zero findings over zero examined files is named a scan of nothing
  rather than a clean bill. Deliberate cases are recorded in-file with `cant-fail-ok: <reason>`,
  counted and never silent.

## [0.5.2]

### Changed

- **Every `testing` skill's `description` now uses `Use when:` rather than `use for`.** `diagnose`,
  `plan`, `run-e2e` and `write` each carried their routing phrases behind a lowercase `use for`,
  which the skill-quality gate does not recognize as trigger phrasing. Each list gains 2–3 typed
  phrases (`'this test is failing'`, `'where are the coverage gaps'`,
  `'does the app actually work'`, `'add test coverage'`, among others); every phrase already present
  is preserved verbatim. `plan`'s `'test plan' / 'what needs testing'` slash-pair becomes a plain
  comma list, which the gate's extractor already read as two separate phrases.

## [0.5.1]

### Changed

- **The bundled `/verify` invocability note now says "by default", not "only".** A recheck on
  2026-08-10 against the bundled-skills reference and the shipped 2.1.223–2.1.226 clients found the
  0.3.x-era wording had drifted: "user-invoked only from v2.1.215" was exact for 2.1.215–2.1.224,
  where the bundled skill carried a hard model-invocation block, but from **2.1.225** that block
  became a runtime gate that can re-enable model invocation. The restriction is therefore the
  *default* rather than an absolute, and two clients on one version can differ — which an unscoped
  "only" cannot express. **The instruction this note supports is unchanged and was strengthened, not
  weakened:** suggest `/verify`, never delegate to it. A delegated call is refused at the tool layer,
  so the suggest-don't-delegate rule now holds across either invocability state rather than resting
  on a version cutoff.
- **The note becomes a conforming upstream-drift record.** Touching a restatement of an
  upstream-owned specific binds the required parts on touch (`docs/conventions/upstream-drift/README.md`
  §Adopters), so the claim now carries a verification date, the client versions checked, and an
  observable recheck trigger — a Claude Code release whose changelog names `/verify` or bundled-skill
  invocability — rather than a bare link.

## [0.5.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.4.0]

### Added

- **`diagnose`: redaction guard + tagged debug logs.** A new `## Redact` section in the router
  requires every secret redacted (`<REDACTED>`) before commands, test output, stack traces, or
  CI logs are shown; reproductions read credentials from env vars so secrets never land in a
  command line, fixture, or committed regression test. Investigation step 4 now tags every
  debug log with a unique short prefix (e.g. `[DEBUG-a4f2]`), and the fix loop's green gate
  removes tagged instrumentation via a single grep before the atomic commit — the loop commits
  per iteration, which is exactly where untagged logs leak into history. (Guard and tag
  convention from upstream mattpocock/skills `diagnosing-bugs` v1.2.3; registry: the
  marketplace repository's `docs/upstream/mattpocock-skills.md`.)

## [0.3.4]

### Added

- **`/testing:diagnose`'s fix step now constrains the direction of the fix, not just its size.** The
  loop's Step 3 bullets bounded scope but never said which side of the red signal to change, leaving
  "edit the assertion until it passes" as the shortest path to green. The step now leads with fixing
  the production code, and requires a deliberate, stated correction when the test itself is the thing
  that is wrong.
- **The e2e prerequisite hard-fail says why workarounds are barred** — a substitute path yields
  unverified pass/fail results, which defeats the point of live verification. Added at both the
  `SKILL.md` and `context/e2e.md` statements of the rule.

### Changed

- **The prerequisite headings drop their `MANDATORY` tag** in `/testing:run-e2e`; the STOP-and-report
  behavior described immediately beneath each already makes the requirement unambiguous.

## [0.3.3]

### Changed

- **`/testing:run-e2e`'s handoff no longer delegates surface verification to the bundled `/verify`.**
  Claude Code v2.1.215 made `/verify` user-invoked only, so **from v2.1.215** "delegate surface
  verification to it first" named a surface the skill cannot invoke. The handoff now suggests the
  user run it and consume its findings, and carries the v2.1.215 scope rather than stating the
  restriction flatly — on 2.1.145–2.1.214 `/verify` is still model-invocable. The instruction itself
  is uniform across the window, because suggesting is correct on every version `/verify` exists on.
  The orchestrator path was already the fallback and is unchanged. The `≥ 2.1.145` availability floor
  is a separate axis, unchanged and re-verified 2026-08-02.

## [0.3.2]

### Changed

- **Doc reference updated for the `config-cascade` seam rename (#1188).** The layering-contract links in
  `README.md`, `run-e2e/SKILL.md`, and `run-e2e/context/e2e-config.md` now point at
  `docs/conventions/config-cascade/` (formerly `consumer-config-layering`). No behavior change.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- `/testing:run-e2e` gains a consumer-project config surface, `.claude/testing/e2e.md`,
  with two per-key-override keys: `recording` (`video | gif | off`, default `off`) and
  `browser_mode` (`headed | headless`, default `headless`). Defaults preserve current
  behavior. Keys, defaults, and precedence live in the skill's bundled
  `run-e2e/context/e2e-config.md`; layers resolve per the marketplace
  consumer-config-layering convention.
- Optional recording evidence tier in the E2E evidence contract — video via the
  playwright CLI for long flows, GIF via `gif_creator` for short demos — plus a
  session-artifacts record (recording path, session ID, transcript pointer). Screenshots
  remain the evidence floor.

### Changed

- `/testing:run-e2e` now resolves the config surface before driving — anchors at the
  repo root, merges all three layers per key, and reports which layer supplied each
  effective value — then passes the resolved `browser_mode` and `recording` values
  through to the executor.
- The drive loop is delegated to a subagent; the orchestrator consumes evidence paths
  only.
- The prerequisite hard-fail keeps its STOP and now also writes a structured
  verification-environment gap report (what is missing, what the operator must provide)
  to the run's evidence output.
- Verification delegates to the bundled `/verify` command first when it is present
  (Claude Code ≥2.1.145); the orchestrator fallback is unchanged when it is absent.
- Eval #1 updated to assert the prerequisite hard-fail STOP plus the structured gap
  report.

## [0.2.5]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.4]

### Changed

- Reworded two `files: []` (context-free) eval expectations to credit a consumer-agnostic inspect/ask
  path equally with a doc-permitted default, rather than pre-committing to one answer. The `diagnose`
  fixture-collision case (case 1) now grades recognition of the process-global singleton / shared-state
  root cause plus inspecting the project's fixture layout or asking for its documented convention, with
  the specific mechanism demoted to a non-exhaustive example instead of the asserted answer. The `write`
  shared-library placement case (case 2) now grades the single-project-vs-cross-project judgment and
  deferral to the project's documented convention, keeping the create-a-test-project decision while
  dropping the co-location pre-commitment (`context/organize.md` permits co-location for single-project
  integration tests and centralization for cross-project ones). Eval expectations only; no skill
  behavior, routing, or context files changed.

## [0.2.3]

### Changed

- Neutralized repo-coupled `expected_output` in `diagnose` and `write` evals so they grade the
  underlying decision, not one private monorepo's layout. The `diagnose` fixture-collision case now
  grades recognition of a process-global singleton / shared-state collision and deferral to the
  project's documented fixture convention (dropping the `MonolithApi.Tests` /
  `MonolithApiTestFixture.CollectionName` names). The `write` cases now grade co-located placement and
  naming per the consuming project's documented conventions, and the testable-vs-contracts decision,
  without naming any project, path, or framework (dropping `Platform.Messaging`, `libs/dotnet/`, and the
  ghost `testing.md` reference to xUnit v3 / Shouldly — this plugin ships `write.md`/`organize.md` and
  defers framework/assertion choices to the consuming project). Eval prompts/expectations only; no skill
  behavior, routing, or context files changed.

## [0.2.2]

### Changed

- Fallback naming defaults, the sole worked code sample, and the sole regression command are reframed
  as ecosystem-relative rather than .NET-only. The PascalCase `{Method}_Should{Behavior}_When{Condition}`
  naming forms (in `write`, `write/context/write.md`, `write/context/organize.md`, `plan`) are demoted
  from "the universal default" to one labeled illustrative (.NET/xUnit) example, routed first through the
  convention-resolution ladder (use the project's documented pattern; when undocumented, mirror the
  consuming ecosystem's own idiom). The lone worked `[Fact]` code sample in `write/context/write.md` and
  the lone `dotnet test` regression block in `diagnose/context/loop.md` now carry an "illustrative (.NET)"
  label, with the regression block routed through `/toolchain:check` as SSOT for the exact per-ecosystem
  command (falling back to the project's own test command when the `toolchain` plugin is absent, matching
  `write`'s handoff). Framing and labeling only — TDD cadence, Four Pillars, verify-through-the-interface, the
  reproduce→fix→retest→regression loop, and all routing/handoff are unchanged; no code, template, or
  command string was altered.

## [0.2.1]

### Changed

- Cross-plugin marketplace-skill references brought under the presence-gated guard and reframed as
  stack-specific. The unguarded inline `dotnet-test:*` parenthetical in `write` (per-cycle checklist)
  is removed; its detection-layer skills moved under `write`'s now-guarded
  `## Marketplace plugin skills (invoke only when installed)` list. The all-.NET enrichment lists in
  `write`, `organize`, `plan`, `run-e2e`, and `diagnose` now state the `dotnet-*` skills apply only
  when your stack is .NET, so a non-.NET consumer is not handed a dead list as the universal path.
  No hard dependencies; every reference stays optional and installed-gated.

## [0.2.0]

### Changed

- **BREAKING: `/testing:e2e` renamed to `/testing:run-e2e`** (fleet conformance wave —
  naming grammar, verb-first skill names). Update any saved invocations. Skill behavior,
  triggers, and evals are unchanged; only the leaf name and namespace token changed.

## [0.1.2]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.1.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.1.0]

### Added

- Initial release — four skills extracted and renamed from the `implementation` plugin's `test-*`
  skills: `/testing:plan` (was `test-plan` — coverage-gap analysis), `/testing:write` (was `test-write` —
  TDD authoring and placement), `/testing:e2e` (was `test-e2e` — live app + non-UI smoke verification),
  and `/testing:diagnose` (was `test-diagnose` — failing-test root-cause diagnosis and the fix loop).
  Skill trigger phrases and evals are preserved; only the namespace and leaf names changed.
- Cross-plugin references degrade gracefully: test invocation defers to `/toolchain:build` when the
  `toolchain` plugin is installed (else the project's own test command), and handoffs to
  `/implementation:implement`, `/verification:confirm`, `/tdd:principles`, and `/playwright:playwright`
  fire only when those plugins are installed — no hard dependencies.
