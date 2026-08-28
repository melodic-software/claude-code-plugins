# Changelog

All notable changes to the `verification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.8]

### Changed

- **Two restated collaborator handoffs regained the gates their owners carry.** The live-app fallback
  restated the `/testing:run-e2e` handoff without the installed-ness condition and fallback the same
  file states 35 lines earlier, and the lint-auto-fix pointer named `/toolchain:lint --fix`
  unconditionally where the Stage 1 delegation gates the same plugin. Both now match. Coupling pass,
  apply lane.

## [0.5.7]

### Changed

- **The artifact-placement sentence names its actor first.** It opened passive with no actor, where
  the actor is named two words later, and its parenthetical closed after a second independent
  sentence. Docs-hygiene sweep, L8-write-for-humans.

## [0.5.6]

### Changed

- **Instruction-surface de-slop (#2891, verification cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.5.5]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.5.4]

### Changed

- **Cross-skill chains name the Skill tool (#3002).** `confirm`'s Stage-1 delegation (both the
  stage table and the prose), the measurable-delta redirect row, the **primary** live-app
  delegation to `/testing:run-e2e` — left bare by the first pass while its own fallback was
  rewritten, directly under a heading reading "`/verification:confirm` delegates rather than
  reimplementing app-launch" — plus both of those fallbacks, the lint auto-fix pointer, and the
  improvement-claim route to `/verification:measure`; `measure`'s green-tree precondition and
  `context/metrics.md`'s mutation-score collection. Wording only — the STOP-on-fail gate,
  presence gates, and manual fallbacks are unchanged.
- **`confirm`: two rewrites re-worded so they read as one clause again (#3002).** The Stage-1
  table cell had stranded the architecture-test gate inside the invocation phrase
  ("… cross-cutting via the Skill tool + architecture-test gate"), and the improvement-claim
  gotcha had split the original compound ("route to `/verification:measure`, invoked via the
  Skill tool, and its baseline discipline"). Both now name the mechanism without breaking the
  sentence.
- **`confirm`: the "which do you reach for" catalog stays prose (#3002).** The first pass
  rewrote clause 1 of a four-clause capability catalog ("**Quick mechanical-only?** …
  **Lint-only?** … **Tests-only?** … Reach for `/verification:confirm` when …") and left the
  other three, leaving the paragraph internally inconsistent. It is a catalog mapping a
  situation to the sibling that covers it — a mention under the rubric — so clause 1 is back to
  "Use `/toolchain:check` (not `/verification:confirm`)."

## [0.5.3]

### Fixed

- **README opener said "Two skills" for a three-skill plugin.** `/verification:setup` was added
  without the sentence above the table being recounted, so the front page understated the set while
  the table right below it listed all three. Found by `scripts/check-skill-count-claims.sh`, a new
  fleet gate that compares every hand-written skill count against the tree.

## [0.5.2]

### Changed

- **`/verification:measure`'s `description` is now a trigger spec rather than a summary.** A skill
  `description` is the text Claude matches to decide whether to load the skill, and this one opened
  with what the skill *is* and buried its routing phrases behind `use for`, so the skill
  under-fired: the skill-quality gate flagged it as carrying no `Use when:` trigger phrasing
  (claude-code-plugins#2174). The phrases now sit behind `Use when:` in the marketplace's house
  shape, and six phrases a user would actually type — `'did that actually speed it up'`,
  `'how much faster is it'`, `'measure this'`, `'capture a baseline'`,
  `'benchmark before and after'`, `'did complexity go down'` — join the three that were already
  there. Every phrase the previous description carried is preserved verbatim — including
  `'cannot quantify'`, which is prose the gate's extractor nonetheless tracks as a trigger — so the
  trigger-keyword-preservation check sees a superset, not a rewrite.
- **`/verification:confirm`'s `description` now uses `Use when:` too.** It had the same shape: three
  good routing phrases (`'verify changes'`, `'prove this works'`, `'did we build the right thing'`)
  behind a lowercase `use for` the gate does not recognize as trigger phrasing. All three are
  preserved verbatim and `'is this done'`, `'check my work'` and `'did the fix actually work'` join
  them.

## [0.5.1]

### Changed

- **The bundled `/verify` invocability claim is now scoped as a default, and its stamp refreshed to
  2026-08-10.** 0.3.6 recorded that v2.1.215 made `/verify` user-invoked only, and that was exact for
  2.1.215–2.1.224: the shipped client carried a hard model-invocation block. A recheck against the
  bundled-skills reference and the shipped 2.1.223–2.1.226 clients found that from **2.1.225** the
  block became a runtime gate able to re-enable model invocation, so the restriction is the
  *default* rather than an absolute and two clients on one version can differ. The delegation
  prohibition 0.3.6 introduced is unaffected and now rests on firmer ground: a delegated call is
  **refused at the tool layer**, not merely discouraged, so suggest-don't-delegate holds across
  either invocability state rather than on the version cutoff alone. The stamp moves from
  2026-08-02 to 2026-08-10 and now names the client versions checked, not only the doc page.
- **An observable recheck trigger joins the stamp.** `docs/conventions/upstream-drift/README.md`
  §Adopters binds the required record parts *on touch* for a surface restating an upstream-owned
  specific, and 0.3.6's record carried a date and basis but no trigger — so nothing obliged the next
  recheck, which is why a v2.1.225 behavior change sat unnoticed until now. The claim now fires on a
  Claude Code release whose changelog names `/run`, `/verify`, `/run-skill-generator`, or
  bundled-skill invocability.
- **Eval 9 (`live-app-delegates-to-bundled-with-fallback`) moved with the wording**, in both its
  `expected_output` and its expectation string. 0.3.6 hit the same hazard from the other direction —
  the eval had encoded the removed delegation as a pass condition — and leaving either field on the
  old "user-invoked only" phrasing would have graded the corrected skill as failing.

## [0.5.0]

### Added

- **Covered-code mutation score as the proxy for a "better tested" claim** (`measure/context/metrics.md`).
  The quality-metrics table previously offered only test count and assertion count for test
  coverage — both of which rise with assertion-free tests. The new row and section name the metric
  that measures fault detection directly, instruct reporting it as a diff-scoped delta rather than a
  whole-repo figure, and carry the three caveats that must travel with the number: scores are not
  comparable across repositories or operator sets, the ceiling is below 100% by an unknowable margin
  because equivalent mutants cannot all be removed, and known flaky tests inflate it by an unknown
  amount. Explicitly not a pass/fail bar.
- Presence-gated reference to `/mutation-testing:audit` per the seam-phrasing convention, with the
  fallback stated inline (run the ecosystem's own tool diff-scoped and read the covered-code figure)
  and the no-tool case handled by saying the proxy is unavailable rather than substituting a
  coverage number for it.

## [0.4.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.3.7]

### Changed

- **`/verification:confirm`'s Stage-2 pointer now promises what `context/outcome.md` actually
  defines.** The step-6 line advertised a "severity vocabulary" that file never had — it defines only
  the binary `CONFIRMED` / `NEEDS WORK` verdict — so a model chasing the pointer either invented a
  severity scale or dropped severity silently. It now points at the verdict criteria.
- **The Stage-1 subagent trigger names a size, not a judgement call.** "The mechanical pass is
  non-trivial" became "spans more than a handful of commands"; the multi-ecosystem trigger is
  unchanged.
- **Shout-emphasis dropped where the surrounding text already carries the weight.** The refactor
  criterion's "ALL tests", the live-app fallback's "SAY SO", and the UI evidence contract's "NO
  absolute paths" now read in sentence case — the adjacent scope, the "never silently swap" clause,
  and the enumerated constraint list respectively make each requirement unambiguous on their own.

## [0.3.6]

### Changed

- **The live-app delegation path no longer tells the skill to invoke the bundled `/verify`.**
  Claude Code v2.1.215 made `/verify` and `/code-review` user-invoked only — Claude does not run
  them on its own — so **from v2.1.215** every instruction routing this skill's live-app run through
  `/verify` named a surface it cannot reach, silently costing the fallback its primary leg. The
  shipped wording carries that version rather than stating the restriction flatly: on 2.1.145–2.1.214
  `/verify` is still model-invocable, and this repository declares no Claude Code support floor that
  would make an unscoped statement true. The *instruction* stays uniform across the window even so —
  suggesting `/verify` is correct on every version it exists on, so the skill never probes the
  client's version. `/run` is unaffected
  (the change names neither it nor the `run-skill-generator` sibling) and stays the supplementary
  agent-invocable path; `/verify` is now surfaced as a suggestion for the user to run. The
  `≥ 2.1.145` availability floor is **unchanged and re-verified 2026-08-02** against the bundled
  skills reference, which still states it for all three of `/run`, `/verify`, and
  `/run-skill-generator` — that note was never stale; what changed is who may invoke one of them.
  The `confirm` skill's graded rubric moved with the behavior: eval 9
  (`live-app-delegates-to-bundled-with-fallback`) had encoded the removed `/verify` delegation as a
  pass condition, and would otherwise have graded the corrected skill as failing.

## [0.3.5]

### Changed

- **Setup no longer hardcodes a publisher and repository name in the schema reference.** The skill
  pointed at a `raw.githubusercontent.com/<publisher>/<repo>` URL for `topic-docs.schema.json`,
  binding a runtime-consulted reference to one forge account inside a plugin that is otherwise
  publisher-agnostic — a fork, a mirror, or a rename leaves the skill citing someone else's schema.
  It now names the schema by the convention's own filename and defers to `reference/topic-docs.md`,
  the binding it already cites one paragraph earlier, which carries the single pointer to the
  published convention. One coupling site per plugin instead of two, and the one that remains is the
  file whose job is to cite upstream.
- **The setup skill now says why its body matches `discovery`'s byte-for-byte.** Most of it does,
  and nothing on the page said whether that was a shared source to extract or a coincidence to
  leave alone — so the next reader either re-litigates it or "deduplicates" two skills that are
  supposed to be free to diverge. They are: both restate rules the topic-docs contract and the
  marketplace setup contract already own, which is what a `SKILL.md` must do since it cannot defer
  at runtime to a document the consuming repo lacks. `planning` renders the same rules in its own
  prose and already disagrees with both on two of them. A maintainer note at the block points at
  the contract's new "Implementers restate the rules" section, which carries the reasoning and the
  trigger that would reopen extraction.

## [0.3.4]

### Changed

- The cross-vendor reviewer example in `/verification:confirm`'s "Independence of
  the verdict" no longer names advisor commands: it gates on the advisor's
  documented surface being able to take the judged artifact and defers invocation
  mechanics (waiting, diff-base selection) to that plugin's own docs — per-site
  command flags drift against the surface the advisor owns.

## [0.3.3]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.2]

### Changed

- Documentation-only: `/verification:confirm`'s live-app delegation section now
  acknowledges the enriched `/testing:run-e2e` — subagent-isolated surface runs, an
  optional recording / session-artifact evidence tier (config-driven, defaults off),
  and a structured verification-environment gap report on prerequisite failure. The
  bundled `/verify` + `/run` supplementary path and its presence gate are unchanged,
  as are the stage and verdict machinery. No behavior change.

## [0.3.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.0]

### Added

- **`/verification:setup` — settles the topic-docs seam for the consuming repo.** Offers the tracked
  `.claude/topic-docs.yaml` concern file that governs where `/verification:confirm` lands its manifests
  (contract tier) and `/verification:measure` lands its baselines and raw captures (memory tier). `check`
  (default) reports the effective concern read-only; `apply` persists it — non-interactively from
  complete `<key>=<value>` arguments or via a one-question, recommendation-first interview — running the
  committed-tier `git check-ignore` guard before writing and never editing the consumer's root
  `.gitignore`. Mirrors the `/discovery:setup` and `/planning:setup` pattern, offering the shared file
  independent of whether the sibling lifecycle plugins are installed. This concern was previously offered
  by `/toolchain:setup`, a build/test/lint plugin that owns no lifecycle artifacts. Part of #263.

## [0.2.4]

### Changed

- Presence-gated the `dotnet-*`/`cloudflare` marketplace-skill evidence pointers in the `measure`
  contexts, superseding 0.2.3's "unchanged" note. `metrics` and `performance` now carry the
  `## Marketplace plugin skills (invoke only when installed)` guard heading (matching the `testing`
  plugin's gated lists) plus a lead-in that frames the `dotnet-*` skills as .NET-only and
  `cloudflare:web-perf` as web-frontend-only, each invoked only when its plugin is installed and
  otherwise falling back to the project's own tooling — the generic complexity/coverage or
  benchmark/profiling harness where that fits, with a tailored per-bullet fallback where the
  evidence type differs (query logging / database profiling / ORM diagnostics for EF-query
  analysis, a test-quality analyzer or test-smell review checklist for test-quality analysis,
  web-vitals tooling for Core Web Vitals). This removes the bare unguarded cross-plugin
  reference `docs/PLUGIN-PHILOSOPHY.md` names as a defect; no hard dependencies added, every
  reference stays optional.

