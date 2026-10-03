# Changelog

All notable changes to the `debugging` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.0] - 2026-10-03

### Added

- **Interactive post-mortem view, built with the shared view builder (#5864).** `/debugging:debug` offers a
  view of its Phase 6 post-mortem: the loop, cause, fix and seam, the hypotheses with their verdicts and
  evidence, a tick for each the reader would re-open, and a copy-out of the challenge.
  `scripts/build-view.mjs` fills a checked-in template with the session's JSON as escaped data through
  `lib/view-builder.mjs` and `lib/view-runtime.js`, which the plugin now carries as generated copies with
  `lib/html-escape.mjs`. No page carries model-written markup or script, so log and error text stays data,
  and no page sits beside the post-mortem, which stays the record. The publish destination comes from the
  `medium` key of the `rendered-views` cascade (`file` when unset); the procedure is in
  `skills/debug/reference/rendered-view.md`.

## [0.7.14] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.7.13] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.7.12] - 2026-09-30

### Changed

- **The `debug` Boundary bullet in `debug` no longer asserts that the bundled skill ships with
  Claude Code.** It keeps the provenance class, what the skill does and how it is invoked, in the
  native-references template form.

## [0.7.11] - 2026-09-29

### Added

- **`debug` carries a Boundary section for the bundled `debug` skill.** The bundled skill debugs
  Claude Code itself and is reserved for the person to run, so the model offers `/debug` when the
  problem is Claude Code rather than the user's application.

## [0.7.10] - 2026-09-29

### Changed

- **`debug` Phase 5** takes the regression test's expected value from the bug report, never from
  what the fixed code returns.

## [0.7.9] - 2026-09-28

### Changed

- **Argument hints** on `debug` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.7.8] - 2026-09-28

### Changed

- `context/recommendation-basis.md` names the full convention by its path in the marketplace
  repository instead of an org-specific URL.

## [0.7.7] - 2026-09-28

### Changed

- **`debug`'s Phase 6 architectural recommendation carries a `Basis:`** and, when it touches
  shared code, is grounded in its consumers first, per the
  [recommendation-basis convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/recommendation-basis/README.md).
- **Ships `context/recommendation-basis.md`**, a byte-identical copy of the `discipline`
  recommendation-basis contract, since an installed plugin cannot read the repository's `docs/`.
  An unsettled consequential recommendation is withheld and filed as an open question.

## [0.7.6] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.7.5]

### Changed

- **The changelog drops its em dashes.** Wording only, with no change to any phase, gate, or trigger phrase; the nine backticked trigger phrases in the 0.6.1 entry are byte-identical. No heading was touched. The released sections corrected in place are 0.7.0, 0.6.1, 0.6.0, 0.4.2, and 0.4.0: their wording changed, their facts did not.
- **`load-bearing` stays in the 0.7.4 entry, because there it is a name.** It identifies which paragraph that release removed, and the same name is still live in `skills/debug/evals/evals.json` and the README. Rewriting it here would leave a reader unable to tell what was removed.
- **`CHANGELOG.md` is declared in `scripts/em-dash-purged-paths.txt`,** alongside the README and skill bodies the gate already defends.

## [0.7.4]

### Changed

- debug: removed the pre-investigation priming pass and its four bullets, the pressure line at the top of Phase 1, the duplicated load-bearing-artifact paragraph, the duplicated Phase 2 gate, the discovery/glob cost hypothesis, and the inert `shell: bash` frontmatter key; restated the hypothesis-grounding paragraph once and replaced the Boy Scout sentence with a focused-diff rule that agrees with the skill's own boundary; replaced the description's trigger-phrase list with intent categories; the bundled checklist no longer lets Phase 6 cleanup be skipped for tagged probes, and both bundled files drop their em dashes under the house style
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.7.3]

### Fixed

- **`debug`:** the git pre-compute lines moved out of `## Pre-computed context` into a "Repository
  context. Gather first" body section of individual Bash calls, one command per call, each `head`
  bound kept inside its command and a failure read as an unknown value. The harness composes a
  skill's whole pre-compute block into one shell invocation, and a worktree-isolated session refuses
  a git-bearing compound command, which blocked these skills from loading inside a worktree. Same
  shape as the worktree skill's fix in #1619. Non-git pre-compute lines stay where they were.

## [0.7.2]

### Changed

- **Dynamic-context probe fallback made reachable.** The working-tree-status injection piped its
  probe into `head` before `||`, so the fallback could never run and a failed probe rendered an
  empty string under a label that reads as a clean tree. The fallback now sits in a brace group with
  the probe and the cap applies outside it. Whole-repo extract-ssot sweep.

## [0.7.1]

### Changed

- **Instruction-surface de-slop (#2891, debugging cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.

## [0.7.0]

### Added

- **`debug` phase 5: the red step now has to be red for the right reason.** Step 2 said "Watch it
  fail (Red)" and stopped there. A test that errors on a typo, a bad import, or an unrelated defect
  is also red, and the fix that turns *that* red green has not touched the bug, while the loop
  reports a clean Red→Green cycle. The step now requires reading the failure message against the
  root cause being targeted, and repairing the test or the reproduction before any implementation
  edit when they do not match.

  Absorbed from an upstream cursor/plugins skill (`docs/upstream/cursor-pstack.md`, the `tdd`
  section), and the only part of its seven-step workflow that survived: an adversarial audit of the
  plan confirmed everything else was owned twice over, and would have let this one slip past
  unnoticed inside a wholesale rejection. Verified absent by reading the phase before landing.

## [0.6.1]

### Changed

- **`/debugging:debug`'s trigger phrases are now single-quoted.** They were written with escaped
  double quotes inside the double-quoted YAML scalar, and the skill-quality gate's trigger-drop
  protection tracks only `'single-quoted'` phrases, so all nine (`'diagnose this'`, `'debug this'`,
  `'why is X broken'`, `'X is throwing'`, `'something is wrong with'`, `'investigate this bug'`,
  `'performance regression'`, `'this is slow'`, `'intermittent failure'`) were invisible to it and a
  future rewrite could have dropped any of them unnoticed. The wording is unchanged; only the
  quoting is.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.0]

### Added

- **`debug`: standing redaction guard.** A new section ahead of the phases requires every
  secret to be redacted (`<REDACTED>`) before commands, outputs, or captured artifacts appear
  in a transcript, work note, or commit; loops read credentials from env vars, captured
  artifacts are quoted only at the lines carrying the diagnostic signal, and insufficient
  redacted output routes to the user instead of a wider quote. The no-loop escape hatch now
  asks for a *redacted* captured artifact. (Guard from upstream mattpocock/skills
  `diagnosing-bugs` v1.2.3; registry: the marketplace repository's
  `docs/upstream/mattpocock-skills.md`.)

## [0.4.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention. Bash-only pipelines must not fall through to a
  PowerShell host.

## [0.4.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.0]

### Changed

- **BREAKING: `/debugging:diagnose` is renamed `/debugging:debug`.** The skill runs the full
  repro → hypothesize → fix → regression-test loop, while "diagnose" promised only the first half
  and twinned confusingly with `/testing:diagnose` (a different skill, which keeps its name).
  Clean break per the marketplace naming effort: no renames-map entry; update invocations to
  `/debugging:debug`. "diagnose" stays a trigger word in the skill description. Claude Code's
  built-in bundled `/debug` skill is unaffected. The plugin skill has no bare command form and
  is invoked only as the namespaced `/debugging:debug`.
