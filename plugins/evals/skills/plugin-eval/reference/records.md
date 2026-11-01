# Basis behind the hub's dated records

Each hub rule that rests on an upstream specific carries its pointer, as-of date and recheck
trigger in `SKILL.md`. This file holds the observations behind them, for a human reader deciding
whether a recheck trigger has fired. When a trigger fires: re-read the pointer, re-run what the
row names, refresh the hub rule and this row with the outcome, and record a drift outcome in this
plugin's CHANGELOG.

## Contents

- [Version floor](#version-floor)
- [Sandbox and credential store](#sandbox-and-credential-store)
- [Worktrees](#worktrees)
- [Command flags](#command-flags)
- [Spoke reach](#spoke-reach)
- [Ceiling, trust and report behavior](#ceiling-trust-and-report-behavior)
- [Cost anchors](#cost-anchors)

## Version floor

`claude plugin eval --help` on the floor release (2.1.269) plus the troubleshooting section of
<https://code.claude.com/docs/en/plugin-evals>, verified 2026-09-12. Recheck: re-run `--help` and
re-read the page.

## Sandbox and credential store

- Bash sandbox: the plugin-evals platform notes, verified 2026-09-12, and
  [Set up Linux and WSL2](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2),
  fetched 2026-10-04. Recheck: re-derive the hub's backend table from that section.
- Docker credential store: the refusal hit all 60 runs of one pass at Claude Code 2.1.289 under
  WSL2, observed 2026-10-04. Docker Desktop's WSL integration links `contexts` and `features.json`
  into `/mnt/c`. The `~/.docker/bin` exemption on macOS is from the 2.1.293 changelog entry. Docs
  lag: neither the plugin-evals page nor the sandboxing page covers the refusal as of 2026-10-10,
  and the current refusal wording is not captured here: it needs a macOS or WSL2 host. Recheck:
  re-run one `Bash`-granting case on a host with such a link.
- Link swap (`scripts/docker-links.py`): it swaps every link the preflight's `find` lists, and the
  store itself when that is a link, rather than only the links the CLI is thought to check, since
  which names the CLI exempts was read from one 2.1.314 binary and failed independent
  verification. Pointer: <https://code.claude.com/docs/en/changelog>, the release notes on sandbox
  credential exclusion. As of 2026-10-30. Recheck: a docs page documents the check or its exempt
  names, or a release note touches them. The fixture suite (`test_docker_links.py`) proves the
  swap and restore on a temporary `HOME`; no host run on WSL2 has been recorded yet.

- Read-only `.git` and session tmp directory under `--allow-tools Bash`: a `claude plugin eval` run
  saw the scratch repo's `.git` as read-only on Claude Code 2.1.310 and 2.1.314, Linux/WSL2,
  2026-10-24 and 2026-10-29 (`git fetch` failed writing `.git/FETCH_HEAD` with "Read-only file
  system"). On 2.1.314 the session tmp directory was read-only too: the shell's cwd-tracking write
  failed, so a Bash call could report exit 1 though its command succeeded. A fresh clone and an
  out-of-repo copy failed the same way. Claude Code 2.1.302 completed a merge on 2026-10-18. The
  cause within the CLI is not bisected (UNVERIFIED). Evidence:
  [#10277](https://github.com/melodic-software/claude-code-plugins/issues/10277),
  [#6997](https://github.com/melodic-software/claude-code-plugins/issues/6997). Recheck: re-run the
  source-control pull-request-ready cases on the next CLI release.

## Worktrees

- The Bash guard's `eval` refusal: `claude plugin eval --help` refused from a worktree-isolated
  subagent on Claude Code 2.1.296, Linux/WSL2, verified 2026-10-13 (#5696), with the message `this
  command runs a string through eval, which can't be verified to stay inside the worktree`. The
  user's own `!` command clause rests on the repro on Claude Code 2.1.285, Linux/WSL2, verified
  2026-10-01. Upstream: anthropics/claude-code#88312, anthropics/claude-code#90377.
- Session shapes, headless `claude -p --permission-mode auto` probes with an `echo ok` control
  each, Claude Code 2.1.301, Linux/WSL2, 2026-10-16:
  - Allowed: a normal session whose working directory is a `git worktree add` worktree; the same
    session after `ExitWorktree` with `keep`.
  - Refused, same message: `claude -p --worktree`; a session after `EnterWorktree`; a subagent
    spawned with no `isolation` from a `--worktree` session, with an absolute target (the message
    names the parent's worktree).
  - Allowed in every shape: the static validator, `validate-cases.py <absolute eval dir>`.
  - Not probed: whether `ExitWorktree` lifts isolation in a `--worktree` session.
  - A peer isolated session also had routine Bash refused for the bare word (`grep -i eval`).
  Recheck: re-run `claude plugin eval --help` in a `--worktree` session and in a normal session
  started in a worktree.
- Recheck on Claude Code 2.1.316, Linux/WSL2, 2026-10-31 (#5696), same probe shape: `claude -p
  --worktree` still refused, same message; a normal session in a `git worktree add` worktree
  allowed.
- The CLI's linked-worktree refusal (`registers more linked worktrees than can be screened`):
  observed on Claude Code 2.1.289, Linux/WSL2, 2026-10-04. Recheck: re-run on a plugin in a
  repository with many linked worktrees.

## Command flags

`claude plugin eval --help` plus <https://code.claude.com/docs/en/plugin-evals>, verified
2026-09-12, with the argument order and trust behavior reproduced against this repository's suite.
For the current `--judge-model` and `--threshold` defaults and the `-j/--concurrency` range, read
`claude plugin eval --help` or the command options table at
<https://code.claude.com/docs/en/plugin-evals#command-options>. Recheck: re-run `--help` when a
release note touches the flag set.

## Spoke reach

Kept traces (`--keep-temp`):

- 2.1.270: six with-arm runs of this plugin's suite, every spoke `Read` denied with `File is in a
  directory that is denied by your permission settings`, verified 2026-09-13.
- 2.1.287 under `--runs 2`: all three spoke `Read` calls in six with-arm runs denied with that
  text and listed in each trace's `permission_denials`, verified 2026-10-01. With a path-scoped
  `--allow-tools "Read(//<plugin>/skills/**)"` grant on one case, both with-arm runs still denied a
  spoke `Read` and the run's settings held no deny rule, verified 2026-10-02.
- 2.1.289: the `debugging` suite read `skills/debug/reference/rendered-view.md` in all three
  with-arm runs of one case, with `is_error` unset and `permission_denials: []`; the
  `architecture` and `planning` suites (12 with-arm runs each) had every spoke `Read` succeed,
  including `skills/interview/context/loop.md` and `skills/interview/context/relentless-mode.md`
  (10 of 12 `planning` runs read a `context/` file) and the plugin-level
  `plugins/planning/reference/artifact-protocol.md`, with no `Read` denied, verified 2026-10-04.
  At that version a skill's `context/`, `reference/`, `actions/` and `templates/` reads succeeded
  with no grant.
- 2.1.316, one with-arm run each of this plugin's `grading-method-choice`: copied to a directory
  named `evals`, the `Read` of `skills/methodology/reference/grading.md` was denied with the text
  above and listed in `permission_denials`; copied to `evals-plugin`, the same `Read` succeeded,
  verified 2026-10-31. The run's sandbox settings listed the plugin root under `denyRead`. Every
  denial above is this plugin, whose directory is named `evals` like the default eval directory,
  so the earlier entries do not show a version boundary.

For what a grant covers, see <https://code.claude.com/docs/en/plugin-evals#grant-tools>, as of
2026-10-02. Recheck: re-run one case with `--keep-temp` and read the with-arm trace.

## Ceiling, trust and report behavior

- The ceiling's two shapes, `--trust-plugin` persisting, and `--json <file>` suppressing the
  table: reproduced across five pilot passes at Claude Code 2.1.269 and 2.1.270, recorded in
  [`docs/specs/plugin-evals-pilot-measurement.md`](https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/plugin-evals-pilot-measurement.md),
  "Observations for the runner skill", verified 2026-09-12 against the `--max-cost-usd` and
  exit-code rows of the plugin-evals page. Recheck: re-run one ceilinged pass.
- A usage or rate limit not marked partial, `kept local` versus publishing, and `init` needing a
  terminal: the plugin-evals page's troubleshooting entry for a usage or rate limit, its HTML-report
  section, and its "Write a case manually" and CI sections, verified 2026-09-13.
- A headless `-p` session that backgrounded the CLI call exited, and the run ended unfinished
  (2026-09-13: empty `out/`, no JSON; 2026-10-04: three runs partial, interrupted, INVALID),
  seen on the versions current then. Which way those runs backgrounded the call is not
  recorded, so they do not show why the runs died.
- 2.1.316, a host probe on a throwaway one-case plugin, 2026-10-31: a `claude -p` session told to
  start the command through the Bash tool with `run_in_background`, answer at once and not wait,
  stayed open until the command ended. A `claude plugin eval` run (one case, two runs, 12 s)
  exited 0 with `partial: false` and wrote its results JSON; a `sleep 120` stand-in wrote its
  marker. A shell-level `(sleep 60; ...) &` inside a foreground Bash call got no wait: the
  session answered and exited about a minute before the child wrote its marker. That arm was a
  stand-in, not `claude plugin eval`. No arm tested a time limit. Recheck: re-run the three arms
  on a release that touches background tasks or `-p` exit.

## Cost anchors

List-price estimates measured on this plugin's own read-only suite with no `--model` (it served
opus-5-5):

| Claude Code | Date | Pass | Cost |
|---|---|---|---|
| 2.1.287 | 2026-10-02 | 24 runs: four cases, three runs, two arms, sonnet judge | 1.67 USD |
| 2.1.287 | 2026-10-02 | 16 runs: two runs, haiku judge (Haiku 4.5) | 0.98 USD |
| 2.1.287 | 2026-10-02 | 42 short single-arm calibration runs | 1.79 USD |
| 2.1.296 | 2026-10-11 | 16 runs: four cases, two runs, two arms, haiku judge (Haiku 5.5) | 1.98 USD |

That is 0.04 to 0.125 USD per run on average, judge calls included, and 0.03 to 0.2 USD for one
run. The 0.2 USD headroom figure is 1.6 to 4.7 times each pass's per-run cost.

The older 0.8 USD per without-run anchor came from passes at 2.1.270 (2026-09-12 and 2026-09-13)
whose without-arm loaded the bundled `claude-api` skill on every run, costing five to seven times
the with-arm; that skill's injected body was about fourteen times the size of this plugin's hub.
At 2.1.287 no without-run loaded a skill, and that arm cost less than the with-arm.

Recheck: a Claude Code release note touches `plugin eval`, the model a run serves changes, or a
pass averages more than 0.2 USD per run. Then re-derive from the last three passes.
