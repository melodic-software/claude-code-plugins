# Changelog

All notable changes to the `debugging` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
  is also red — and the fix that turns *that* red green has not touched the bug, while the loop
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
  protection tracks only `'single-quoted'` phrases — so all nine (`'diagnose this'`, `'debug this'`,
  `'why is X broken'`, `'X is throwing'`, `'something is wrong with'`, `'investigate this bug'`,
  `'performance regression'`, `'this is slow'`, `'intermittent failure'`) were invisible to it and a
  future rewrite could have dropped any of them unnoticed. The wording is unchanged; only the
  quoting is.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
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
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.4.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.0]

### Changed

- **BREAKING: `/debugging:diagnose` is renamed `/debugging:debug`** — the skill runs the full
  repro → hypothesize → fix → regression-test loop, while "diagnose" promised only the first half
  and twinned confusingly with `/testing:diagnose` (a different skill, which keeps its name).
  Clean break per the marketplace naming effort: no renames-map entry; update invocations to
  `/debugging:debug`. "diagnose" stays a trigger word in the skill description. Claude Code's
  built-in bundled `/debug` skill is unaffected — the plugin skill has no bare command form and
  is invoked only as the namespaced `/debugging:debug`.
