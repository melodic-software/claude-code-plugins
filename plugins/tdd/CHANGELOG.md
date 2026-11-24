# Changelog

All notable changes to the `tdd` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.8] - 2026-11-24

### Changed

- `/tdd:principles` gains a `## Related` section pointing at `/testing:test-value` and
  `/mutation-testing:principles`.

## [0.6.7] - 2026-11-21

### Changed

- **`/tdd:principles` anti-patterns and testable-architecture pages carry no C# listings.** `anti-patterns-khorikov.md` loses its eleven C#, Moq (`CallBase`) and `DateTime.Now` listings, and `testable-architecture-khorikov.md` loses its six C#, xUnit.net and Fluent Assertions listings (the CRM refactoring, the domain-layer test, CanExecute/Execute and domain events). Where a listing carried the only statement of a point (the code-pollution flag and its interface fix, partial mocking of a concrete class, time as ambient context, the two ways to inject time, when domain events are recorded and sent), the point is now stated in prose. The rules both pages teach are unchanged ([#17767](https://github.com/melodic-software/claude-code-plugins/issues/17767)).

## [0.6.6] - 2026-11-21

### Removed

- **`/tdd:principles` property-based and characterization testing pages no longer state tool behavior.** `property-based-testing.md` drops its Shrinking section, the `@example(...).xfail()` note and the Sources entries for Hypothesis, fast-check, rapid, CsCheck, FsCheck, QuickCheck, the `/hypothesis` command and Kiro. Its intent-first claim now rests on Vikram et al. alone, and its fallback rule of thumb no longer says to pin the shrunk input as an explicit example. `characterization-testing.md` drops its Golden Master, Approval and Snapshot Tests section and the Sources entries for ApprovalTests, Verify, Jest and Scientist. The paper and author citations stay, and the routing table no longer lists shrinking or golden-master, approval and snapshot tests ([#17771](https://github.com/melodic-software/claude-code-plugins/issues/17771)).

## [0.6.5] - 2026-11-21

### Changed

- `principles` no longer shows its test-double and London-versus-classical patterns as Java, Python, TypeScript or C#/Moq code. The Mock Object, Self Shunt, Log String, Crash Test Dummy and one-function-per-remote-operation examples in `reference/test-doubles.md`, and the two Store/Customer listings in `reference/classical-vs-london-khorikov.md`, are cut. The Moq `Times.Once` and `VerifyNoOtherCalls()` calls in the fifth mocking practice and the inline `storeMock.Verify(...)` in the over-specification argument are cut too. The prose explaining each pattern stays. Sentences that only described a removed listing, or how Java does it, are cut.

## [0.6.4] - 2026-11-21

### Changed

- **`/tdd:principles` routing table, sources and test-design page carry no ecosystem-specific examples.** The routing table drops the `DateTime.Now` keyword, and the web-sourced reference list no longer names property, approval and snapshot tools' docs. `test-design.md` loses its Java and C# listings, its xUnit.net parameterized-test API guidance (`[Theory]`, `[InlineData]`, `[MemberData]`, `[Fact]`) and the Fluent Assertions library recommendation; its Fluent Assertions section is renamed "Readable Assertions" and keeps only the subject-action-object principle. Where a listing was the only place a rule appeared (evident expected values, failing an exception test that returns normally, Khorikov's naming refinements), the rule is now stated in prose. The rules the page teaches are unchanged ([#17763](https://github.com/melodic-software/claude-code-plugins/issues/17763)).

## [0.6.3] - 2026-11-21

### Changed

- **`/tdd:principles` coverage, integration-testing and four-pillars pages carry no ecosystem-specific examples.** `code-coverage-khorikov.md` and `integration-testing-khorikov.md` no longer show C# listings (coverage examples, interfaces, logging, mocking, spies, object mother); where the surrounding text needs an example, it is stated in prose. They also drop the Moq call names, the PIT and Infection metric names, a logging-library call, and the Entity Framework, `DbContext`, NHibernate and SQLite names. In `four-pillars-khorikov.md`, the brittle-test example is checking which internal methods the SUT calls, not verifying a SQL string literal. The rules the pages teach are unchanged ([#17769](https://github.com/melodic-software/claude-code-plugins/issues/17769)).

## [0.6.2] - 2026-11-21

### Changed

- **The principles skill's observable-behavior and testing-styles pages no longer teach through C# listings.** The C#, Moq, xUnit.net and Fluent Assertions code examples are cut from both pages. The leaking-API example, which communications to mock and the audit-system refactoring are now stated in prose, and the "Mock (the Tool) vs Mock (the Test Double)" section, which was framed around Moq's `Mock<T>`, is removed ([#17765](https://github.com/melodic-software/claude-code-plugins/issues/17765)).

## [0.6.1] - 2026-11-18

### Changed

- The snapshot-tool entry in the `characterization-testing.md` Sources list now links the Verify snapshot-management section and the Jest updating-snapshots and property-matchers sections, not just the pages.

## [0.6.0] - 2026-11-15

### Added

- **`reference/characterization-testing.md`, "When the Code Cannot Be Put in a Test Harness".**
  Feathers' exception to characterize-first: make only the dependency-breaking change, then
  characterize, then refactor; with his three seam types and each one's enabling point.
- **`reference/characterization-testing.md`, "Replacing a Legacy System in Steps".** Fowler's
  Strangler Fig as the incremental alternative to a rewrite.
- `/tdd:principles` routes both topics to that file, and its sources list names the publisher's
  sample of *Working Effectively with Legacy Code* (chapter 4 and the preface) as what was read.

## [0.5.4] - 2026-11-15

### Changed

- Restore the earlier skill wording a prompt audit cut without eval evidence, pending eval evidence of no loss.

## [0.5.3] - 2026-11-15

### Changed

- The Child Test trigger and the integration-test share of the test pyramid now match the Beck and Khorikov references they summarize.

## [0.5.2] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.5.1] - 2026-10-13

### Changed

- **`test-doubles.md`'s boundary-interface section is rewritten with its own example.** The section is now headed "One Function per Remote Operation" and uses a shipping-service example in place of the upstream user-and-orders one; the "Replace, Don't Layer" paragraph is reworded. The guidance and its subordination to "mock only unmanaged dependencies" are unchanged.

### Fixed

- **Implement routes to the Test stage before review.** `/implementation:implement` and `/implementation:implement-dispatch` now name the Test-stage skills in `## Next` (`/testing:plan`, `/testing:audit`, `/testing:run-e2e`), with `/review:quality-gate` once tests are planned, checked and green; the `testing`, `tdd` and `mutation-testing` skills that hand off name their successors too, so the graph runs implement, test, review, verify.

## [0.5.0] - 2026-10-06

### Added

- `/tdd:principles` adds two web-sourced references with routing rows: property-based testing (properties as what must never happen, shrinking, the patterns with their evidence levels, agent-authorship evidence with its qualifiers) and characterization testing (Feathers' recipe, approval and golden-master tests, the sabotage check, pins prove sameness, not correctness). The Sources section now separates the cover-to-cover book readings from these web sources.

## [0.4.11] - 2026-10-03

### Changed

- Cross-plugin routing to plugins that now install disabled says "enabled" where it said "installed": an installed but disabled plugin exposes no skills ([#5934](https://github.com/melodic-software/claude-code-plugins/issues/5934)).

## [0.4.10] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.4.9]

### Changed

- **`principles`: description prose no longer addresses the reader.** Anthropic's skill-authoring guidance keeps first and second person out of a description because it is injected into the system prompt; the rewritten clauses name the user, the session, or the repository instead. Quoted trigger phrases are unchanged.

## [0.4.8]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **Every markdown surface in the plugin passes `/ai-slop:audit`.** Em dashes in the plugin's own
  prose (this changelog, the principles skill body, and its thirteen references covering the
  Khorikov and Beck material) are rewritten as a comma, a period, a colon where a definition or
  list follows, or a restructured sentence. No principle, test-double distinction, coverage
  argument, or worked example changed.
- **Quoted Beck and Khorikov sentences keep their em dashes**, inside ignore markers naming the
  source in five places. Those dashes are the authors'. Where a `> — Author` attribution line
  carried the dash instead, the attribution moves to its own blockquote paragraph rather than being
  rewritten.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`,** so the gate defends
  it from here on.
- **Changelog, in-place wording corrections to released entries:** the same rewrite was applied
  inside `[0.4.0]` and `[0.3.0]`. Wording only; every entry's facts are unchanged.

## [0.4.7]

### Changed

- **principles:** the description drops three trigger phrases that restated a neighbor's intent
  ('what makes a good test', 'when to mock', 'TDD cycle'); the surviving phrases still name each
  intent.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.4.6]

### Changed

- **Authoring-doctrine pass over `skills/principles/reference/test-doubles.md`.** Fixed pointers and cross-references that did not resolve. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.4.5]

### Changed

- **Long reference files carry a `## Contents` index.** 3 reference files in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.4.4]

### Changed

- **Repo-wide `/ai-slop:audit fix` pass (#3359).** A digest bullet in
  `integration-testing-khorikov.md` reworded to "both your database and external
  applications"; the verbatim Khorikov quote in `anti-patterns-khorikov.md` stays
  untouched, covered marker-free by the detector's blockquote exemption
  (ai-slop 0.4.0).

## [0.4.3]

### Changed

- **Instruction-surface de-slop (#2891, tdd cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop leftover body-prose em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. YAML frontmatter is unchanged so the cheatsheet stays valid.

## [0.4.2]

### Changed

- **`principles`: the mutation-score aside names the Skill tool (#3002).** In
  `reference/four-pillars-khorikov.md`, the presence-gated `/mutation-testing:principles`
  invocation now says "via the Skill tool". Wording only; the without-it summary is unchanged.

## [0.4.1]

### Changed

- **SDK-style boundary interfaces are stated as subordinate to "mock only unmanaged dependencies"**
  (`test-doubles.md`, #2936). The section sat immediately below the five Khorikov mocking best
  practices but never declared a precedence relation to the first of them, leaving it readable as
  license to introduce an interface per external operation wherever one is convenient. It shapes a
  boundary already decided to be mocked; it never widens what gets mocked, and no interface is
  introduced for an in-process dependency to satisfy the shape.

## [0.4.0]

### Added

- **Mutation testing named as the partial exception to "no automated way to measure test suite
  quality"** (`code-coverage-khorikov.md`). The chapter's claim is about quality as it defines it and
  stands; one property, whether assertions can detect a fault rather than merely execute code, is
  automatically measurable, and a file at high coverage with a low mutation score is exercised but
  not checked. The note states the measurement's limits in the same breath (unknowable ceiling from
  equivalent mutants, and targeting the number reproduces the chapter's own perverse incentive).
- **The false-negative half of test accuracy tied to its measurement** (`four-pillars-khorikov.md`).
  A surviving mutant is a demonstrated false negative, not an estimate of one; nothing equivalent
  exists for the false-positive half, so the note is explicit that the measurement is lopsided and
  that optimizing for it trades away the other three pillars.

Both notes are presence-gated references to `/mutation-testing:principles` with the substantive
fallback stated inline, per the seam-phrasing convention.

## [0.3.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.2.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.0]

### Changed

- Renamed the `tdd` skill → `principles`. Update any `/tdd:tdd` invocations to `/tdd:principles`;
  the plugin ID (`tdd`) and marketplace listing are unchanged, only the skill's leaf name moved.
