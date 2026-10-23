# Changelog

All notable changes to the `debugging` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.13.0] - 2026-10-23

### Changed

- Exports are written under the run's `${work:?}` directory, so cleanup deletes only that directory.
- When `mktemp -d` fails because the temporary directory is read-only, `/debugging:analyze-profile` makes its SQLite work directory with `mktemp -d "<writable dir>/profile.XXXXXX"` under a writable directory outside the repository, so the `rm -r` at cleanup only ever deletes a directory this run created.

### Removed

- `/debugging:analyze-profile` no longer records profiles: capture mode, the `capture <symptom and process>` argument, `reference/capture-by-symptom.md` and the three capture skill evals and two capture plugin eval cases are gone. With no artifact in hand the skill stops and names `/app-control:drive capture --kind <trace|cpu|heap>` as the command for the person to run, and never invokes drive or a recorder itself, attended or not. Two new eval cases, one attended and one unattended, check that a capture request names `/app-control:drive capture`, runs no profiler and makes no Skill call to drive.
- `prerequisites.json` drops the record-only profilers (py-spy, jcmd, dotnet-stack, heaptrack, gdb, sample, spindump, leaks) and no longer lists node for analyze-profile; the remaining exporters (memray, jfr, dotnet-trace, dotnet-gcdump, go, perf, addr2line) describe only reading or converting an existing file.

## [0.12.0] - 2026-10-22

### Added

- `/debugging:debug` Phase 2 gains a Minimize step: cut inputs, callers, config, data and steps one at a time, keep a cut only when the loop stays red, and stop when every remaining element is needed. The Phase 3 gate now requires the minimized reproduction.
- `/debugging:debug` Phase 5 step 2 asks for a diff against a pristine copy when the red was forced by editing code or a fixture, to confirm the edit landed before the red is trusted.
- `/debugging:debug` notes that every answer the human-driven script collects with `ask` is pasted back into the session, so it asks only for observations and leaves signing in to an `instruct` step.

- `/debugging:analyze-profile`'s `query_profile.py` gains two read-only subcommands for converted heap snapshots: `compare <before.db> <after.db>` lists which heap types grew between two snapshots, and `retainers <db> <idx>` prints the shortest non-weak path from the root to one heap object.

### Fixed

- The `.cpuprofile` format pointer targets the DevTools Profiler domain page; its `#type-Profile` anchor is rendered client-side and failed the online link check.

### Security

- Credential guards now catch stateless GitHub App installation tokens (`ghs_` followed by a JWT), using GitHub's recommended `ghs_` regex where a guard matches the whole token.

## [0.11.2] - 2026-10-20

### Fixed

- Shared `prerequisites.mjs` synced: a `node-pkg` or `python-pkg` entry reads `CLAUDE_PLUGIN_DATA` only when its last path segment is this plugin's name or starts with `<plugin>-`, and treats a literal `${...}` value as unset, so another plugin's data directory reports `unverified` instead of `missing`.

## [0.11.1] - 2026-10-16

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.

## [0.11.0] - 2026-10-13

### Added

