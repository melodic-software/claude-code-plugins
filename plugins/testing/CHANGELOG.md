# Changelog

All notable changes to the `testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.22.12] - 2026-10-04

### Changed

- The SessionStart node-notice rows now match `startup|resume|clear|fork`, so a compaction no longer starts them; the session and its notice latches survive a compaction, so a re-fire printed nothing (#6251).
- The `test-scan-bash` row starts the launcher with `--skip-unless-stdin-contains bashEditDiff`, so a Bash payload with no change diff starts node only (#6253). The shared `exec-bash.mjs` launcher copy also gains `--skip-if-all-false`, which no testing row uses (#6252).

### Fixed

- The `test-judge.test.sh` link fixtures now run only when a real native symlink can be made, so cleanup of a self-nesting tree can no longer spin (#6248).
- The link cases fail, not skip, when the native-link probe fails in CI (#6248).
- The judge test helper runs `jq` with MSYS path conversion off on each call, so the Stop path hashes the project key the recorder wrote on Windows (#6266).

## [0.22.11] - 2026-10-04

### Changed

- **Shared hook notice text ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)).** Skip notices from the shared hook helpers are never renewed: each tells the model once per agent and the user once per session, and says the notice will not repeat. A missing-tool notice no longer carries the hook's PATH; that goes to the debug log. The SessionStart notice for a missing node goes to the user only, in one shorter line. The jq `degrade` text in `prerequisites.json` no longer says the skip lasts the session or that the hook says so once.

## [0.22.10] - 2026-10-04

### Fixed

- `/testing:audit` now reports C# assertions that cannot fail as `rule-inert-assertion` in xUnit and NUnit suites: `Assert.True(true)`, `Assert.False(false)`, `Assert.NotNull` of a `typeof` or `nameof` expression, and `Assert.True` or `Assert.False` comparing two of them, such as `nameof(Widget) == typeof(Widget).Name` (#6040).
- An inert C# assertion no longer also counts as an oracle, so `Assert.NotNull(typeof(Widget))` is reported once, as inert, not also as `rule-weak-oracle` (#6040). Because an inert line no longer counts as a strong oracle either, a weak oracle beside a bare `.Should();`, or beside an MSTest `Assert.IsTrue(true)`, is now reported.

## [0.22.9] - 2026-10-04

### Fixed

- `/testing:audit` no longer reads a C# test's own signature as an assertion. A test named `Diagnostics_CheckConnectionStrings`, or a theory with an `expected` parameter, whose body only prints is now reported as `rule-zero-assertion` ([#6040](https://github.com/melodic-software/claude-code-plugins/issues/6040)).
- A C# test whose body sits on its declaration line, `{ ... }` or `=> ...`, is now checked for `rule-weak-oracle`, `rule-snapshot-only` and `rule-inert-assertion`, as a multi-line body is. An async assertion a `Task`-returning expression body returns (`System.Threading.Tasks.Task` written out included) is awaited by the runner and is not reported; in an `async` test the expression's value is discarded, so it is, also when the expression wraps to the line after its `=>` ([#6040](https://github.com/melodic-software/claude-code-plugins/issues/6040)).

## [0.22.8] - 2026-10-04

### Changed

- **Upstream plugin doc links repointed to the split `plugins/` pages ([#5962](https://github.com/melodic-software/claude-code-plugins/issues/5962)).** The README options block now links `plugins/cli-reference#plugin-install` for the `--config` flag, since the old `plugins-reference` page no longer carries that section, and `plugins/manifest-reference#user-configuration` for the `userConfig` schema.

## [0.22.7] - 2026-10-04

### Changed

- The README notes that an installed mod can stop this plugin's `PreToolUse` hooks from running and can approve a call they blocked, with links to the two mods events sections. Nothing the plugin runs changed.

## [0.22.6] - 2026-10-04

### Fixed

