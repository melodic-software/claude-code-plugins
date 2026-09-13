# Preflight: the runner skill's live transcripts

Evidence for acceptance criteria 1, 4, and 5 (the preflight report per target type, the refusal of
a Bash-granting suite before any spend, and the unlimited option). Each transcript is the report
block the skill printed, quoted as printed; prose around it is summarized. The five preflight
transcripts invoked no `claude plugin eval` and spent nothing; the one `run` transcript at the end
of criterion 5 did invoke it, and that run is pass 5 in `pilot.md`.

## Setup

- Command shape, run from the PowerShell tool in the worktree root:
  `claude -p "/evals:plugin-eval preflight <target>" --plugin-dir plugins/evals --allowedTools
  "Bash,Read,Glob,Grep,Skill" --output-format text`.
- Claude Code 2.1.270. The CLI auto-updated past the 2.1.269 the plan pinned; the floor is met,
  and `--help` at 2.1.270 lists the same options as the recorded 2.1.269 surface.
- Which `evals` resolved: only the worktree copy carries the `plugin-eval` skill (both installed
  copies are 0.2.x and disabled), so every rendered report below is itself the proof that
  `--plugin-dir` resolved the worktree copy.
- Fixtures outside the repo: a wrapped-skill directory (a copy of `skills/validate` under a minimal
  `.claude-plugin/plugin.json` named `wrapped-validate`, no eval cases) and a copy of the pilot
  suite whose `control-no-trigger` case grants `Bash`.

## Criterion 1: the report per target type

### `plugins/evals` (plugin)

```text
cli_version:     2.1.270 (Claude Code)
floor_met:       true
platform:        windows
sandbox_backend: absent
target_type:     plugin
suite_tools:     read-only
estimate_usd:    roughly 3.5 (3 cases x 3 runs x 2 arms = 18 agent runs, plus 18 judge calls)
ceiling:         5 USD
```

The skill said a run would go ahead, that the missing sandbox blocks nothing because every case is
read-only, and that the ceiling came through as the literal `${user_config.max_cost_usd}`
placeholder so it used the manifest defaults (5 USD, not unlimited) and said so. It priced the
knowledge case's three without-runs at the high end of the recorded range, which is where the 3.5
comes from against the 2.1 to 2.7 per pass measured before Phase 6 (2.1 to 3.2 after it). It
stopped without invoking the CLI.

### Wrapped skill (a bare skill under a minimal manifest)

```text
cli_version:     2.1.270 (Claude Code)
floor_met:       true
platform:        windows
sandbox_backend: absent
target_type:     wrapped-skill
suite_tools:     none found (no plugin-eval cases)
estimate_usd:    roughly 0 (0 cases x 3 runs x 2 arms, 0 judge calls)
ceiling:         5 USD
```

The skill identified the wrapper, reported that the directory has no `prompt.md` or `case.yaml`,
flagged the skill's own `evals/evals.json` as the skill-creator format the CLI cannot read, and
gave the next steps (write cases at the wrapper root or run `/evals:design`, pair a `tool_used`
grader on `Skill` with an outcome grader, validate, preflight again).

### `.claude/rules` (rules, refused)

```text
cli_version:     2.1.270 (Claude Code)
floor_met:       true   (floor 2.1.269)
platform:        windows
sandbox_backend: absent (native Windows)
target_type:     rules
suite_tools:     n/a (no suite; refused at routing)
estimate_usd:    0 (refused before any run)
ceiling:         5 USD (manifest default; user_config placeholders did not render), unlimited: false
```

Refused with the reason (every run starts from a throwaway home without `CLAUDE.md` or
`.claude/rules`, so a shim would measure the shim) and the route: `/claude-config:unhobble`,
which the skill found installed and named without starting, since preflight only reports.

## Criterion 4: a Bash-granting case on a machine with no backend

Target: the pilot-suite copy with `allowed_tools: [Read, Glob, Grep, Skill, Bash]` on
`control-no-trigger`.