## [0.2.3]

### Changed

- Neutralized the .NET/C#/PowerShell-flavored illustrative examples in the
  stack-agnostic `confirm` and `measure` skills so a non-.NET consumer isn't
  handed a stack-specific illustration as the universal path: the reproduction-test
  example uses a generic descriptive name and failure, and the metric/perf
  "how to check" cells count import/dependency declarations and point to "your
  test runner"/"your benchmark harness" instead of `using`/`ProjectReference`/
  `dotnet test`/BenchmarkDotNet. The Unix-shell `wc -l` line-count assumption is
  now stated shell-neutrally (`wc -l` on POSIX/Git Bash, `Measure-Object -Line`
  in PowerShell), honoring the cross-platform "never assume Bash" contract. The
  named marketplace-plugin evidence pointers (`dotnet-*`) are unchanged.

## [0.2.2]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/testing:run-e2e`); behavior unchanged.

## [0.2.1]

### Changed

- **Freshness rider on the bundled `/verify` + `/run` availability claim**
  (fleet conformance wave). The ≥ 2.1.145 floor is re-verified against the
  official bundled-skills docs and now carries a verified-date + link.

## [0.2.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states
  baselines and raw captures are checkout-local, and `/verification:measure` writes distilled
  values only into `PLAN.md` — never a memory-slice capture path (pointer discipline).

## [0.1.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.1.0]

### Added

- Initial release — two skills extracted and renamed from the `implementation` plugin's `verify-*`
  skills: `/verification:confirm` (was `verify-changes` — the mechanical prerequisite gate then
  intent-match + evidence + verdict) and `/verification:measure` (was `verify-improvement` —
  baseline/compare measurable-improvement verification). Skill trigger phrases and evals are preserved;
  only the namespace and leaf names changed.
- Bundled reference: the plugin-local `reference/topic-docs.md` binding (verification manifests and
  baselines placement) and the byte-identical `reference/artifact-protocol.md` lifecycle profile shared
  across participating lifecycle plugins.
- Cross-plugin delegation degrades gracefully: the Stage-1 mechanical pass delegates to
  `/toolchain:build` and `/toolchain:lint` when the `toolchain` plugin is installed (else the project's
  ecosystem-native commands), and live-app verification prefers `/testing:run-e2e` when the `testing` plugin
  is installed (else bundled `/verify` + `/run` or a manual orchestrator launch) — no hard dependencies.