- The task-end test judge resolves the repository from the test file's own directory when it runs, taking a Git Bash backslash path at either separator, instead of trusting the recorded one, which could be the hook's working directory's repository ([#5924](https://github.com/melodic-software/claude-code-plugins/issues/5924)). A test file a subagent wrote in a linked worktree is now judged in that worktree, and its findings land under the worktree's `.work/reviews/<branch>/`. A file in no repository is reported UNKNOWN, "no repository", and does not block Stop. A file whose toplevel, as git names it, does not hold it is not judged: it is logged as a malfunction ([#6099](https://github.com/melodic-software/claude-code-plugins/issues/6099)).
- The judge's allow rule is now absolute, `Read(//<repository>/**)` (on Windows `//c/...`). The old `Read(<repository>/**)`, `Grep(...)` and `Glob(...)` rules anchored at the working directory, so they matched nothing. A `\`, `*`, `?`, `[` or `]` in the repository's path is escaped with a backslash, so the rule's gitignore pattern names only that directory ([#6099](https://github.com/melodic-software/claude-code-plugins/issues/6099)).
- A judge run in which Claude Code denied a tool call (the result's `permission_denials`) and that gives no test a FLAG or PASS is a malfunction. Its UNKNOWN verdicts, such as "the Read permission was denied", are dropped and logged, those tests are named as not judged, and Stop is not blocked. A denied run that gives any FLAG or PASS keeps every verdict, UNKNOWN included, so one denied read cannot mute the other tests of the file ([#6099](https://github.com/melodic-software/claude-code-plugins/issues/6099)).

## [0.22.5] - 2026-10-04

### Fixed

- The task-end test judge no longer blocks Stop when every relayed verdict is PASS, or UNKNOWN only because there is no repository or no judge class. The findings file and the systemMessage, with the counts and the path, are still written. A FLAG, or an UNKNOWN for any other reason, still blocks once with the relay template ([#6037](https://github.com/melodic-software/claude-code-plugins/issues/6037)).
- Test files under the system temp directory (`TMPDIR`, `TMP`, `TEMP`, and `/tmp` and `/var/tmp` when none is set, which is the default on POSIX hosts), including its Windows long and 8.3 short drive spellings when Git Bash reports the temp variables as `/tmp`, and files in a Claude session scratchpad (`.../claude/<project>/<session>/scratchpad/`) are not recorded, so the judge does not run on those working copies ([#6037](https://github.com/melodic-software/claude-code-plugins/issues/6037)).

## [0.22.4] - 2026-10-03

### Fixed

- **The `SessionStart` node-notice row no longer runs `powershell` on Linux.** It stopped at `${BASH_VERSION:+exit}`, which only bash sets; Claude Code runs hooks with `/bin/sh`, which is dash on Debian and Ubuntu (WSL included), so every session printed `powershell: not found`. The row now stops at `${PPID:+exit}`, which every POSIX shell sets.

## [0.22.3] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.22.2] - 2026-10-03

### Changed

- `scripts/gen-hook-filters.test.sh` and `skills/setup/scripts/setup.test.sh` declare the files they read without naming them in `# test-scope:` headers, so CI's test selection runs them when one of those files changes. Nothing the plugin runs changed.

## [0.22.1] - 2026-10-03

### Changed

- **Shared `hook-utils.sh` synced ([#5838](https://github.com/melodic-software/claude-code-plugins/issues/5838)); no change to this plugin's hooks.**
  It is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copy.

## [0.22.0] - 2026-10-03

### Added

- A `SessionStart` hook row reports a missing `node` once per session, on both hook channels, and works on Windows without Git Bash. The notice names `/testing:check`. The row is shared across plugins, so a session with several of them sees one notice.
- `lib/prerequisites.mjs`, `lib/prerequisites.sh` and `lib/prerequisites.ps1`, the generated copies of the shared prerequisites checker and its `node-notice` stubs.

### Changed

- The shared hook helper has `hook::require <id>` in place of `hook::require_jq`. Its skip notice is built from the plugin's declared `prerequisites.json` entry and names `/<plugin>:check`, not `/harness-ops:prerequisites`.
- Hooks call `hook::require jq` where they called `hook::require_jq`.

## [0.21.4] - 2026-10-02

### Changed

- **Shared `exec-bash.mjs`, `rewrite-guard.sh` synced ([#5837](https://github.com/melodic-software/claude-code-plugins/issues/5837)); no change to this plugin's hooks.**
  Each is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copies.

## [0.21.3] - 2026-10-03

### Changed

- `prerequisites.json` is converted to the schema `docs/conventions/prerequisites/` owns: a `requires` list whose entries carry `id`, `kind`, `need`, `for`, `detect`, `degrade`, `install` and `check`, in place of the retired `tools` list ([#5840](https://github.com/melodic-software/claude-code-plugins/issues/5840)). The plugin now ships the shared checker, `lib/prerequisites.mjs` with its `lib/prerequisites.sh` and `lib/prerequisites.ps1` stubs, generated from the repository's canonical copy.

## [0.21.2] - 2026-10-03

### Changed

- The shared hook library's missing-prerequisite notice says to run `/harness-ops:prerequisites` if the `harness-ops` plugin is enabled, where it said installed: an installed but disabled plugin exposes no skills, and `harness-ops` now installs disabled ([#5934](https://github.com/melodic-software/claude-code-plugins/issues/5934)).

## [0.21.1] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.

## [0.21.0] - 2026-10-02

### Added

- **`/testing:fix-until-green` workflow** (`workflows/fix-until-green.js`). One runner runs the
  command and lists failures with the source files each points at or imports. The workflow
  groups them so no two groups share a file and runs one fixer per group in the same working
  tree, in waves of `maxConcurrent`. A verifier then checks the
  diff from the starting commit for test weakening and for changed files no fixer was allowed to
  edit, and the command runs again. It stops when the command passes, at `maxRounds`, after two
  rounds in a row with no fewer failures, when a fixer's root cause sits in a file that is out of
  scope or protected (an editable in-scope file joins that fixer's group next round instead), when
  the check flags weakening or an edit outside the allowed files, or when HEAD moves. It flags these
  and never reverts them. Paths that are absolute, contain `..`, sit under git internals, agent
  settings, hooks, CI, editor tasks or dependency trees, or name a dependency manifest, lockfile,
  build file, or secret-bearing file or directory in any common ecosystem, never reach a fixer
  (matched case-insensitively). A file a fixer asks for joins its group only when git tracks it.
  The checks, and every re-run, count untracked files and a moved HEAD, and fixers are told to run
  no git command that writes. After any round that dispatched a fixer, a green run gets a final
  verifier that re-runs the command and reviews the whole diff. Its `args` carry `command`
  (required; without it the run returns `{error: "missing-command"}` and dispatches nothing; a
  string that is itself valid JSON, such as `true`, stays the command), `scope` (path prefixes
  the fixers may edit; when every entry is rejected the run returns `{error: "bad-scope"}`),
  `maxRounds` (default 3, clamped to 1-5), `maxConcurrent` (default 2, clamped to 1-16), `roles`
  and `finalVerify` (default true). The result carries `green`, `rounds`, `remaining`, `changes`
  per round, `weakening`, `outsideEdits`, `base`, `nulls` and `stoppedBecause`. Fixers take the
  worker role's fan-out variant at `medium` effort, the runner the retrieval role's single
  variant at `low`, and the round check and final verifier the verifier role's single variant at
  `high`, from `/multi-agent:route` when the caller passes them, else from built-in fallbacks that
  run fixers on `opus`. It commits nothing.
- **`testing:green-runner`, `testing:green-fixer` and `testing:green-verifier` agents**, one per
  workflow stage, each holding only that stage's tools: Bash for the runner; Read, Edit and Bash
  for fixers; Read and Bash for the verifier. Fixers and the verifier preload `testing:test-value`.
  Each inherits the model and pins no effort; the workflow passes both from the role map.

### Changed

- **`diagnose` offers the workflow when several tests fail across files**
  (`context/fix-until-green.md`): it asks for a clean working tree, checks that the Workflow tool
  is available, resolves roles with `/multi-agent:route all code` when that skill resolves, and
  falls back to the investigate and loop phases on the main thread. It grants
  `Workflow(testing:fix-until-green)` only.

## [0.20.2] - 2026-10-02

### Changed

- The shared hook helper's posture comment no longer names a fixed member count.

## [0.20.1] - 2026-10-02

### Changed

- Cross-plugin routing says "if enabled" where it said "if installed": an installed but disabled plugin exposes no skills, and `playwright` and `mutation-testing` now install disabled. `cleanup` stops when `mutation-testing` is not enabled.

## [0.20.0] - 2026-10-02

### Added

- `test-value` names six more judgment-only shapes: a negative test that passes for an unrelated
  reason, a fixture that supplies the outcome, a mock that implements the asserted behavior, a name
  that promises more than the assertions check, a hand-copied inventory, and a test kept only to
  preserve a test-only export.
- `write`'s per-cycle checklist asks whether existing coverage already catches the regression, keeps
  one regression test per bug at its owning boundary, and rejects a test that needs a production
  seam no production caller uses.
- `cleanup` classifies a layer replay (a mocked re-proof of a contract a stronger kept test already
  proves) under row 5 and deletes it with both tests cited, takes user-named duplicates as a fourth
  input, and judges tests by their assertions using `test-value`'s judgment-only shapes.

### Changed

- `cleanup` reports a test that fails the same way on every baseline run as a possible product bug,
  never a quarantine, and re-scans each rewritten file before the mutation replay, stopping on a
  finding step 1 did not list. Its `## Next` points at `/code-tidying:audit-dead-code` for exports a
  deletion leaves with no caller.

### Removed

- Provenance notes in `test-value` (where its examples came from and where it departs from that
  source) and `write` (the upstream skill a rule came from). The rules stand on their own.

## [0.19.1] - 2026-10-02

### Fixed

- `test_judge_effort` points at the model config page for supported levels and says it has
  no effect on a model that page lists without effort levels. The judge calibration takes
  Haiku's sweep arms from that page, and `cleanup`'s model record states only what the skill
  relies on.

## [0.19.0] - 2026-10-02

### Changed

- `test_judge_model`, `test_judge_fallback_model` and `test_judge_effort` are pickers in `/config`
  (`options`), listing exactly the values `judge-lib.sh` accepts, per the plugin-option-naming
  convention (`docs/conventions/plugin-option-naming/`). A value outside the list, which the hook
  already ignored in favor of the default, is now rejected when set.

## [0.18.4] - 2026-10-02

### Changed

- **`write` no longer asks for a self-check before writing tests.** It states the interface it
  assumes in one line and proceeds.

## [0.18.3] - 2026-10-02

### Changed

- **The judge-calibration u16 case moves to `cases/u16/plugins/harness-ops/`, and the u31
  fixtures carry the `harness-ops:lane-telemetry` sentinel.** The `source` column keeps its
  commit-pinned `path@sha`, which resolves only under the path at that commit.

## [0.18.2] - 2026-10-02

### Fixed

- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action and keeps alternatives inside brackets with an unspaced `|`.

## [0.18.1] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.18.0] - 2026-10-01

### Added

- **`/testing:cleanup <folder>`.** Cleans up low-value tests in one folder: reads the scanner's
  findings, the branch's test-judge findings when present, and the tests the user names as flaky.
  A fresh-context classifier on `opus` picks quarantine, rewrite, delete, merge or keep per test.
  Rewrites are the default; each deletion or merge needs a positive no-contract statement and the
  user's yes. Named flaky tests are skipped with a dated `test-change: quarantined` reason. The
  mutation gate records the tests' kills before any edit and replays them after
  (`/mutation-testing:audit --record-mutants` and `--replay-mutants`); a lost kill blocks the
  batch and lists the candidate changes. Nothing is committed until the user approves the batch.
- `audit` and `test-value` name `/testing:cleanup` as a successor.

## [0.17.0] - 2026-10-01

### Added

- **audit:** `[--file <path>]` in the argument hint, forwarded to the script's `--file` mode, so
  another skill can ask through the Skill tool which adapter claims a file.
  `/mutation-testing:audit --exercised` uses it to recognize changed test files.

## [0.16.3] - 2026-10-01

### Changed

- **The test judge ignores `memory_dir` in `.claude/topic-docs.yaml`.** `judge-lib.sh` always writes the findings file under `<repo>/.work/reviews/<branch-slug>/`, so a consumer that set `memory_dir` there no longer gets findings in that root. Citations of the removed topic-docs convention and the `docs/specs` tree were dropped from the docs.
- **The judge calibration record moved beside its labels.** `calibration.md` now lives in `skills/audit/evals/judge-calibration/`, and `metrics.sh --check` reads its `holdout-only:` lines from there instead of `docs/specs/tautological-tests-judge/calibration.md`.

## [0.16.2] - 2026-10-01

### Fixed

- **calibration:** `sample.sh` marks a fixture executable when its first line is a shebang, so
  the shebang calibration fixtures stay runnable.

## [0.16.1] - 2026-10-01

### Changed

- Shared `hooks/hook-utils.sh` resynced from the repository library (comment wording only, no behavior change).

## [0.16.0] - 2026-10-01

### Changed

- **judge:** the task-end judge defaults to `sonnet` at `medium` effort, with `opus` as the fallback
  class, in `plugin.json` and in `judge-lib.sh`'s in-script defaults and invalid-value fallbacks.
  The calibration sweep chose them: `sonnet` `medium` is tied-best under both the consensus labels
  and GPT's labels (the tie-break alone picks `sonnet` `low`, which GPT's labels rate significantly
  worse than `opus` `high`), at about $0.001 more per row. The table is in `docs/specs/tautological-tests-judge/calibration.md`.

### Added

- **calibration:** the judge calibration set under `skills/audit/evals/judge-calibration/`: 78
  labeled cases, `raters.sh` (blind opus and Codex raters), `metrics.sh` (kappa, confusion matrix,
  Wilson intervals, `--check`, a seven-arm `--sweep`, `--table` and `--rerun` for run-to-run
  variance), and the sweep's verdict, cost and wall-time files under `sweep/`.

### Fixed

- **calibration:** `metrics.sh` printed `flag-n` for a stratum with no reference FLAG as a value
  like `5.22809e-310` instead of `0`.
- **calibration:** `raters.sh` dropped an answer whose reason quoted code containing braces; it now
  parses the outermost `{...}` object first, then falls back to the flat scan.
- **calibration:** `raters.sh` runs Codex with `--ignore-user-config`, web search off and connected
  apps off, so the user's MCP servers, plugins and `AGENTS.md` never reach the rater.

## [0.15.1] - 2026-10-01

### Changed

- **`prerequisites.json` declares `node`.** The hooks run it, so `/claude-ops:prerequisites` now reports a missing `node` and names `/testing:check`, which probes it.

## [0.15.0] - 2026-10-01

### Changed

- **config:** the team layer is read from the one `yaml config` fenced block in
  `docs/conventions/testing.md` (a second block is an error), with `.claude/testing.yaml` as the fallback when the docs file has
  no block. When both exist the docs block wins and `resolve-config.sh` prints one warning naming
  both paths. Config errors in the block report the `.md` path and line. The user-global and
  `.local` layers are unchanged.
- **hooks:** `judge-lib.sh` cache keys include `docs/conventions/testing.md`, so a changed block
  re-derives; `test-scan` and `test-weaken` messages name whichever source failed.
- **setup:** `apply` writes the docs block, or `.claude/testing.yaml` when that file is the one in
  use, and refuses to touch a docs block that does not parse. It rejects a flag value that holds a
  line break and refuses a symlinked docs file before reading it.
- **docs:** the README carries the migration steps and the measured `test-scan` timings;
  `scripts/time-config.sh` reproduces them.

## [0.14.0] - 2026-10-01

### Added

- **`/testing:check` reads whether `jq` resolves for the testing hooks.** The skill is model-invocable, read-only and never installs. A new `prerequisites.json` declares `jq` and points at it, so `/claude-ops:prerequisites` and the per-plugin check read the same list.

## [0.13.1] - 2026-10-01

### Changed

- **Shared library sync: `hook-utils.sh` `jq` notices name `/claude-ops:prerequisites` when the claude-ops plugin is installed.** No behavior or exit-code change.

## [0.13.0] - 2026-09-30

### Added

- **audit:** `cant-fail-scan.sh --blocks` also prints `block <file>:<start>-<end> <ordinal> <name>`
  for each examined test block in `--lines` scope, in every adapter family; a bash harness is one
  whole-file block. The ordinal counts same-named blocks through the whole file, so a block's
  identity is its name and ordinal, never its line range.
- **hooks:** `test-scan` records each scanned write in
  `sessions/<pkey>/<session_id>/<tool_use_id>.json` under the plugin data directory: the file, its
  repository, the agent, whether the write created the file, the blocks it created or changed
  (`null` when unknown, meaning the whole file) and the `cant-fail-ok:` count. `<pkey>` hashes the
  project directory and the transcript directory, so a `/clear` or fork successor finds its
  predecessor's writes. Session state and the task-end judge's state directories are pruned after
  7 days. The record also carries `lines`, the lines the write changed (`null` when unknown). A
  test file a Bash call changed gets the same record, one per file as `<tool_use_id>-<n>`, when
  Claude Code records the call's `bashEditDiff`.
- **hooks:** an opt-in task-end test judge (`test_judge_enabled`, off by default, needs
  `test_guards_enabled`). A separate headless `claude -p` run asks one question of each test block
  the session created or changed: where did its expected value come from? It answers FLAG, PASS or
  UNKNOWN with quoted evidence and, for FLAG, a proposed diff it never applies. `test-judge-bg.sh`
  (PostToolUse, async) judges soon after a write and keeps the verdicts in a ledger;
  `test-judge.sh` (Stop) waits only on runs still in flight, judges the rest (10 per Stop, the
  remainder at the next task end), writes a review-findings file and, in an attended session,
  asks Claude once to show the verdicts; `test-judge-start.sh` (SessionStart) names verdicts an
  earlier session never showed. The judge's model class differs from every model that wrote the
  tests: `test_judge_model` (default `opus`), `test_judge_fallback_model` (`sonnet`),
  `test_judge_effort` (`medium`), and `test_judge_session_runs` (unset: no limit; each run is reserved
  before it waits for a judge slot, so jobs that start together cannot pass it). Each judge run
  is bounded at 150 s by the same process-group watchdog that bounds the scanner (the plan's
  "timeout 150" is that bound, not the coreutils binary, which stock macOS lacks and Git Bash may
  resolve to Windows' `timeout.exe`); the whole group gets TERM, then KILL, and a run cut at its
  bound gives no verdict. Every wait in the Stop hook (a judge slot, a run, a background job)
  ends at its 180 s bound, and tests not judged in time go to a background job, which waits for
  the Stop's own unfinished run to let go of them, and are shown at the next task end. On Windows
  (Git Bash with the native `jq.exe`) the judge hooks read payload fields NUL-separated rather than
  through `@tsv`, which doubled every backslash in a Windows `transcript_path`, `cwd` or file path
  and so gave the Stop hook a different project key from `test-scan`'s; and every `jq` call runs
  with `-b` under Git Bash and Cygwin, which `jq.exe` (1.6 and later) needs to write LF rather than
  CRLF, chosen over stripping CR from each field because it leaves every byte as written, a CR a
  diff or a quote really carries included, and costs no extra process. A Stop over files whose
  verdicts are ready no longer re-runs the scanner: the in-doubt blocks are cached by the file's
  content, the records and the config layers, and the hook reads each record and verdict with one
  `jq`; a ready Stop over one file went from 187 processes to 31 on Linux, over five files from
  671 to 79. A quote in a verdict is valid when it appears, whitespace trimmed, in the test file or
  in another file of the repository (`git grep --untracked`), because the implementation line an
  expected value restates is a FLAG's best evidence; one found nowhere still makes the verdict
  UNKNOWN. The judge prompt now says so; it changed before any Phase 4 calibration label was read,
  so the prompt freeze is not broken. Hardened after a security review: the findings directory
  and the memory root must resolve, symbolic links followed, inside the checkout before and after
  they are created; the `.gitignore` is written only where no name exists, so an existing link,
  FIFO or other non-regular name is refused (noclobber alone would open a non-regular name); the
  findings file goes to a temporary file in the checked directory and takes a free name with
  `mv -n` after a second check, so a link in the repository cannot carry the write elsewhere (it
  falls back to the plugin data directory; a local process racing those steps is an accepted
  residual); the frontmatter `branch:` is quoted when its plain YAML form would misparse, with the
  predicate `testing:audit` uses; `memory_dir` is used only
  when it matches `[A-Za-z0-9._/-]` with no `..`; judge text in the findings file is capped, kept
  on one line and fenced past its own backticks, and a verdict that failed validation shows only
  its reason; a test file in no repository is not judged ("no repository"); and every numeric
  setting is checked as a number before any arithmetic. The README and
  `/testing:setup` describe the options, what is tunable and what is fixed, and what the judge
  reaches.

## [0.12.1] - 2026-09-30

### Changed

- Test-only: the suites remove their temporary directories on exit. No behavior change.

## [0.12.0] - 2026-09-30

### Added

- **`test-scan` covers test files a Bash call changed.** A PostToolUse `Bash` hook reads `bashEditDiff`
  and runs `test-scan` on each changed test file (up to four), behind the same opt-in. Claude Code
  records the field only with `bashEditDiffEnabled: true` in user, `--settings` or managed settings,
  or `CLAUDE_CODE_BASH_EDIT_DIFF=1`; without one of these it was absent in `default`, `acceptEdits`,
  `auto` and `bypassPermissions` mode. The `Bash` row has no `if`, so its node launcher starts on
  every Bash call, whatever `test_guards_enabled` says; the README states the cost
  ([#5608](https://github.com/melodic-software/claude-code-plugins/issues/5608)).

## [0.11.9] - 2026-09-30

### Changed

- **README declares the Node.js requirement.** A Requirements section states that every hook row launches through `node`, and that a missing `node` is a hook launch error. `/testing:setup` checks it.

## [0.11.8] - 2026-09-30

### Changed

- **Shared library sync: `hook-utils.sh` now adds cygpath spellings of the temp root on Windows shells.** No behavior change off Windows.

## [0.11.7] - 2026-09-30

### Fixed

- **`audit` eval names the repair routes.** The expectation names `/testing:write` and the review fix pass as where repair goes ([#5394](https://github.com/melodic-software/claude-code-plugins/issues/5394)).

## [0.11.6] - 2026-09-30

### Changed

- **The `run` Boundary bullet in `run-e2e` no longer asserts that the skill ships with Claude
  Code.** It keeps the provenance class, what the skill does and how it is invoked, in the
  native-references template form.

## [0.11.5] - 2026-09-30

### Fixed

- **setup:** `check`'s instruction line names the one file Claude Code loads at the repository
  root (`CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, or the user `CLAUDE.md`
  under `${CLAUDE_CONFIG_DIR:-~/.claude}` when the repository has none) instead of offering
  "CLAUDE.md or AGENTS.md": `AGENTS.md` does not load beside a `CLAUDE.md`, `.claude/CLAUDE.md` or
  `CLAUDE.local.md`, and `CLAUDE.local.md` always loads, so it is named with a note that a
  `CLAUDE.md` would share the line with the team.

## [0.11.4] - 2026-09-30

### Changed

- **Shared library sync: `hook-utils.sh` now carries `hook::file_is_gitignored` and `hook::gitignored_out_of_scope`.** No behavior change.

## [0.11.3] - 2026-09-29

### Fixed

- **audit:** `rule-zero-assertion` follows same-file helpers to any depth: a helper that calls an
  asserting helper asserts too, so a test awaiting `waitForAll()`, which returns `pollUntil(...)`,
  which throws, is no longer a finding. A C# overload that calls another overload of its name, by argument count, counts when that
  overload asserts; plain recursion does not. A bats test whose last line is a standalone `! cmd` (no `||`, `&&` or `;`) asserts through that line. A
  base-versus-head re-scan of this repository, `medley` and `ci-runner` under gawk and mawk
  cleared exactly medley's two known false positives and moved nothing else.

## [0.11.2] - 2026-09-29

### Changed

- **audit:** fewer `rule-zero-assertion` false positives, from a precision run over this repository,
  `medley` and `ci-runner` (`docs/specs/tautological-tests/precision-run.md`). A test that calls a
  function defined in the same file, bare or on `self`, `this` or `cls`, whose own body asserts,
  throws, raises or rejects has an assertion; the helper's own calls are not followed. A call on
  `self` or `this`, and a bare C# call, resolves to the test's own class when that class defines
  the name (every C# overload must assert), so another class's asserting helper of the same name
  does not count. The C# adapters count `}.RunAsync(` as an assertion only in a file that imports
  `Microsoft.CodeAnalysis.Testing` or aliases one of its types, and `bash-harness` counts
  `exit "$((FAIL > 0))"`.
- **audit:** `rule-conditional-assertion` treats a loop over `.map` of a nonempty array literal,
  or of a name the test bound to one, awaited through `Promise.all` or not, as a loop over a
  literal table.
- **audit:** `rule-recomputed-expectation` keeps firing on a deliberate determinism check,
  `f(x) == f(x)`; its remedy says to mark one `cant-fail-ok: determinism contract`.

### Fixed

- **audit:** a `cant-fail-ok:` comment at the end of a Python `assert` line no longer drops the
  recomputed-expectation finding without counting it as exempt.

## [0.11.1] - 2026-09-29

### Added

- **test-value:** new model-invoked skill stating where each expected value must come from, when
  call-count checks (unmanaged, state-changing boundaries) and direct database reads are
  legitimate, the EF Core `DbContext` carve-out, refactoring inside the TDD loop, and the can't-fail
  and change-detector taxonomy keyed to `testing:audit` rule ids. `write`, `plan` and `diagnose`
  point to it and each gains a `## Next` section.

### Changed

- **write:** the per-cycle checklist points to `testing:test-value` instead of listing oracle
  sources, and keeps the round-trip caution. "Verify through the interface" now calls a direct
  read of a managed database after the act step state verification, and flags only a read of an
  internal table when a public read path exists.
- **audit, hooks:** `rule-recomputed-derived` reports at SUGGESTION, not IMPORTANT: a derived
  expectation can fail, but passes when the test and the code share a mistake. `test-scan` leads
  such a finding with "check little", not "cannot fail". It stays report-only.
- **README:** documents the two `userConfig` options and the hooks they gate, and lists seven skills.

## [0.11.0] - 2026-09-29

### Added

- **hooks:** opt-in `test-scan` PostToolUse hook (`test_guards_enabled`, default `false`). After
  Claude writes or edits a test file it runs the can't-fail scanner on that file and feeds the
  findings back through `additionalContext`. A new file reports every test block; an edit reports
  only blocks that overlap the lines it wrote. A recomputed expectation asks Claude where the
  expected value comes from. The first write per file per session and agent adds a pointer to the
  test-value guidance. The hook starts only for paths its `if` rows match, generated from the
  adapters' `files:` globs by `scripts/gen-hook-filters.sh`; gitignored files are left alone, and
  a scanner error or timeout lets the edit through and logs a line.
- **audit:** `cant-fail-scan.sh --file <path> --lines <list>` reports only findings whose test
  block overlaps the listed lines.
- **audit:** adapters for Bash harnesses (`*.test.sh`), bats, Pester, Go `testing`, `node:test`,
  Playwright, unittest, NUnit and MSTest, with lexers for Bash, PowerShell and Go. A harness with
  no per-case marker is judged as one test. Recomputed expectations are also caught in shell
  command form (`assert_eq "$(f)" "$(f)"`) and pipeline form (`f | Should -Be (f)`). The
  `bash-harness` and `bats` findings are advisory: they never fail `--check` without `--strict`.
  The test-scan hook covers the new globs.
- **audit:** a fixture corpus with a bad and a good file per adapter and rule, and
  `check-corpus-grid.sh`, which fails when a `GRID.md` pair cell lacks either file.
- **audit:** three report-only rules. They print and count, and never gate `--check`, `--strict`
  included. `rule-inert-assertion` finds assertions that never evaluate: an async matcher nothing
  awaits, an `expect` with no matcher, a bare `.Should()`, a Python tuple assert or a Mock
  `called_once_with`, a bats `run` nothing checks or a `!` that is not the last line, and the like
  in every adapter. `rule-constant-restatement` finds a constant, or a literal the test bound
  itself, compared to a literal with no call before the assertion; it does not run in C#, Go or
  Pester, whose constants are not uppercase. `rule-source-text-read` finds a test reading a
  git-tracked, non-test source file by a static path and searching its text; a read through a
  glob or a walk, of a `__testfixtures__` path, or that the test parses or executes is never
  flagged. Adapters gain `assertion.async` and `assertion.inert` fields. The inert-assertion
  remedy names the repair for the file's language.
- **audit:** four more report-only rules. `rule-conditional-assertion` finds a test whose every
  assertion sits inside an `if`, a `catch` or a loop over a result it computed, with no `else` and
  no length check. `rule-recomputed-derived` finds an expected value rebuilt from the call's own
  arguments with an operator or an aggregate (`items.reduce(...)`, `sum(xs)`, `a + b`); a file
  holding a property-test marker and the Playwright adapter are exempt. `rule-snapshot-only`
  finds a test whose only oracle is a snapshot ("snapshot is the only oracle: review it as code"),
  never an image comparison such as `toHaveScreenshot`. `rule-weak-oracle` finds a test whose only
  oracle is a weak matcher (`toBeDefined`, `is not None`, `Assert.NotNull`) or an over-broad
  exception check (`toThrow()`, `pytest.raises(Exception)`). Adapters gain `assertion.weak`,
  `assertion.count`, `assertion.fail`, `property_markers` and `rules_off`, and fill the existing
  `snapshot` field. The audit skill lists every rule with its tier and gating.
- **audit:** `GRID.md` maps each of Matt Pocock's low-value test examples to a rule or to the
  Release 2 judge, and the corpus holds the twelve planted taxonomy tests, one per file.
- **hooks:** `test-scan` asks where the expected value comes from for a constant restatement or a
  derived expectation too, and leads with "change detectors" or "weak or snapshot-only oracles"
  when only findings of tests that can fail are present. The 7-day marker prune removes the
  directories the earlier `mkdir` markers left, as well as marker files.
- **audit, hooks:** `.claude/testing.yaml`, resolved across `~/.claude/testing.yaml`, the team file
  and `.claude/testing.local.yaml` by `scripts/resolve-config.sh` (lists concatenate, a later
  scalar overrides). `adapters.disable` and `adapters.enable` (an allowlist) pick adapters,
  `paths.exclude` and `paths.include` take repo-root globs (`**` crosses `/`, `*` does not;
  Windows paths are normalized first), `extend.<adapter>.<field>` appends to an adapter's list,
  `adapter_dirs` loads consumer adapters, and `rules.<rule>: off | warn | error` drops a rule's
  findings, keeps them out of the `--check` gate, or gates them. The scanner applies all of it, so
  an excluded file or a disabled adapter also silences the `test-scan` hook, rules note included.
  A file whose adapter is off is not scanned at all, never handed to another adapter that matches
  its name. The team and local layers are read from the scanned file's own repository, so a
  sibling worktree uses its own config; a UTF-8 byte-order mark and a leading `~/` in
  `adapter_dirs` are accepted. An unknown adapter id is refused at its file and line, and the
  `test-scan` hook names an invalid config back to Claude instead of going quiet. The audit names
  every consumer adapter or `extend` glob no shipped hook row matches. A repository with no layer
  file scans exactly as before.
- **setup:** `/testing:setup check | apply`. `check` prints the resolved config, which test-lint
  rules the lint config turns on per language (a missing `valid-expect`, Playwright await or
  focused-test rule, `xUnit2021`, `NUnit2009`, or ruff `PLR0124`, `PT011` or `F631` is a finding),
  an optional instruction line to paste, and a `.claude/settings.json` entry for each glob the
  shipped hook skips. `apply` writes only `.claude/testing.yaml`. The `test-scan` hook takes
  `--enabled` for that settings entry, since a settings hook receives no plugin option variables.
  The entry runs the highest installed version of the plugin from the marketplace `check` ran
  from, says so on stderr when no installed copy takes `--enabled`, and shares the plugin hook's
  markers, so a file both cover is reported once.
- **hooks:** opt-in `test-weaken` PreToolUse hook, under the same `test_guards_enabled` option and
  the same generated `if` rows as `test-scan`. Before Claude writes or edits a test file it
  compares the old text with the new and names removed test blocks, removed assertions, added skip
  markers (a suite skip such as `describe.skip` included) and changed expected values, then asks Claude for its reason. It returns no permission
  decision, so the user's own prompt still applies. With `rules: {test-weaken-block: error}` in
  `.claude/testing.yaml`, an added skip or a removed test block is denied until the edit carries a
  `test-change: <reason>` comment; removed assertions and changed expected values never deny. A
  scanner error or timeout lets the edit through and logs a line.
- **audit:** `cant-fail-scan.sh --file <path> --inventory <text>` counts test starts, assertion
  tokens and skip markers per line of a text, and lists its equalities with a literal side, using
  the adapter and config of `<path>`.

### Changed

- **audit:** when no adapter's `detect` matches a file, the claimant with no `detect` list wins, so
  `cs-xunit` stays the C# default.
- **audit:** `--findings` rows carry a per-rule tier: `SUGGESTION` for the two change-detector rules.
- **audit:** the Jest-family adapters count `expect.poll(` and `expect.soft(` as assertions, and no
  longer count a `checkout(` call as one.
- **audit:** `check-corpus-grid.sh` reads only the `GRID.md` table headed `Adapter`.
- **hooks:** `test-scan` claims its once-per-call and once-per-file markers as files created with
  `noclobber` (`O_EXCL`) instead of `mkdir`, which is not atomic under uutils coreutils.

### Security

- **setup:** `apply` refuses a `.claude` directory or `.claude/testing.yaml` that is a symlink, so a
  repository cannot point it at `CLAUDE.md` and have it overwritten. It writes a temporary file in
  `.claude/` and renames it into place, and restores a refused answer the same way.
- **setup:** the `check` hook entry names the marketplace only when it is a plain name
  (`[A-Za-z0-9_.-]`); any other name prints the `<marketplace>` placeholder instead of splicing it
  into the command.
- **config:** `resolve-config.sh` exits 2 on a team or overlay layer that is a symlink or sits under
  a symlinked `.claude`, so a repository cannot have the loader parse a file outside it.
- **hooks:** the `test-scan` and `test-weaken` scanner timeout ends the scanner's whole process
  group, not just its shell, so no `awk` outlives it.
- **hooks:** without `CLAUDE_PLUGIN_DATA`, `test-weaken` keeps its log and markers where `test-scan`
  does (the plugin data directory, else `XDG_STATE_HOME`), never in a shared `TMPDIR` directory.

## [0.10.0] - 2026-09-29

### Changed

- **run-e2e:** the Native step carries the full wrap grammar: an identity check that also accepts a
  project skill named `run`, a mutation fingerprint, skip and refuse states that name the axis line
  and the enable path, a result block, and an unattended run never invokes `run`.
- **run-e2e:** one launch path per verification. An orchestrator-governed start skips the Native step.
- **run-e2e:** the Boundary section and `context/bundled-run.md` match the compose decision.
- **diagnose, plan, write, run-e2e:** Arguments are stated once.
- **run-e2e:** the evals replace a duplicate case with one that covers the Native step.
- **diagnose, plan, write:** the evals carry a literal em dash where a `—` escape stood; the parsed JSON is unchanged.

## [0.9.7] - 2026-09-28

### Changed

- **audit:** the can't-fail scanner reads its framework vocabulary from adapter files
  (`skills/audit/adapters/`: `js-jest`, `js-vitest`, `py-pytest`, `cs-xunit`) instead of
  regex literals in `cant-fail-scan.awk`. `scripts/adapter-load.awk` loads a restricted YAML
  subset and refuses a malformed adapter or a non-portable regex with exit 2. Findings,
  coverage and exit codes are unchanged; `scripts/parity-check.sh` proves that against the
  previous scanner under gawk and mawk.

### Added

- **audit:** `cant-fail-scan.sh --file <path>` scans exactly one test file, with the same
  modes and exit codes, and names the adapter that claimed it.

## [0.9.6] - 2026-09-28

### Changed

- **Argument hints** on `diagnose`, `plan`, `run-e2e`, `write` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.9.5] - 2026-09-28

### Changed

- **The native-surface presence gate reads "resolves in this session"** ([#4112](https://github.com/melodic-software/claude-code-plugins/issues/4112)). The `run-e2e` routing line named a native surface behind "resolves in your session", which addresses the reader. The gate now names the session instead, matching the canonical token that claude-ops' native-overlap self-check matches. Routing is unchanged.

## [0.9.4] - 2026-09-28

### Added

- **Eval floor:** `plan, diagnose, run-e2e, write` now ships three or more eval cases each ([#4070](https://github.com/melodic-software/claude-code-plugins/issues/4070)). The skill-authoring checklist's three-case advisory stays advisory; this is coverage, not a new gate.

## [0.9.3] - 2026-09-28

### Changed

- **run-e2e:** compose the bundled `run` skill via a Native step section and description routing phrase ([#4052](https://github.com/melodic-software/claude-code-plugins/issues/4052)). Store `integration` / parity tooling waits on #4049.

## [0.9.2] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.9.1]

### Changed

- The wizard template shares one prompt line and one gh set helper between its ask and set functions, the testing cant-fail scanner folds its readability guards, config dedupe, and C# body-start detection into helpers, its suite gains run and count helpers, and the songwriting datamuse comments are trimmed, with byte-identical output.

## [0.9.0]

### Added

- **`audit`**: two Playwright runner-config rules beside the three test-body rules.
  `testing/audit/rule-flaky-passes-suite` fires when retries are configured (a literal above zero or
  an expression) while `failOnFlakyTests` is absent or literal `false`, the shape where a test that
  fails and passes on a retry leaves the run green. `testing/audit/rule-only-not-forbidden` fires
  when `forbidOnly` is absent or literal `false`, the shape where a committed `test.only` shrinks
  the suite to one passing test. Both are IMPORTANT with `Confidence` omitted, advisory in `--check`
  unless `--strict`, which gates them together with `mock-only-oracle`. A new engine,
  `runner-config-scan.awk`, judges one config per invocation beside the shared masker
  `mask-js.awk`; the driver walks the six `playwright.config.*` filenames in the runner's own probe
  order, reads the first per directory and counts the rest as shadowed. Declines carry their
  evidence (`spread-undecidable`, `variadic-undecidable`, `key-below-top-level`,
  `retries-not-configured`, `key-set`) and a config whose object literal cannot be anchored is
  counted as enumerated and not examined rather than judged. `cant-fail-ok:` anywhere in a config
  exempts it, file-scoped and counted. The coverage block and the `## Surfaces` line gain the config
  denominator; the exit-2 rule for 0 examined test files is unchanged, so a config-only tree reports
  its findings without gating or persisting them. Crosswalk rows for both rules land in the
  detector-findings convention 3.1.0.

## [0.8.1]

### Changed

- **Every markdown surface in the plugin passes `/ai-slop:audit`.** Em dashes in the plugin's own
  prose (this changelog, the write and organize contexts, the diagnose investigate and loop
  contexts, and the run-e2e e2e, e2e-config and non-ui contexts) are rewritten as a comma, a
  period, a colon where a definition or list follows, or a restructured sentence. No test-writing
  rule, browser-fit verdict, MCP revision pin, or dated verification stamp changed.
- **Four headings took the colon form**, in `e2e-config.md` and `organize.md`; no file in the
  repository links any of the old anchors.
- **Em dashes inside the `csharp` illustrative fences stay.** They are code comments, which the
  detector exempts and which this campaign treats as code rather than prose.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`,** so the gate defends
  it from here on.
- **Changelog, in-place wording corrections to released entries:** the same rewrite was applied
  inside
  `[0.7.10]`, `[0.7.5]`, `[0.7.4]`, `[0.7.2]`, `[0.7.1]`, `[0.7.0]`, `[0.6.2]`, `[0.6.1]`,
  `[0.6.0]`, `[0.5.1]`, `[0.5.0]`, `[0.4.0]`, `[0.3.4]`, `[0.3.3]`, `[0.3.2]`, `[0.3.1]`,
  `[0.3.0]`, `[0.2.3]`, `[0.2.2]`, `[0.2.0]`, and `[0.1.0]`. Wording only; every entry's facts are
  unchanged.

## [0.8.0]

### Added

- **`run-e2e`**: a `## Boundary, the bundled run skill` section: the bundled `run` skill (beside
  `/verify` and `/run-skill-generator`) launches and drives the app for a look, this skill starts
  it through the project's orchestrator and captures evidence to the contract, with a non-UI lane
  that has no native counterpart. Routing, a mutation gate (one orchestrator per verification),
  and an availability rule that never assumes the bundled skill resolves. Four-part records in
  `context/bundled-run.md`.

## [0.7.18]

### Added

- **`audit`**: a `## Next` section naming the skill that normally runs after this one, in
  the mention-only shape the skill-body rule describes.

## [0.7.17]

### Changed

- **diagnose, plan, run-e2e, write:** the inert `shell: bash` frontmatter key is dropped, since no injection remains in the file (prompt-audit follow-up F12).
- diagnose, write, and run-e2e: the .NET framework-trap claims are corrected to the current runner behavior and dated, the Playwright CLI version floor names the live package, and the gather-block claim points at the worktree skill's record (prompt-audit follow-up F6)

## [0.7.16]

### Changed

- **`audit`:** the description's eight quoted trigger phrases became three intent clauses; the
  scope note dropped "this cycle", the `recomputed-expectation` gotcha dropped "not yet", and the
  platform-skip gotcha now states the detector boundary without the history of a rule that never
  shipped.
- **`diagnose`:** the fix step no longer invites Boy Scout cleanup inside a bug fix, the regression
  step states the side-effect reason once instead of three times, and both context files dropped
  their marketplace-skill sections naming plugins that exist in no installed marketplace.
- **`plan`:** dropped the marketplace-skill section naming plugins that exist in no installed
  marketplace.
- **`run-e2e`:** the description's six quoted trigger phrases became three intent clauses; a missing
  Playwright CLI now routes to the user instead of a global install; GIF recording follows the
  resolved `recording` key rather than firing on every multi-step flow; the `/verify` handoff states
  the current rule without the release-by-release history; caps emphasis on the e2e route, semantic
  locators, and the prerequisite check became plain instructions; the duplicated after-testing
  handoff moved into the SKILL.md handoff, which now carries the structured-log step; `headless` no
  longer describes itself as preserving current behavior.
- **`write`:** the description's five quoted trigger phrases became three intent clauses; the
  vertical-slice rule leads with the positive form; the pre-coding interface check confirms with the
  user only when the session is interactive and the change is material; the refactor step keeps
  cleanup inside the slice and notes the rest as follow-ups; two config keys no schema defines became
  plain references to the project's own conventions; a hollow "Current state" section and both
  marketplace-skill sections are gone.

Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.7.15]

### Fixed

- **`diagnose`, `plan`, `run-e2e`, `write`:** the git pre-compute lines moved out of `##
  Pre-computed context` into a "Repository context. Gather first" body section of individual Bash
  calls, one command per call, each `head` bound kept inside its command and a failure read as an
  unknown value. The harness composes a skill's whole pre-compute block into one shell invocation,
  and a worktree-isolated session refuses a git-bearing compound command, which blocked these skills
  from loading inside a worktree. Same shape as the worktree skill's fix in #1619. Non-git
  pre-compute lines stay where they were.

## [0.7.14]

### Changed

- **`audit/scripts/cant-fail-scan.sh`: one write-only tally removed.** `x_cf2`
  counted `cant-fail-ok:` exemptions of the `recomputed-expectation` rule and
  nothing ever read it. Its two siblings do have readers: `x_cf1` and `x_cf3` feed
  `fired_blocks` and the two `declined_*` figures the coverage line prints, and
  the line itself says in words that `recomputed-expectation` is not tallied,
  being line-scoped. The aggregate `exempted` counter had already counted the
  record. The `recomputed-expectation)` case arm stays, now empty with a comment
  giving that reason, so an exemption for the rule is still recognized rather than
  falling through to the "unknown exempt rule" drift report.
- **The same file is now shfmt canonical.** Its `case` blocks indented their
  labels one level in, which shfmt's default form does not. Measured rather than
  eyeballed: `shfmt -d` (v3.12.0, taking `indent_size = 2` from `.editorconfig`)
  reports no change against the new file and 630 diff lines against the old one,
  and `git diff -w` between the two revisions shows only the `x_cf2` removal and
  its replacement comment. No output string, exit code or public surface moved.

## [0.7.13]

### Changed

- **`audit/scripts/cant-fail-scan.awk`: one comment corrected.** It described a
  detector as covering a variant the rule set does not carry. Comment only: the
  non-comment lines are identical, the program parses under both `awk` and
  `mawk`, no GNU extension was introduced, and its own suite passes 92 checks.

### Known issues

- **`cant-fail-scan.awk` selects 5 suites and 1 exercises it.** The other four are
  a basename collision: another plugin's script names this file, and three
  unrelated plugins own a file sharing its basename. The selector's own header
  states that a basename match counts even when it lands in a comment, so this
  shape is by design rather than a defect, but a selection count is not a coverage
  count.

## [0.7.12]

### Changed

- **Dynamic-context probe fallback made reachable.** The working-tree-status injection piped its
  probe into `head` before `||`, so the fallback could never run and a failed probe rendered an
  empty string under a label that reads as a clean tree. The fallback now sits in a brace group with
  the probe and the cap applies outside it. Whole-repo extract-ssot sweep.

- **`audit`: the findings-file producer preamble regains three dropped clauses.** This skill states
  the producer contract as a numbered `apply` step rather than as a `persist-findings.md` preamble,
  and that compression had dropped the shape's authority, the self-ignore guard, and the whole
  "where the contract and this file disagree, the contract wins" rule. The step keeps its own form
  and carries all three again. The four `persist-findings.md` surfaces this sweep touched are
  byte-identical apart from their run-name slot; this one is deliberately not, and
  `provenance:audit`'s later preamble is a sixth surface outside that set. Whole-repo extract-ssot
  sweep.

## [0.7.11]

### Changed

- **Authoring-doctrine pass over `README.md`.** Fixed sentences that parsed two ways. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.7.10]

### Changed

- **`run-e2e`'s outcome handoff carries its presence gate in the file that executes it.** `SKILL.md`
  gated the `/verification:confirm outcome` step on the `verification` plugin being installed and gave
  a fallback; `context/e2e.md`, which `SKILL.md` names as where the workflow steps live, restated the
  same step with neither half. The executed copy now matches the owner. Coupling pass, apply lane.

## [0.7.9]

### Changed

- **`run-e2e` MCP handshake shapes point at the spec instead of copying it.** The `initialize` request/response JSON blocks are replaced by a pointer naming the pinned `2025-06-18` revision and <https://modelcontextprotocol.io/specification/latest>, noting revisions after `2025-11-25` replace the handshake with per-request metadata (verified 2026-08-26), so the smoke test is scoped to legacy/dual-era servers.
- **Duplicated "27K vs 114K" token figures removed** from the SKILL body and `context/e2e.md` in step with the playwright plugin dropping the unsourced origin figure; the comparison is now qualitative. From the repo-wide derivability/point-dont-copy audit (PR #3387).

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
  file went unmatched, with no error, and nothing distinguishing it from "no findings". That is
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
  present", a truncated prefix of a structured value, so it passed for the emitter's real
  `2026-08-23T04:37:40Z` and equally for `2026-08-21T13-36-00Z`, a hyphenated time that is
  ISO-8601 in neither the extended nor the basic profile. That is the same assertion shape
  that pinned `ai-slop`'s emitter bug rather than catching it (#3097), sitting inside the
  skill whose whole purpose is finding tests that cannot fail. The assertion now anchors the
  full extended form with an explicit `Z`
  (`^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`), and was confirmed
  discriminating: it FAILS against both malformed shapes above and PASSES against
  `cant-fail-scan.sh --findings` output. Test-only. The emitter already stamped the correct
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
  impracticality triggers 0.7.0 added are the upstream cursor/plugins `tdd` cost branch. The
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
  next-step arrows. Wording only. Presence gates, fallbacks, and step order unchanged.

## [0.7.0]

### Added

- **`write`: a test worth having is not always worth *this* test.** Absorbed from an upstream
  cursor/plugins skill (`docs/upstream/cursor-pstack.md`, the `tdd` section) into the existing
  "When NOT to write tests" section.

  That list already covered code that needs no test: pure contracts, constants, one-liner
  delegation, config wiring. It said nothing about the other axis: code that genuinely needs
  covering, where the only available test would need broad harness setup, brittle mocks, slow
  end-to-end infrastructure, production-only state, a reproduction nobody can state precisely, or
  large unrelated fixture churn. Prefer no new test to a bad one there. A test that mostly
  exercises its own mocks, encodes today's implementation, or would be deleted the moment it has
  proved its point costs more to maintain than the confidence it buys.

  **Declining is not skipping.** The addition requires naming which trigger made the test
  impractical and then naming the closest executable check used instead: a targeted script, a
  reproduction command, a snapshot comparison, a log assertion, a focused integration check. That
  matches doctrine this repo already enforces mechanically in CI, where a silent skip is a defect.

  Landed here rather than in `debugging:debug`, which the plan originally proposed: an adversarial
  audit pointed out that this decline list is the incumbent for the concern and a second one in
  `debug` would split it. The two lists are different axes, verified by reading both, so this is an
  addition rather than a restatement.

## [0.6.2]

### Fixed

- **The README claimed four skills and documented four, in a plugin that has five.** `/testing:audit`
  landed in 0.6.0 and reached the plugin manifest's description but never the README, so the front
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
  unmasked, chosen because misreading division as a regex would mask real code, with the known
  cost that an unmasked regex containing a brace can close the test block early and false-positive
  `rule-zero-assertion`); and the platform-skip blindness boundary, where a platform-skipped assertion is
  unverified on the platform that skips it, the same defect family this detector hunts approached
  from the environment side and out of static reach, making the dropped skip rule's uncovered axis
  platform as well as ecosystem.

## [0.6.0]

### Added

- **New `/testing:audit` skill: the can't-fail test audit (#2684).** A deterministic script
  detector (`cant-fail-scan.sh` driving `cant-fail-scan.awk`) for tests that cannot fail, with
  three rules v1, each carrying a qualified rule id and a fixed threshold:
  `testing/audit/rule-zero-assertion` (a runnable test body with 0 assertion tokens),
  `testing/audit/rule-recomputed-expectation` (an equality assertion whose actual and expected
  sides are the identical expression, the decidable core of the recomputed-expected-value class),
  and `testing/audit/rule-mock-only-oracle` (every assertion in a mock-constructing test is a
  mock-interaction assertion; advisory by default because deliberate interaction-style tests are
  the known benign case, gating only under `--strict`). Ecosystems v1: JS/TS, Python, C#; bash
  `*.test.sh` is deliberately excluded. The marketplace repo's discriminating-skip gate is the
  incumbent for the skip-vacating shape there. Detection bias errs toward not firing (generous
  assertion tokens, string/comment masking, skipped tests unjudged), guarded by a negative fixture
  that must produce zero findings. `--check` is the fail-closed gate mode: exit 1 on a gating
  finding, exit 2 when inputs could not be fully read or when 0 test files were examined (an
  unread input is never a clean one, and a wrong or empty scan root must not share exit 0 with a
  healthy suite), exit 0 only for a fully read clean scan of at least one test file. That is the
  liveness-assertion contract's fail-loud limb.
  `--persist-findings` (explicit override; bare invocation stays read-only per the `audit` verb
  contract) writes a detector-findings-conforming file that the `review:fanout` `fix` action
  consumes, with `Tier` looked up flat per rule (IMPORTANT), `Confidence` high or omitted (never
  low), root-relative `Location`, cell escaping, and `## Surfaces` coverage. Every run reports a
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
  *default* rather than an absolute, and two clients on one version can differ, which an unscoped
  "only" cannot express. **The instruction this note supports is unchanged and was strengthened, not
  weakened:** suggest `/verify`, never delegate to it. A delegated call is refused at the tool layer,
  so the suggest-don't-delegate rule now holds across either invocability state rather than resting
  on a version cutoff.
- **The note becomes a conforming upstream-drift record.** Touching a restatement of an
  upstream-owned specific binds the required parts on touch (`docs/conventions/upstream-drift/README.md`
  §Adopters), so the claim now carries a verification date, the client versions checked, and an
  observable recheck trigger rather than a bare link. The trigger is a Claude Code release whose
  changelog names `/verify` or bundled-skill invocability.

## [0.5.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command. The
  slash-command picker then echoed that back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.4.0]

### Added

- **`diagnose`: redaction guard + tagged debug logs.** A new `## Redact` section in the router
  requires every secret redacted (`<REDACTED>`) before commands, test output, stack traces, or
  CI logs are shown; reproductions read credentials from env vars so secrets never land in a
  command line, fixture, or committed regression test. Investigation step 4 now tags every
  debug log with a unique short prefix (e.g. `[DEBUG-a4f2]`), and the fix loop's green gate
  removes tagged instrumentation via a single grep before the atomic commit. The loop commits
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
- **The e2e prerequisite hard-fail says why workarounds are barred.** A substitute path yields
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
  restriction flatly. On 2.1.145–2.1.214 `/verify` is still model-invocable. The instruction itself
  is uniform across the window, because suggesting is correct on every version `/verify` exists on.
  The orchestrator path was already the fallback and is unchanged. The `≥ 2.1.145` availability floor
  is a separate axis, unchanged and re-verified 2026-08-02.

## [0.3.2]

### Changed

- **Doc reference updated for the `config-cascade` convention rename (#1188).** The layering-contract links in
  `README.md`, `run-e2e/SKILL.md`, and `run-e2e/context/e2e-config.md` now point at
  `docs/conventions/config-cascade/` (formerly `consumer-config-layering`). No behavior change.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention. Bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- `/testing:run-e2e` gains a consumer-project config surface, `.claude/testing/e2e.md`,
  with two per-key-override keys: `recording` (`video | gif | off`, default `off`) and
  `browser_mode` (`headed | headless`, default `headless`). Defaults preserve current
  behavior. Keys, defaults, and precedence live in the skill's bundled
  `run-e2e/context/e2e-config.md`; layers resolve per the marketplace
  consumer-config-layering convention.
- Optional recording evidence tier in the E2E evidence contract: video via the
  playwright CLI for long flows, GIF via `gif_creator` for short demos, plus a
  session-artifacts record (recording path, session ID, transcript pointer). Screenshots
  remain the evidence floor.

### Changed

- `/testing:run-e2e` now resolves the config surface before driving. It anchors at the
  repo root, merges all three layers per key, and reports which layer supplied each
  effective value, then passes the resolved `browser_mode` and `recording` values
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
  ghost `testing.md` reference to xUnit v3 / Shouldly, since this plugin ships `write.md`/`organize.md` and
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
  `write`'s handoff). Framing and labeling only. TDD cadence, Four Pillars, verify-through-the-interface, the
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

- **BREAKING: `/testing:e2e` renamed to `/testing:run-e2e`** (fleet conformance wave:
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

- Initial release, with four skills extracted and renamed from the `implementation` plugin's `test-*`
  skills: `/testing:plan` (was `test-plan`, coverage-gap analysis), `/testing:write` (was `test-write`,
  TDD authoring and placement), `/testing:e2e` (was `test-e2e`, live app + non-UI smoke verification),
  and `/testing:diagnose` (was `test-diagnose`, failing-test root-cause diagnosis and the fix loop).
  Skill trigger phrases and evals are preserved; only the namespace and leaf names changed.
- Cross-plugin references degrade gracefully: test invocation defers to `/toolchain:build` when the
  `toolchain` plugin is installed (else the project's own test command), and handoffs to
  `/implementation:implement`, `/verification:confirm`, `/tdd:principles`, and `/playwright:playwright`
  fire only when those plugins are installed. No hard dependencies.