- `/debugging:analyze-profile`, a new skill that reads a captured CPU profile, heap snapshot or performance trace down to a file:line cause and stops there, with no fix. Load mode converts Chrome trace events, V8 `.cpuprofile` and `.heapsnapshot` files into SQLite with a stdlib Python script (`scripts/trace_to_sqlite.py`, which writes `<out>.partial` and renames it on success, refuses to overwrite, refuses input over 512 MiB after gzip decompression, and stores GitHub tokens, AWS access key ids and `Bearer` values in any field as `<REDACTED>`, only those shapes, so its output is still reviewed by hand) and queries them with `scripts/query_profile.py`, which allows only reads (no ATTACH, VACUUM, PRAGMA or writes); per-format pages hold the queries, and other formats go through their own exporters first. Capture mode picks the recording by symptom, prefers launching the target under the profiler, attaches only to a process the user names and only after a yes per capture, puts any elevated command in a script file it shows first, and refuses when no one is present to answer. The SQLite directory and any raw capture are deleted at the end unless the user keeps them. `/debugging:debug` hands it an artifact with no reproduction (Phase 1) or a profile an instrument step wrote (Phase 4), and names it in its description and `## Next`.
- A plugin-level eval suite under `evals/` (load mode, capture consent, the unattended refusal, debug's hand-off) and a `prerequisites.json` declaring Python 3.10 as required and the profilers and symbolizers the capture table names as optional, with the generated `lib/prerequisites.{mjs,sh,ps1}` checker copies.

- `/debugging:debug` names the belief behind every attempt in one sentence and checks it once a second fix fails (advisory; Phase 1 stays the only hard gate); tallies a symptom that is uneven across workers or hosts with a script run on every loop pass; ranks stored state first when a failure follows a restart with no code change; and prefers the test that rules out more hypotheses. Edits made for a refuted hypothesis are dropped before the fix commit, a load imbalance is fixed in the code that picks a worker, and the report and PR description show the red and green loop runs. On a request for a diagnosis only, it stops at the confirmed hypothesis with no fix. A shipped workaround needs a tracking link or removal condition (the `unjustified-workaround` shape), and a new `## Next` section names `/verification:confirm fix` and `/implementation:implement fix`.

### Changed

- **`/debugging:debug` is restated in its own words, with one running example.** The skill now follows one case (photo uploads over 20 MB failing with a 502) through every phase. Phase 1 ranks the ten loop kinds in a table with a "choose it when" column, ends with an exit check (about 2 seconds, one verdict, the reported symptom only), and gives intermittent failures a table of levers and the no-loop case a three-part report. Phase 3 writes hypotheses as a ranked table with "refuted if" and "supported if" columns, Phase 4 chooses probes from a table, the correct-seam rule in Phase 5 is a decision table, the secrets rules are a table by kind of text, and the Phase 6 checklist is grouped into removing what the run added, proving the fix, and leaving a record. The human-run loop template was rewritten: its helpers are `instruct` and `ask`, and it ends with a `=== results ===` block of `NAME=value` lines. The README phase list, the checklist's Phase 1 line and the ecosystem reference's pointer to the Phase 1 heading were updated to match. Behavior is unchanged.
- Reworded `/debugging:analyze-profile`'s purpose, load-mode steps and unresolved-frame eval, and
  `/debugging:debug`'s restart, uneven-load, refuted-edit, worked-example, red-and-green,
  workaround and second-failed-fix passages in our own words, each in a structure of its own.
  Behavior is unchanged.
- Reworded `/debugging:analyze-profile`'s pre-answer checks as a table keyed by what the draft does, and its unresolved-frame eval name, in our own words. Behavior is unchanged.

- **The bundled `debug` record points at the live sections instead of paraphrasing them.** What `/debug` enables, when its logging starts, and the settings that remove or hide a bundled skill are read at anchored commands and skills sections, with an as-of date and a recheck trigger.

### Fixed

- **`trace_to_sqlite.py` refuses a heap snapshot with a negative type or name index**, which used to count silently from the end of the table, and one whose edge array holds more edges than the nodes' edge counts.
- **`query_profile.py --param` binds a decimal such as `1000.5` as a number**, where it used to bind it as text; `nan`, `inf` and other text stay text.
- **`/debugging:analyze-profile` can find the samples inside a trace event.** `samples` gains `ts`, the profile's `startTime` (from the trace's `Profile` event, or the `.cpuprofile`'s own) plus every delta so far, and the Chrome trace page adds a query joining `samples` to one event by that clock, as the skill's "done when" for traces already asked.
- **`/debugging:analyze-profile` keeps the profiles of one trace apart.** Each `pid:id` profile numbers its frames from 1, so the caller-path and outside-JavaScript queries on the `.cpuprofile` page now join on `profile` as well as the frame id, and the caller path takes `--param profile=`; they used to merge caller chains and double counts across profiles.

- Shared library comments that restated Claude Code hook, plugin and managed-settings behavior now point at the live docs sections, and the prerequisites probe no longer gives a wrong reason for always exiting 0.

- **The shared prerequisites checker now finds a `python-pkg` in the plugin's own installed Python
  set.** A module that the interpreter cannot import on its own is looked up in the set a plugin
  with a committed `requirements.txt` installs into its data directory
  (`<data>/python/<lock hash>-<interpreter tag>/`), imported the way that plugin's launcher runs
  it. Before, such a package was reported missing. When the data directory is unknown (no
  `--data-dir`, no `CLAUDE_PLUGIN_DATA`), the entry reports `unverified` instead of failing.
  Refs #6112.

## [0.10.0] - 2026-10-11

### Changed

- **`/debugging:debug` Phase 6 names an owner for a check-shaped prevention answer.** A mistake a deterministic check could catch goes to `/review:audit-enforceability` when it is a repo or policy mistake, or to `/session-flow:retro` when it is agent behavior, each named only when installed. The skill proposes the check and never builds it.

## [0.9.2] - 2026-10-10

### Changed

- `/debugging:debug` `## Next` sends a root cause that needs a design change to `/planning:interview` and names `/session-flow:workflow` for a session unsure where it stands.

## [0.9.1] - 2026-10-07

### Changed

- The post-mortem's rendered-view reference treats `medium: hosted` as `artifact`: the view is never sent to a page host.
- Shared `view-runtime.js` synced: a page served top-level over `https:` keeps its save button.

## [0.9.0] - 2026-10-06

### Added

- `/debugging:debug`'s ecosystem reference adds Python and TypeScript timing-injection rows (frozen or injected clocks, seeded test order with replay, network blocked by default, fake timers, Playwright's page clock, route mocking). Only .NET had one before.

