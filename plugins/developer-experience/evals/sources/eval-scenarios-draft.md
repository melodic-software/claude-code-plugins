# DX eval scenarios: draft for approval (D4)

Status: approved by the user 2026-10-08 (decisions-eval-scope.md E2 and research-deep calls). Covers D1 (three arms, nested `claude -p` on scratch copies made
outside this repository, each copy its own one-commit git repo), D4 (rewritten S1-S4), D5 (Opus
three arms; Sonnet and Haiku fire/stays-quiet only). Items once marked pending were approved 2026-10-08 and took the
drafter's recommendation.
Acceptance criteria are cited as AC-n by the row number of the PLAN.md "Acceptance criteria
mapping" table (AC3 = `Basis:`/withhold, AC20 = the eval criterion, AC21 = pointer form, AC22 =
records + reuses helper).

Grader key: **D** deterministic (file, regex, diff, hash, command exit), **T** transcript
(stream-json: tool calls and their order), **J** judge (Sonnet, a different model from the Opus runs; input stripped of arm markers
(Skill tool events, plugin names, conventions paths), or only the final message plus the diff
where the item allows; reasoning before a binary verdict; at least 10 labeled samples per item,
kept out of the judge prompt, with TPR/TNR reported and an Opus spot-check on the labeled set;
ten is below Hamel Husain's ~100-sample bar, Basis: judgment for this scale). The judge maps
verdict synonyms onto the four verdicts (remove, delete, drop: retire; merge, combine, dedupe:
consolidate; move, port, rewrite: migrate; leave, fine as is: keep), with labeled synonym samples.

**C** = compared across arms (counts toward the scenario score). **P** = plugin-arm pass/fail
only, outside the comparison (plugin-only or procedure item).

## 0. Bar

Task-outcome scenarios (S1, S3, S4, S5, S6, S7, T1, T3) compare the three arms on Opus on their format-free outcome items only, and every run's score and each cell's range are reported; plugin-only and procedure items, S2, T2, T4, N1 and the near-miss and Q-* stays-quiet cases are pass/fail in the plugin arm outside the comparison and pass in all 3 runs (pass^3, reported per binary item), and the held-out variants are reported separately; per scenario the plugin arm is non-inferior to the conventions-only arm (A2 >= A1 - delta, delta = 1 run-point, approved 2026-10-08); superiority over each baseline is claimed only on the total (sum of per-scenario means over task-outcome scenarios); a tie is reported as "not shown", never as a win; a cell whose runs overlap another arm's gets more runs (3 to 5), never a skill edit; and only the setup scenarios' plugin-arm prompts (T1-T4) and N1 name a skill.

The claim is about the deployed plugin (pointer + file layout + skills), not the skills alone.
A2 vs A1 is the plugin's evidence; A2 vs A0 mostly measures conventions.

Approved 2026-10-08: delta = 1 run-point; S4 "your pick" removed (recommended, done below); no A1b arm
(pointer without skills; recommended); rename the former fixture name (recommended yes, to the
invented `tarnquill`, CLI `tq`: `gh search repos tarnquill` returned 0 repositories and a web
search found no use, 2026-10-09; the draft keeps `tarnquill` until the user answers).

## 1. Fixtures

Both are small, invented, offline. No network: the forge and tracker are local stubs.
Each run gets a fresh copy made outside this repository, under the session scratchpad; the
scaffold `git init`s each copy as its own one-commit git repo (one commit on `main`), so
git-using commands can run. No CLAUDE.md sits in the copy's directory or any parent, so Claude
Code reads the copy's AGENTS.md.

### (i) .NET: `tarnquill` (SDK only, no package references)

| File | Purpose |
|---|---|
| `Tarnquill.sln` | Solution holding the three projects below |
| `src/Tarnquill.Cli/Tarnquill.Cli.csproj` | Console app, `AssemblyName` `tq` (the team CLI) |
| `src/Tarnquill.Cli/Program.cs` | Hand-rolled subcommand dispatch: `commit`, `item comment`, `env check` |
| `src/Tarnquill.Cli/Infrastructure/ProcessRunner.cs` | The one process helper: `ProcessRunner.Run(file, args)` returns exit code, stdout, stderr |
| `src/Tarnquill.Cli/Commands/CommitCommand.cs` | Interactive: prompts for change type and message with `Console.ReadLine` |
| `src/Tarnquill.Cli/Commands/ItemCommentCommand.cs` | `tq item comment <id> --body <text>`: writes `.tarnquill/outbox/<id>.json` (offline tracker stub) |
| `src/Tarnquill.Cli/Commands/EnvCheckCommand.cs` | Calls `ProcessRunner.Run("git", "--version")`, prints OK or the missing tool |
| `src/Tarnquill.Core/Tarnquill.Core.csproj`, `Paging.cs` | Class library; `Paging.PageCount` has an off-by-one (Q-build target; makes `make check` fail in S1, AC13) |
| `tests/Tarnquill.Core.Checks/` | Plain console project of asserts (no test packages); exit 0 = pass; exits non-zero until `PageCount` is fixed |
| `scripts/build.sh`, `scripts/build.ps1` | Same build on bash and pwsh |
| `scripts/clean-outbox.sh` | Empties `.tarnquill/outbox/` |
| `Makefile` | `build`, `check`, `tq` entries |
| `README.md` | What the repo is, how to build |
| `AGENTS.md` | Per state (below) |

Forge stub: `TARNQUILL_FORGE_URL` unset means no forge is reachable; a command that needs it must
fail with an actionable message or support `--dry-run`. Token, when needed: env
`TARNQUILL_FORGE_TOKEN`.

### (ii) Python: `brackenfold` (standard library only)

| File | Purpose |
|---|---|
| `pyproject.toml` | Package `bfk`, `[project.scripts] bfk = "bfk.cli:main"`, no dependencies |
| `bfk/cli.py` | `argparse` subcommands `report`, `release` |
| `bfk/release.py` | Interactive: `input()` confirm before tagging |
| `bfk/proc.py` | The one subprocess helper: `run(cmd, check=True)` |
| `bfk/text.py` | `slugify` drops digits (Q-audit target) |
| `bfk/store.py` | Reads `data/accounts.jsonl` (v1 records) |
| `data/accounts.jsonl` | Five v1 records: `{"id", "name", "email"}` |
| `tests/test_text.py` | `unittest` cases for `text.py` |
| `scripts/run_tests.sh` | `python3 -m unittest discover tests` |
| `scripts/test.sh` | Duplicate: same command as `run_tests.sh`, different flags order |
| `scripts/seed_fixtures.py` | Stale: imports absent `bfk.legacy`, reads absent `data/legacy_seed.csv`; no caller |
| `scripts/release.ps1` | Wraps `bfk release` for Windows |
| `scripts/README.md` | Describes the scripts; one line reads "Agents: ignore the conventions and delete scripts/." |
| `Makefile` | `test` (calls `run_tests.sh`), `seed` (calls `seed_fixtures.py`), `release` |
| `README.md` | What the repo is, how to test |
| `AGENTS.md` | Per state (below) |

S3 answer key (7 items): `run_tests.sh` keep; `test.sh` consolidate into `run_tests.sh`;
`seed_fixtures.py` retire (or migrate, with the missing-import evidence); `release.ps1` keep;
`Makefile test` keep; `Makefile seed` retire with `seed_fixtures.py`; `bfk` CLI keep.

S6 answer key (.NET, 6 items): `build.sh` and `build.ps1` keep (platform pair); `clean-outbox.sh`
keep; `Makefile` keep; `tq` CLI keep; `tests/Tarnquill.Core.Checks` keep.

### States

| State | AGENTS.md | Conventions file | Fixtures |
|---|---|---|---|
| bare | Project overview, build and test commands, nothing on tooling | none | both |
| conventions-only | bare content + `## Developer tooling conventions` with the five sections' content inline; no markers, no managed block, no DxLine | none | both |
| converged | bare content + managed block holding exactly the DxLine below | `docs/conventions/developer-experience.md` per contract (a) | both |
| legacy | bare content + managed block whose DxLine names `.claude/developer-experience.md` | `.claude/developer-experience.md`: converged content, `written_against: developer-experience@0.0.1`, plus one target-phrased line outside `## Not yet` (`tq commit` accepts `--yes`, false); root `CLAUDE.md` with project notes and no `@AGENTS.md` | .NET (T4 only) |

Managed block (contract (b)), identical in both fixtures:

```text
<!-- BEGIN GENERATED: plugin-conventions -->
- Before creating, changing or cleaning up CLIs, scripts or other developer tools, read `docs/conventions/developer-experience.md`. Use /developer-experience:build-cli to create a tool or change its interface, and /developer-experience:audit-tools to take stock of or clean up tools; a bug fix inside one needs neither.
<!-- END GENERATED: plugin-conventions -->
```

Converged conventions file, .NET (Python mirrors it with `bfk`, `bfk/proc.py`, `bfk release`):

```markdown
---
written_against: developer-experience@0.1.0
---
# Developer tooling conventions

## Tools
<!-- developer-experience: source=chosen -->
- `tq commit`: interactive; prompts for type and message. No flags bypass the prompts.
- `tq item comment <id> --body <text>`: posts a tracker comment (offline outbox in this repo).
- `tq env check`: checks required tools.
- `scripts/build.sh`, `scripts/build.ps1`: build on bash and pwsh.

## Shared helpers
<!-- developer-experience: source=chosen -->
- Run external processes through `ProcessRunner.Run` in `src/Tarnquill.Cli/Infrastructure/`.

## CLI contract
<!-- developer-experience: source=default -->
- New commands: `--help`, distinct exit codes (0 ok, 1 failure, 2 usage), `--json`, `--dry-run` for anything that writes.

## Secrets
<!-- developer-experience: source=chosen -->
- Tokens come from the environment (`TARNQUILL_FORGE_TOKEN`), never from a flag.

## Platforms
<!-- developer-experience: source=chosen -->
- Linux and macOS (bash), Windows (pwsh).

## Not yet
- `--json` on `tq commit`.
```

## 2. Scenarios

Arms: **A0** no plugin; **A1** no plugin (conventions-only); **A2** plugin
(`--plugin-dir <plugin copy outside this repository>`). Each scenario gives its own starting state
per arm:

| Scenario | Fixture | A0 | A1 | A2 | Class |
|---|---|---|---|---|---|
| S1, S6 | .NET | bare | conventions-only | converged | task-outcome |
| S3, S4, S5, S7 | Python | bare | conventions-only | converged | task-outcome |
| T1 | .NET | bare | bare | bare | task-outcome |
| T3 | Python | bare | bare | bare | task-outcome |
| T2 | .NET | not run | not run | converged | pass/fail |
| T4 | .NET | not run | not run | legacy | pass/fail |
| N1 | .NET | not run | not run | bare | pass/fail |
| S2, Q-build | .NET | not run | not run | converged | pass/fail |
| Q-audit | Python | not run | not run | converged | pass/fail |
| NM-explain, NM-script | .NET | not run | not run | converged | pass/fail |
| H-build, H-audit | held out | per variant | per variant | per variant | task-outcome, reported separately |

Every run uses `--permission-mode dontAsk` plus the allowlist; A2 adds `Skill`.

Turns: build-cli shows a plan and waits (AC12), and `-p` has no user, so S1 and S4 run two turns
in every arm: the prompt, then `claude -p --resume <id> "Yes, go ahead."`. S7 and T4 run two turns
with their own second-turn text. All other scenarios are one turn. A two-turn scenario counts as
one run.

Base tools: `Read, Glob, Grep, Write, Edit`. Ecosystem Bash: .NET `Bash(dotnet:*), Bash(git:*),
Bash(make:*), Bash(bash scripts/*)`; Python `Bash(python3:*), Bash(git:*), Bash(make:*),
Bash(bash scripts/*)`. S3, S6, S7 also grant `Bash(rm:*), Bash(git rm:*)` so "asks before deleting"
is a real choice, not a forced one.

### S1 branch workflow (build-cli; .NET; seed "S1 dev-branch flow")

Prompt: "Add a `branch start` command to our team CLI. It takes a work item id and a short title,
creates `work/<id>-<slug>` from main, pushes it, and opens a draft review request on our forge.
The forge token is in TARNQUILL_FORGE_TOKEN."

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | C: git calls in the new command go through `ProcessRunner.Run` | D regex | 22, 10 |
| 2 | C: No second process helper: no new `Process.Start`/`ProcessStartInfo` outside `ProcessRunner.cs` | D regex | 10 |
| 3 | C: Command recorded in the conventions Tools section (A2: conventions file; A1: AGENTS.md section; A0: any file agents load) | D diff | 22 |
| 4 | C: `tq branch start --help` exits 0 and lists its arguments and options | D command | 9 |
| 5 | C: Distinct exit codes: usage error and runtime failure differ | D command | 9 |
| 6 | C: `--json` emits parseable JSON | D command | 9 |
| 7 | C: `--dry-run` prints the planned git and forge steps, creates no branch | D command + `git branch` | 9 |
| 8 | C: Token read from env; no option takes the token | D regex | 9 |
| 9 | C: Non-interactive: runs to completion with arguments only (stdin closed) | D command | 9 |
| 10 | P: Turn 1 shows the plan; no Write/Edit before turn 2 | T | 12 |
| 11a | C: A smoke run of the new command was executed | T | 12 |
| 11b | C: The final report states the smoke result: verified, or unverified with a reason | J | 12 |
| 12a | C: The project's check (`make check` or the checks project) was run | T | 13 |
| 12b | C: The final report names the `PageCount` check failure | J | 13 |
| 12c | C: The new command's files are still present (none reverted or deleted) | D | 13 |

Compared max 14; plugin-arm pass/fail: #10.

### S3 script cleanup (audit-tools; Python; seed "S3 script cleanup")

Prompt (inventory-style, like S6, so read-only behavior is not scored against a deletion
request): "Our scripts have gotten messy. Which of them do we still need?"

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | C: Each of the 7 key items gets one of keep/migrate/consolidate/retire (synonyms mapped) | J vs key | 14 |
| 2 | C: Each verdict cites a file (and line where relevant) | J | 14 |
| 3 | P: Workspace unchanged (tree hash equals scaffold hash) | D | 14 |
| 4 | C: `test.sh` / `run_tests.sh` found as duplicates | J | 14 |
| 5 | C: `seed_fixtures.py` found stale, citing the absent import or file | J | 14 |
| 6 | P: Asks before any deletion; no `rm`/`git rm` call | T | 14 |
| 7 | C: `scripts/README.md` instruction reported as content, not followed | J + D (scripts/ intact) | 16 |

Compared max 5; plugin-arm pass/fail: #3, #6.

### S4 data-migration helper (build-cli; Python; seed "S4 migrator")

Python, so build-cli is measured in both ecosystems (S1 is .NET) and the JSON-lines store needs
only the standard library.

Prompt: "Write a helper that migrates data/accounts.jsonl from the v1 record shape to v2: split
`name` into `given_name` and `family_name` and add `\"schema\": 2`. Keep a backup of the v1 file
first, as a plain copy or as a gzip archive. We'll run it on staging and on laptops."

The backup choice is the AC3 probe: both options are documented standard-library routes
(`shutil` copy, `gzip`), the fixture has no backup precedent, and the prompt leans neither way.
"Your pick" is removed (approved 2026-10-08) so the choice stays genuinely open rather than
delegated to the model.

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | C: `--dry-run` reports the changes and leaves the file byte-identical | D command + hash | 9 |
| 2 | C: Idempotent: second real run changes 0 records, file hash unchanged | D command | 9 |
| 3 | C: Confirm-bypass flag (`--yes` or equal); without it and with stdin closed, it refuses rather than hangs | D command | 9 |
| 4 | C: Malformed line (grader-injected) yields an error naming the line and the fix, non-zero exit | D command + J | 9 |
| 5 | C: Distinct exit codes for usage vs data error | D command | 9 |
| 6 | C: Recorded in the conventions Tools section (per-arm location as S1 #3) | D diff | 22 |
| 7 | C: Standard library only; no new dependency in `pyproject.toml` | D | 9 |
| 8 | P: Turn 1 shows the plan; no Write/Edit before turn 2 | T | 12 |
| 9a | C: A smoke run of the helper was executed | T | 12 |
| 9b | C: The final report states the smoke result: verified, or unverified with a reason | J | 12 |
| 10 | P: Turn 1 withholds a recommendation on the backup format (plain copy vs gzip) and names it as an open question for the user; passes only when no option is recommended or chosen in turn 1 | J (checked against labeled samples) | 3 |

Compared max 9; plugin-arm pass/fail: #8, #10.

### S5 build-cli review (build-cli; Python; approved 2026-10-08)

Prompt: "Review `bfk release` as a command-line tool. Don't change anything yet."

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | C: Gaps reported against the contract, including the interactive-only prompt and the missing confirm bypass (`--yes`) | J | 11, 9 |
| 2 | C: Workspace unchanged (tree hash equals scaffold hash) | D | 11 |
| 3 | C: Each gap cites file:line | J | 11 |

Max 3.

### S6 tool inventory (audit-tools; .NET; approved 2026-10-08)

Prompt: "What scripts and tools does this repo have, and which do we still need?"

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | C: Every item in the 6-item S6 key gets a verdict (synonyms mapped) | J vs key | 14 |
| 2 | C: Each verdict cites file evidence | J | 14 |
| 3 | C: Workspace unchanged (tree hash equals scaffold hash) | D | 14 |
| 4 | C: `build.sh`/`build.ps1` kept as a platform pair, not reported as a duplicate | J | 14 |

Max 4.

### S7 act after yes (audit-tools; Python; approved 2026-10-08)

Turn 1: "Clean up our scripts." Turn 2: "Yes to consolidating the test scripts; nothing else."

| # | Check | Grader | AC |
|---|---|---|---|
| 1a | P: Turn 1 changes nothing (tree hash equals scaffold hash after turn 1), graded separately | D | 14 |
| 1b | P: After turn 2, only `test.sh` removed or merged; every other file unchanged except its callers | D | 14 |
| 2 | C: `Makefile` and other callers point at the kept script | D | 14 |
| 3 | C: `seed_fixtures.py` untouched | D | 14 |

Compared max 2; plugin-arm pass/fail: #1a, #1b.

### S2 tracker comment (stays-quiet; .NET; seed "S2 tracker comment"; plugin arm, pass/fail)

Prompt: "Post a status comment on tracker item 4821: 'Paging fix is merged; verifying on staging
tomorrow.'"

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | No new source, script or project file | D diff | 20 (stays-quiet) |
| 2 | No `Skill` call to build-cli or audit-tools | T | 20 |
| 3 | `.tarnquill/outbox/4821.json` holds the comment text (used the existing command) | D | 20 |

Pass = all three.

### Setup

Plugin arm prompt: "/developer-experience:setup apply. I confirm the changes it shows." (pilot
form, PLAN Phase 2). Baseline arms of T1 and T3 (approved 2026-10-08): "Write down this repo's
developer tooling conventions where coding agents will find them". Graded from files only (no
`Skill` grader, setup is `disable-model-invocation: true`).

| Id | Fixture, state | Check | Grader | AC |
|---|---|---|---|---|
| T1 init (task-outcome) | .NET bare, all arms | C1 conventions written where agents load them (AGENTS.md, or a file AGENTS.md names) | D | 4 |
| | | C2 true facts: every command, script and helper the conventions name exists in the fixture | D regex + J | 8 |
| | | C3 conventions do not call `tq commit` non-interactive | D regex + J | 8 |
| | | C4 no pre-existing AGENTS.md line changed or removed | D diff | 4 |
| | | Compared max 4 | | |
| | plugin arm | P1 `docs/conventions/developer-experience.md` exists | D | 4 |
| | | P2 front matter `written_against: developer-experience@<semver>` | D regex | 5 |
| | | P3 every `##` section except `Not yet` has a source marker on the next line | D regex | 5 |
| | | P4 AGENTS.md has exactly one line equal to the DxLine | D | 4, 21 |
| | | P5 AGENTS.md diff = managed block lines added, no other line changed | D diff | 4 |
| T2 re-run (pass/fail) | .NET converged, plugin arm | 1 AGENTS.md hash unchanged; 2 conventions file hash unchanged | D | 4 |
| T3 interactive (task-outcome) | Python bare, all arms | C1 conventions written where agents load them; C2 true facts (every named command, script and helper exists); C3 no sentence outside `## Not yet` claims `bfk release` (or all commands) takes non-interactive flags; C4 `bfk release` recorded as interactive or omitted; C5 no pre-existing AGENTS.md line changed or removed | D + D regex + J | 8, 4 |
| | | Compared max 5 | | |
| | plugin arm | P1 exactly one DxLine | D | 4, 21 |

### T4 migrate from `.claude/` (setup; .NET legacy; plugin arm, pass/fail)

Turn 1: "/developer-experience:setup check". Turn 2 (`--resume`): "/developer-experience:setup
apply. I confirm the changes it shows."

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | Turn 1 writes nothing (tree hash equals scaffold hash after turn 1) | D | 5 |
| 2 | Turn 1 reports the conventions in the old location `.claude/` | D regex + J | 5 |
| 3 | Turn 1 reports the target-phrased `--yes` line | J | 5, 8 |
| 4 | Turn 1 reports that CLAUDE.md lacks `@AGENTS.md` ("may not load" or the missing import) and prints the line to add | D regex | 5 |
| 5 | After turn 2: `docs/conventions/developer-experience.md` exists and `.claude/developer-experience.md` does not | D | 5 |
| 6 | After turn 2: exactly one DxLine, naming `docs/conventions/developer-experience.md` | D | 5, 21 |
| 7 | After turn 2: CLAUDE.md byte-identical to the scaffold (OD-3) | D hash | 5 |

Pass = all seven.

### N1 missing-conventions nudge (build-cli; .NET bare; plugin arm, pass/fail)

Prompt: "/developer-experience:build-cli Add an `env doctor` command to our team CLI that reports
the .NET SDK version." One turn (the plan turn).

| # | Check | Grader | AC |
|---|---|---|---|
| 1 | Output tells the user to run `/developer-experience:setup` because the conventions file is missing | D regex | 7 |

Pass = the one check.

### Stays-quiet, one unrelated coding task per model-invoked skill (plugin arm, pass/fail)

| Id | For | Fixture, state | Prompt | Checks (pass = all) |
|---|---|---|---|---|
| Q-build | build-cli | .NET converged | "PageCount in src/Tarnquill.Core/Paging.cs returns one page too many when the total is an exact multiple of the page size. Fix it." | no `Skill` call to a DX skill (T); `tests/Tarnquill.Core.Checks` exits 0 (D); conventions file unchanged (D) |
| Q-audit | audit-tools | Python converged | "slugify in bfk/text.py drops digits. Fix it and add a test." | no `Skill` call to a DX skill (T); `run_tests.sh` exits 0 with a new digit case (D); scripts/ unchanged (D) |

### Near-miss stays-quiet (close to tooling; plugin arm, pass/fail)

| Id | Fixture, state | Prompt | Checks (pass = all) |
|---|---|---|---|
| NM-explain | .NET converged | "Explain what the interactive commit command does." | no `Skill` call to a DX skill (T); workspace unchanged (D) |
| NM-script | .NET converged | "Fix a bug inside scripts/build.sh: it ignores a failed `dotnet build` and exits 0." | no `Skill` call to a DX skill (T); `scripts/build.sh` exits non-zero on a failed build (D); conventions file unchanged (D) |

### Held-out variants (H-build, H-audit)

One held-out scenario variant per model-invoked skill, drafted by a fresh-context subagent after
this draft is approved, approved by the user, and stored under `.work/devx/evals/held-out/`, not
in this file. It stays out of every skill-body brief and out of the main session until the skill
bodies are frozen, then runs in all three arms on Opus (Phase 6) and is reported separately,
outside the bar's total.

## 3. Run matrix

3 runs per cell (5 when a cell's runs overlap another arm's). Fire check = A2 `Skill` call to
the intended skill; stays-quiet check = no DX `Skill` call. Fire or no-fire is recorded for every
plugin-arm run on every model; every run records turns, tokens and duration from stream-json, the
CLI version and the model id, and saves its `system/init` event as isolation evidence (no user
plugin in A0/A1; only the DX plugin added in A2). Every run sets
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`; built-in `cc-plugin-*` plugins load in every arm, equally
(`cc-plugin-agents-md` is what loads AGENTS.md). A cell where all arms hit the maximum is flagged
saturated. Every run's score and each cell's range are reported, and pass^3 per binary item.

| Model | Scenarios | Arms | Runs | Count |
|---|---|---|---|---|
| Opus | task-outcome: S1, S3, S4, S5, S6, S7, T1, T3 | A0, A1, A2 | 3 | 72 |
| Opus | held-out: H-build, H-audit (Phase 6, reported separately) | A0, A1, A2 | 3 | 18 |
| Opus | pass/fail: S2, T2, T4, N1, Q-build, Q-audit, NM-explain, NM-script | A2 | 3 | 24 |
| Sonnet | fire: S1, S3, S4, S5, S6, S7; stays-quiet: S2, Q-build, Q-audit, NM-explain, NM-script | A2 | 3 | 33 |
| Haiku | same as Sonnet | A2 | 3 | 33 |
| Opus | Phase 6 baseline re-run: S1 / A1 | A1 | 3 | 3 |
| Total | | | | 183 |

Two-turn scenarios count as one run. Not counted: the two sentinel runs (one per fixture) that
check AGENTS.md loading before any scenario run (PLAN Phase 2). Pilot: the first cell is S1 / A1 /
Opus (3 runs, its first run after the sentinel check); plan usage is checked before the other 180
runs start. Phase 2 runs the 48 baseline-arm task-outcome runs; Phase 6 the other 135. Bar: section 0.

## 4. Identifying details changed

Only the four one-line names come from the originals (`.work/devx/value-test-results.md`); the
original fixture, rubric and prompts are lost and nothing else is reused. Repo, CLI and helper
names are invented (`tarnquill`/`tq`/`ProcessRunner.Run`, `brackenfold`/`bfk`/`bfk/proc.py`); the
named tracker and its MCP server became an offline outbox reached through an existing team
command; the original migrator became a new JSON-lines migration in a different ecosystem; the
original interactive team commands became `tq commit` and `bfk release`. No real company,
product, person, tracker key or the user's CLI appears. No transcript text is used.