```text
cli_version:     2.1.270 (Claude Code)
floor_met:       true
platform:        windows
sandbox_backend: absent
target_type:     plugin
suite_tools:     Bash
estimate_usd:    roughly 2.7 (3 cases x 3 runs x 2 arms = 18 agent runs, plus 18 judge calls)
ceiling:         5 USD
```

The transcript opened with the refusal: no sandbox backend on this machine, and
`control-no-trigger` grants `Bash`. It named both halves (each granting run would be refused by the
CLI and score 0 instead of measuring anything; the route is WSL2, a Linux host with `bubblewrap`
and `socat`, macOS, or a Claude cloud session) and the suite-side alternative (drop `Bash` from
that case). No CLI call was made, and the fixture held no `results/` directory afterwards
(checked with a filesystem search).

## Criterion 5: the unlimited option

The plan's route (set the option in the installed plugin's config) does not reach a `--plugin-dir`
session: without a stored value, `${user_config.max_cost_usd}` and `${user_config.unlimited_cost}`
render as their literal placeholder text, and the skill falls back to the manifest defaults and
says so (every transcript above). The official plugins reference documents that `pluginConfigs`
is read from user settings, `--settings`, or managed settings only, so the attestation used
`--settings` with `{"pluginConfigs":{"evals":{"options":{"max_cost_usd":5,"unlimited_cost":true}}}}`
on the `plugins/evals` target:

```text
cli_version:     2.1.270 (Claude Code)
floor_met:       true
platform:        windows
sandbox_backend: absent
target_type:     plugin
suite_tools:     read-only
estimate_usd:    roughly 2.7 (3 cases x 3 runs x 2 arms = 18 agent runs, plus 18 judge calls)
ceiling:         unlimited
```

The estimate printed, the ceiling read `unlimited`, no confirmation was asked, and the skill stated
that a run would leave out `--max-cost-usd`. Attested by hand from the transcript; the value was
supplied for the session, and no settings file on the machine was changed.

The clause "the run proceeds without a prompt" was then exercised through the skill's `run`
action with the same `--settings` block (`claude -p "/evals:plugin-eval run plugins/evals …"`).
The session's transcript shows the sequence the skill prescribes: the version and suite read, the
validator (exit 0), then the CLI invoked in the foreground with a ten-minute tool timeout as
`claude plugin eval plugins/evals --trust-plugin --json <ignored path> --threshold 0.8
--no-publish`, with no `--max-cost-usd` and no confirmation step. It exited 0 after 381 s at
3.20 USD, `partial: false`, deltas +1.00 / 0.00 / 0.00 (pass 5 in `pilot.md`). One gap against
the skill's own rule: the estimate ("about 6.0, a deliberate overestimate") appears in the
session's final answer, not as a message emitted before the CLI call; a headless session tends
to go straight from the reads to the tool call and report the estimate afterwards.

A first attempt at the same run ended early: the session backgrounded the CLI, answered "the run
started", and exited, which killed the run after one temp directory with an empty `out/`, no
JSON, and no results directory. The second attempt added "run the CLI in the foreground and
wait" to the prompt. Both are recorded in the runner skill (the run step and a Gotchas bullet).

## Observations for the runner skill

- Under `--plugin-dir` with no stored `pluginConfigs`, the placeholders render literally. The
  skill's fallback sentence covers it, and the report says which values it used.
- The estimate moved between transcripts on the same suite (3.5, 2.7, 2.7) depending on whether
  the model priced from the per-run anchors or the measured full-pass range. One transcript
  noted that applying the 0.8 USD without-run anchor to all nine without-runs gives about 8 USD,
  above the 5 USD ceiling, while the measured pass is 2.7; the anchor is for a knowledge case,
  and the skill body now says so.
- `cli_version` is the live number, not the floor: the reports print 2.1.270 on a machine the plan
  expected to be at 2.1.269, and `floor_met` carried the comparison.