## [0.8.5] - 2026-10-04

### Added

- **`debugging` ships a `claude plugin eval` suite for `/debugging:debug`.** The seven skill-creator cases in `skills/debug/evals/evals.json` are converted to case directories under `evals/` (tag `converted`), and three new cases (tag `phase1-red-run`) check that Phase 1 runs a reproduction command and observes its failing output before the first edit. Graders are deterministic where the behavior allows (`regex`, `tool_order`, `tool_used`, file-content regex), with a judge rubric beside them where the expectation is a judgment; every grader has pass and fail samples. The Bash-granting cases need `--scaffold` and `--allow-tools Bash,Edit,Write`. No skill text changes.

## [0.8.4] - 2026-10-04

### Changed

- **`/debugging:debug` names its successors ([#6279](https://github.com/melodic-software/claude-code-plugins/issues/6279)).** A new `## Next` section routes a landed fix with its regression test to `/review:quality-gate`, a design-flaw root cause to `/planning:plan`, and a failure no loop could reproduce to `/bugs:write --file`. The redesign escalation now names `/planning:plan` when the `planning` plugin is installed, with a generic fallback otherwise.

## [0.8.3] - 2026-10-04

### Changed

- The shipped recommendation-basis contract (`context/recommendation-basis.md`) follows the convention's 2.0.0 grounding bar: a design pattern is grounded in the canonical source that defines it, not in how popular it is; recency never discounts a canonical pattern definition; and a pattern found in a template, sample, or popular repository is checked against the principle it claims to serve.

## [0.8.2] - 2026-10-04

### Fixed

- Shared `view-runtime.js` synced ([#6173](https://github.com/melodic-software/claude-code-plugins/issues/6173)): pages built by `/debugging:debug` (post-mortem) no longer say they saved a file. The claude.ai artifact viewer blocks a download the page starts itself without an error the page can see, so the page reported a save that never happened. The "Save as file" button now appears only on a page opened from `file://` or served by the session bridge on `127.0.0.1`, and after a download attempt the status reads "If no file was saved, select the text below and copy it." "Copy reply" and the selectable payload text are unchanged.

## [0.8.1] - 2026-10-03

### Changed

- Shared `view-builder.mjs`, `view-runtime.js` synced ([#5868](https://github.com/melodic-software/claude-code-plugins/issues/5868)); no change to this plugin's own behavior.

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
