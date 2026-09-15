# dissolve-comments aggressive dial

## Brief

### TLDR

Add an `aggressive` posture and a `strip` argument to `/code-tidying:dissolve-comments` so a run
removes nearly every comment and rewrites the code to carry what it can, without loosening any
proof gate, then calibrate it against real and invented sections through a `claude plugin eval`
suite run in WSL2.

### Goal

Four runs of the current skill on this repository removed 2 of about 2,360 comment lines, because
every posture keeps rationale that passes the class-C test. The owner wants a dial that removes all
removable comments and makes the code self-describing for each one removed, plus a mode that
removes all comments except the ones that must survive, and a repeatable way to check the output
matches what the owner expects.

### Constraints

- No knob loosens a gate. Deletions carry the COMMENT-ONLY proof; function-local renames carry the
  RENAME-ONLY proof; tier-2 and tier-3 moves need a discovered test net covering the touched file;
  Introduce Assertion is test-net-only. A syntax check never substitutes for a gate.
- The exempt surfaces in `plugins/code-tidying/skills/dissolve-comments/reference/safety.md` hold in
  every mode, including `strip`, and so does a comment paired with a regression test.
- An identifier that appears in a repo-local marker row (for example
  `scripts/silent-revert-incidents.txt`) is never renamed.
- A non-interactive run on a widened rung still runs in safe mode.
- `change-shape.py` reads a Python docstring as a string token, so deleting any docstring, private
  ones included, reads CODE-CHANGED and cannot apply; under `aggressive`, Python docstring removals
  are proposals.
- The survivor list and gate statement live in `SKILL.md`, because a `claude plugin eval` with-arm
  cannot read the skill's reference files.
- `claude plugin eval` cannot set plugin `userConfig`, so every behavior the suite measures is
  reachable by an argument token.
- The per-skill `evals/evals.json` stays the CI-gated format; skill bodies state current rules only
  (`.claude/rules/skill-bodies-state-current-rules.md`); no em dashes in plugin prose.

### Acceptance criteria

Format: `free-text` (default; no convention surface resolved).

- `comment_posture` accepts `aggressive`, and `aggressive [target]` is accepted as a per-run token
  that wins over the standing value.
- Under `aggressive`, a comment passing today's class-C test but not on the exempt-surface list is
  deleted with its narrative staged, except a load-bearing warning, which is kept within
  `class_c_max_lines`; a class-B comment is dissolved when its move's gate passes or kept with a
  proposal when it does not.
- `strip [target]` deletes every comment except exempt surfaces, rewrites no code, and certifies
  every deletion COMMENT-ONLY.
- `safe` wins over `aggressive` and `strip`; `./aggressive` and `./strip` resolve as paths.
- The staged block carries an `Intentional-removal:` line when the target repository's own scripts
  or CI reference that trailer, and the optional `--notes <path>` appends
  the block to an untracked or out-of-repo file and refuses a tracked path.
- IF an `aggressive` or `strip` run targets already-committed code, THEN removals apply and the
  report names the next commit touching that code as the block's landing place, as `strict` does
  today.
- IF a scoped file is UNPROVABLE against itself, THEN the run names it before the census and every
  edit in it is a proposal.
- WHILE the run is non-interactive on a widened rung, it runs in safe mode whatever the posture.
- The "posture ladder only descends" wording is replaced in `SKILL.md`, `reference/safety.md`,
  `README.md`, and the `plugin.json` option description, and the tier lists in `safety.md` and
  `dissolving-moves.md` agree.
- A `claude plugin eval` suite under `plugins/code-tidying/evals/` runs in WSL2 with `--scaffold`
  and `--allow-tools Edit Bash Write`, covering the three frozen real sections, a minimal
  `lib/hook-utils.sh` excerpt that is UNPROVABLE (the whole file run once and recorded), one
  invented case per triage class, and the `aggressive`/`strip`/`safe` interactions, each graded on
  file contents.
- Expected outputs for every calibration case are written with the owner, one section at a time,
  before the suite's scores are read as a verdict.

### Captured assumptions

- WSL2 distro `Ubuntu-26.04` stays the eval host; it has `claude` 2.1.270, `bwrap`, and `socat`, and
  needs the CI-pinned pygments and tree-sitter wheels installed before the first run.
- `claude plugin eval` graders on `{ source: file, path }` read post-edit contents of a scaffolded
  file; this is documented but unprobed, and the first case run confirms it.
- The with-arm can execute the skill's `${CLAUDE_SKILL_DIR}/scripts/*` wrappers; unprobed, confirmed
  by the first case run.
- Unwanted-behaviour and state-driven coverage were examined: the IF and WHILE criteria above.

### Out-of-scope

- A separate command for destructive comment removal; `strip` keeps the exempt-surface floor.
- New proof tooling for tier-2 moves; they stay behind a test net.
- A tree-sitter-bash grammar fix for base-N arithmetic.
- Running the dial across this repository; calibration comes first.

### Deferred questions

- Q7 Which side of the Martin versus Ousterhout split `aggressive` takes on internal-interface
  comments that are not on the exempt list. arbiter: /planning:plan
- Q8 Whether `evals.json` validation follows skill-creator's `expectations` or `assertions` field
  name. arbiter: /planning:plan
- Q9 Under `aggressive`, whether a tier-2 move with no discovered test net applies as a labelled
  unproven edit instead of a proposal. This is a risk-appetite call: the Brief defaults to proposal,
  which means that on this repository's shell scripts (no covering net, a net over the 600-second
  tool cap, or an UNPROVABLE file) `aggressive` deletes rationale and proposes the rewrites.
  arbiter: USER-RESERVED

## Plan

### Goal

Ship `aggressive` and `strip` in `/code-tidying:dissolve-comments` 0.20.0 and a `claude plugin eval`
suite whose expected outputs the owner wrote, with the suite passing in WSL2. Design:
[design/design-resolution.md](design/design-resolution.md) (Tier B early-exit, argument grammar
and mode table).

### Resolved deferred questions

- **Q7 (arbiter /planning:plan, owner agreed).** `aggressive` takes Martin's side on
  internal-interface comments: a non-exempt comment describing a private function's contract is
  deleted with its narrative staged. Public-API doc comments stay exempt under the
  leading-underscore rule. Basis: the owner asked for "ALL or most ALL comments" removed, and Q1
  keeps only the exempt surfaces and load-bearing warnings.
- **Q8 (arbiter /planning:plan, owner agreed).** New `evals.json` entries use `expectations`.
  Basis: all 15 existing entries use it, and `plugins/skill-quality/scripts/check-evals-quality.sh`
  treats `expectations` and `assertions` as equivalent and warns when a case carries both.
- **Q9 (USER-RESERVED, owner agreed to the default).** A tier-2 move with no discovered test net is
  a proposal.

### Brief amendments (owner approved 2026-09-14, applied to the Brief)

Stress-test findings that changed a Brief line.

1. **Whole-file case becomes a recorded manual run.** The suite's UNPROVABLE case uses the smallest
   `lib/hook-utils.sh` excerpt that still exits 21 from `change-shape.sh` (a function using
   `10#$var`); the whole 4,086-line file is run once with `--runs 1` and its result recorded in this
   file. Basis: an UNPROVABLE file still gets full triage and a `git log -L` per rationale comment
   (`SKILL.md:187-214`), 3 runs times up to 1,800 s each, and the fixture would ship inside the
   plugin.
2. **`Intentional-removal:` only where the target repository reads it.** The staged block carries
   that line when the target repository's own scripts or CI reference the trailer (a grep over the
   repository), and omits it otherwise. Basis: it is this repository's own trailer
   (`scripts/check-silent-revert.sh:445`), and `code-tidying` is installed in other repositories.
3. **Paired records survive every mode.** A comment that is one half of a comment-plus-regression-
   test pair is kept under `aggressive` and `strip`. Basis: `reference/safety.md:224-227` calls
   deleting half a paired record a correctness bug, which no mode may loosen under "no knob loosens a
   gate".
4. **The eval grant adds `Write`.** `--allow-tools Edit Bash Write`, because `--notes` creates a
   file and `Edit` cannot create one (`case-authoring.md:82`).

### Standards grounding

Loaded for the surfaces touched: `.claude/rules/skill-bodies-state-current-rules.md` (verification
records, `## Next` placement before `## Gotchas`), `.claude/rules/pr-body-contract.md`, root
`AGENTS.md` (draft PRs), `plugins/evals/skills/plugin-eval/SKILL.md` and
`reference/case-authoring.md`, `reference/reading-results.md` (case layout, graders, sandbox,
results JSON), `docs/specs/plugin-evals-pilot-measurement.md` (with-arm cannot read spokes). No
consumer standards index beyond these.

### Test strategy

The skill is prose, so its tests are eval cases, written red first.

- **Boundary driven:** the existing public interface, the invocation
  `/code-tidying:dissolve-comments [tokens] <target>`, run through `claude plugin eval` against the
  working-tree plugin at `plugins/code-tidying`. No new interface is introduced for testability.
- **Red:** Phase 2 runs the suite against the unchanged skill. Each case lists its expected-red
  graders (the ones encoding behavior new to `aggressive` or `strip`); graders encoding today's
  behavior (class-A deletion, exempt surfaces) are expected to pass red and are recorded as such.
- **Green:** Phase 4 re-runs the suite after the Phase 3 skill change with `--threshold 0.8`.
- **Graders per case:**
  - survivors: `regex` `contains` on `{ source: file, path }`, anchored to comment syntax around an
    owner-chosen key phrase (`#[^\n]*<phrase>`), so a terser rewrite of a kept warning still passes;
  - deletions: `regex` `not_contains` on the same anchored form;
  - code preserved: one `regex` `contains` per non-comment code line, or a `count:N` over them, so
    deleted or rewritten code fails the case (for `strip`, "rewrites no code");
  - process: `tool_used` on `Bash` with `input_match: change-shape`, `arm: both`, so a run that skips
    the proof scores lower;
  - UNPROVABLE case: `tool_order` with `change-shape` before `comment-census`.
- **Delta caveat:** in the without-arm the slash command does not resolve, so the delta partly
  measures whether the command exists. Read pass rates in the with-arm as the calibration verdict.
- **Static checks in CI:** `check-evals-quality.sh` over `evals.json`, `sync-plugin-options-docs.py
  --check`, `allowed-tools-pairing.test.sh`, `check-purged-em-dashes.sh`. The paid suite does not
  run in CI.

### Phase 1: Eval harness tracer in WSL2 [DONE]

Proves the runner mechanics every later phase depends on, against the unchanged skill. All WSL2
commands run in the main checkout at `/mnt/d/repos/github.com/melodic-software/claude-code-plugins`
on the task branch, never in a worktree, because WSL git cannot read a worktree `.git` file that
holds a `D:/` path. `$TEMP` is unset in WSL2; WSL2 commands use `${TMPDIR:-/tmp}`.

1. Create branch `feat/dissolve-comments-aggressive-dial` from `main`; commit `PLAN.md` and
   `design/design-resolution.md`.
2. WSL2 tooling `[EXEC-SHAPE]`: `uv venv ~/.venvs/code-tidying --python 3.14` then `uv pip install
   --python ~/.venvs/code-tidying/bin/python --require-hashes -r .github/requirements-ci.txt`, and
   launch every `claude plugin eval` with `~/.venvs/code-tidying/bin` first on `PATH`. The skill
   wrappers exec `python3` from `PATH` (`skills/dissolve-comments/scripts/change-shape.sh:17`), and
   the distro's current `python3` is uv's CPython 3.14 at `~/.local/bin`.
3. Author `plugins/code-tidying/evals/probe-environment/case.yaml`: prompt `Run: command -v python3;
   python3 -c 'import pygments, tree_sitter, tree_sitter_bash'; command -v make; echo "$PATH"`,
   `execution: { allowed_tools: [Bash], max_turns: 5, timeout_seconds: 120 }`, graders `regex` on
   `trace` for `tree_sitter_bash` import success. No skill involved.
4. Author `plugins/code-tidying/evals/probe-explicit-target/`: `case.yaml` with
   `context.scaffold_script` that copies `fixture/app.sh.txt` (from `$(dirname "$0")`) to `app.sh`,
   runs `git init`, and commits with `-c user.name=eval -c user.email=eval@example.invalid` and a
   commit message carrying no rationale. `app.sh` holds one class-A comment `# increment counter`
   above `counter=$((counter + 1))` and one `# shellcheck disable=SC2034` directive. Prompt:
   `/code-tidying:dissolve-comments app.sh`. `execution: { allowed_tools: [Read, Glob, Grep, Skill,
   Bash, Edit, Write], max_turns: 80, timeout_seconds: 1200 }`. Graders per the test strategy.
5. Run both probes in WSL2: `claude plugin eval plugins/code-tidying --case 'probe-*' --scaffold
   --allow-tools Edit Bash Write --trust-plugin --runs 1 --ablation none --keep-temp --no-publish
   --json "${TMPDIR:-/tmp}/dc-probe.json"`. From the result and the kept traces, record in this file:
   the `python3` the run resolved and whether the imports succeeded; whether the slash invocation
   fired the skill; whether `change-shape.sh` executed or was denied; whether the file-content
   graders read the post-edit file; whether the scaffold resolved its own directory.
6. **Stop conditions** `[FALLBACK — confirm or override]`:
   - the run cannot import the wheels, or `change-shape.sh` is denied in the with-arm: stop, record
     the evidence here, and return to `/planning:plan review` before Phase 2;
   - the slash invocation does not fire the skill: prompts become `Use the Skill tool with skill
     code-tidying:dissolve-comments and args "<tokens> <target>"`, which keeps token parsing;
   - the scaffold cannot resolve its own directory: each scaffold embeds its fixture as a quoted
     heredoc.

**Phase 1 record (2026-09-14):**

- Wheels installed into `~/.venvs/code-tidying` with `uv pip install --require-hashes`; imports of
  pygments, tree_sitter, tree_sitter_bash, tree_sitter_python, tree_sitter_toml succeed.
- First eval attempt refused every Bash-granting run before turn 1: `~/.docker` in the distro holds
  two symlinks into `/mnt/c/Users/.../.docker` (Docker Desktop WSL integration), and the sandbox
  refuses a credential store containing a link. `DOCKER_CONFIG` pointing at a plain directory did
  not clear it.
- Workaround, no change to the owner's files: run `claude plugin eval` with
  `HOME=/var/tmp/dc-evalhome`, a directory holding only symlinks to `~/.claude`, `~/.claude.json`,
  and `~/.config`. Every WSL2 eval command in this plan runs that way. WSL2 scratch paths use
  `/var/tmp`, because this repository's drive-root temp guard rejects `/tmp` in a command string.
- `probe-environment` passed under that HOME (2 turns, 0.17 USD): the sandboxed Bash resolved a
  `python3` that imports the wheels.
- `probe-explicit-target` passed 4 of 4 graders (15 turns, 107 s, 0.54 USD). Confirmed from the
  trace and the kept workspace: the slash invocation fired the skill; `change-shape.sh` executed in
  the with-arm with tree-sitter and returned `COMMENT-ONLY`; `comment-census.sh` ran; the
  `{ source: file }` graders read the post-edit `app.sh` (the class-A comment present at scaffold
  time was absent); the scaffold resolved its own directory and copied the fixture, so the heredoc
  fallback is not needed and was removed. No stop condition fired.
- Sanity results: `validate-cases.py` exit 0 (WARN lines only, for tools granted by
  `--allow-tools`); the grader `jq` check printed `true`.

**Sanity Check:**

- `python3 plugins/evals/skills/validate/scripts/validate-cases.py plugins/code-tidying/evals` exits 0.
- `jq '[.cases[].arms.with[0].graders[] | .passed] | all' /var/tmp/dc-probe.json` prints
  `true`, or this file records the failing grader and the stop condition taken.
- `git log --oneline main..HEAD -- docs/topics/dissolve-comments-aggressive-dial/PLAN.md` lists at
  least one commit.

### Phase 2: Expected outputs with the owner, then the red run [DONE]

Main session, interactive, one fixture per round. Fixtures are committed with a `.txt` suffix
(`app.sh.txt`, `mod.py.txt`) and renamed by the scaffold, so CI shellcheck, ruff, and the
comment-hygiene scan do not lint deliberately commented fixtures.

1. Freeze the real sections at commit `0a676a578` as fixture copies, each a self-parsing block:
   `plugins/rate-limit-guard/scripts/statusline-tee.sh` lines 308-324 (`_rlg_read_stamp` and its
   header comment); the `WHY BLAME-OF-DELETED-LINES, AND NOT THE ALTERNATIVES` comment block in
   `scripts/check-silent-revert.sh` with the function that follows it; the `lib/hook-utils.sh`
   header through its calling-convention block plus one helper, and separately the smallest
   `lib/hook-utils.sh` excerpt that exits 21 (amendment 1).
2. Baseline `[EXEC-SHAPE]`: `comment-census.sh --json` over each real fixture; record each file's
   comment-line count here as the before value.
3. Write invented fixtures:
   - class A: a restating comment and commented-out code;
   - class B: a magic literal and a vague local name, with a `Makefile` `test:` target the scaffold
     writes, so the skill's test-net discovery finds a net;
   - class C: a load-bearing warning, a rationale comment whose text is absent from git history, and
     a rationale comment the scaffold's commit message does repeat;
   - exempt surfaces: license header, `# noqa` with justification, `TODO(#12)`,
     `dissolve-comments-ignore`;
   - marker row: a repo-local marker file listing an identifier that a comment would otherwise
     rename;
   - Python: a private function with a docstring (expected proposal, not applied);
   - paired record: a comment paired with a regression test (amendment 3).
4. For each fixture, show it to the owner with the doctrine's prediction under `aggressive` and
   under `strip`; the owner marks every comment keep, delete, or dissolve and picks the key phrase
   each grader anchors on. Record the marks as graders plus `expected_outcome`, and list the case's
   expected-red graders in this file. `/planning:interview` round format.
5. Author the interaction and criterion cases on the class-C fixture unless noted:
   - `aggressive`, `strip`, `safe aggressive`, `safe strip` (both expect class-A deletions only);
   - `./aggressive` as a target (scaffold creates a directory named `aggressive`; expects it triaged
     as a path under the default posture);
   - `--notes notes/dc-notes.md` with `notes/` untracked: `file_exists` plus `regex` on `{ source:
     file, path: notes/dc-notes.md }` for the staged block;
   - `--notes` on a tracked path: expects a refusal in `last_message` and the file unchanged;
   - committed-code landing place: `last_message` regex for the next-commit landing statement;
   - WHILE criterion: scaffold with a clean tree and history, prompt `/code-tidying:dissolve-comments
     aggressive` with no target; expects no class-C deletion applied (safe mode);
   - the standing `comment_posture: aggressive` route goes to `evals.json`, because eval runs cannot
     set `userConfig`.
6. Cost gate: print the suite estimate per `plugins/evals/skills/plugin-eval/SKILL.md` "cost
   estimate"; the owner sets `--max-cost-usd` before the red run (user-approval gate).
7. Red run: full suite, `--runs 1`, against the unchanged skill. Record per case which graders
   passed and whether that matches its expected-red list.
8. Whole-file record (amendment 1): one `--runs 1` run on all of `lib/hook-utils.sh`; record the
   outcome, turns, and cost here.

**Phase 2 record:**

- Owner rule (round 1, applies to every mode and every case): a comment that is kept must be
  succinct, clear, and justified. Graders enforce it as no kept comment block longer than
  `class_c_max_lines` (2) plus a key phrase naming the consequence; Phase 3 writes the rule into
  `SKILL.md`.
- Shared fixtures live in `plugins/code-tidying/evals/fixtures/`, seeded by `fixtures/seed.sh`,
  which each case's one-line `scaffold.sh` calls.
- Round 1, `statusline-tee.sh` lines 308-324 (`real-statusline-stamp-aggressive`,
  `real-statusline-stamp-strip`):

  | Part | `aggressive` | `strip` |
  |---|---|---|
  | (a) contract: reads a stamp or 0 | delete, staged | delete, staged |
  | (b) arithmetic-injection warning | keep, at most 2 lines | delete, staged |
  | (c) single-reader rationale | delete, staged | delete, staged |
  | (d) builtins-only render-path constraint | delete, staged | delete, staged |

  Expected red on the unchanged skill: `aggressive` graders `contract-deleted`,
  `single-reader-rationale-deleted`, `render-path-deleted`; `strip` graders `no-comments-left`,
  `narrative-staged`.
- Round 2, `scripts/check-silent-revert.sh` lines 73-106 plus `die()` from lines 368-371
  (`real-silent-revert-design-aggressive`, `real-silent-revert-design-strip`): the heading, the
  three rejected designs, and the measured result are deleted and staged in both modes; the
  no-threshold warning is kept at most 2 lines under `aggressive` and deleted under `strip`. No
  sentence is a paired record. Expected red: `aggressive` `design-history-deleted`; `strip`
  `no-comments-left`, `narrative-staged`.
- Owner restatement (round 2): the default answer is delete, or refactor the code until the comment
  is unnecessary; every survivor must be justified in the report.
- Rounds 3-9, approved by the owner as one batch (2026-09-14), with the note that a kept line must be
  as succinct as the round-3 SSOT line (`# SSOT: edit lib/hook-utils.sh, then run
  scripts/sync-hook-utils.sh; CI rejects drifted copies.`):

  | # | Fixture | `aggressive` | `strip` |
  |---|---|---|---|
  | 3 | `lib/hook-utils.sh` lines 1-59 | keep the one-line SSOT warning and a one-line `_to` calling convention; delete the rest, including the `hook::is_enabled` comment | delete all but the `shellcheck shell=bash` directive |
  | 4 | class A: restating comment, commented-out code | delete | delete |
  | 5 | class B: `86400` literal, vague `n`, `Makefile` test net | `SECONDS_PER_DAY`, `display_name`, comments deleted | comments deleted, no code change |
  | 6 | class C: warning, rationale absent from history, rationale in the commit message, one class-A line | warning kept at most 2 lines; the rest deleted and staged; report names the next commit | delete all |
  | 7 | exempt: shebang, license, `# noqa` with reason, `TODO(#12)`, `dissolve-comments-ignore`, one rationale | exempt kept, rationale deleted | same |
  | 8 | marker-row identifier, private Python docstring, paired record | comment deleted and identifier never renamed; docstring proposed; paired record kept | same |
  | 9 | interactions on the class-C fixture: `safe aggressive`, `safe strip`, `./aggressive`, `--notes` untracked and tracked, non-interactive run with no target; UNPROVABLE `hook-utils.sh` excerpt | `safe` wins; `./aggressive` is a path; untracked notes written, tracked refused; no-target run is safe mode; UNPROVABLE named first, proposals only | same |

- Cases authored for rounds 3-9: 19 case directories and 15 fixtures, 25 cases in the suite with the
  probes. Verified: `validate-cases.py` exit 0; real fixtures byte-identical to their `0a676a578`
  slices; every `.sh.txt` fixture passes `bash -n` and self-certifies COMMENT-ONLY, except
  `hook-utils-unprovable.sh.txt` (`hook::resolve_read_timeout_to`, lines 1570-1593), which exits 21;
  both `.py.txt` fixtures compile and self-certify; the class-B test net passes under `make test` in
  WSL2; every comment-deletion `not_contains` grader matches the unedited fixture (red before);
  scaffolds pass shellcheck and carry mode 100755.
- Grader decisions: the succinct grader is `(^[ \t]*#(?!!| shellcheck )[^\n]*\n){3}` with `m`,
  because JS `\s` spans newlines and the approved hook-utils result is a directive plus two kept
  lines; `fork-cost-deleted` anchors on `CreateProcess|copy-on-write|forks a subshell` so a kept
  `_to` line may mention forks; `interaction-notes-tracked-refused` has no `proof-ran` grader,
  because a refusal before triage is a correct outcome.
- Baseline (`comment-census.sh --json`, before value): `hook-utils-header.sh` 46 of 59 lines are
  comment; `silent-revert-design.sh` 34 of 39; `statusline-stamp.sh` 8 of 17; 88 of 115 in total.
- Red run skipped on the owner's decision (2026-09-15): nearly every case reaches its behavior by an
  argument token the unchanged skill reads as a path, so the run would have re-measured a known
  outcome at 12 to 30 USD. The expected-red lists above stand as the record of what the unchanged
  skill does, and Phase 4's run is the first paid pass.
- The branch moved to the worktree `D:/worktrees/ccp-dissolve-dial` after another session switched
  the main checkout back to `main`. WSL2 eval commands run from
  `/mnt/d/worktrees/ccp-dissolve-dial`.

**Sanity Check:**

- `validate-cases.py plugins/code-tidying/evals` exits 0.
- `for c in plugins/code-tidying/evals/*/; do case "$c" in *probe-*) continue;; esac; grep -rqs
  "source: file" "$c" || echo "$c"; done` prints nothing.
- For each shell fixture `f` in `plugins/code-tidying/evals/*/fixture/*.sh.txt` other than
  `Makefile`-target test scripts, `bash -n "$f"` exits 0 and
  `plugins/code-tidying/skills/dissolve-comments/scripts/change-shape.sh "$f" "$f"` exits 0, except
  the UNPROVABLE excerpt, which exits 21. (Check whether `change-shape.py` maps `.txt`; if not, copy
  to a `.sh` name under `${TMPDIR:-/tmp}` first and record that in this command.)
- `git ls-files plugins/code-tidying/evals | grep -E '\.(sh|py|bash)$'` lists only scaffold scripts.
- Every case's expected-red list in this file matches its red-run record.

### Phase 3: Skill change [DONE]

1. Consumer and claim sweep first: `grep -rn "comment_posture\|only descends\|narrows\|widened\|loosen
   nothing\|ceiling\|of 15" plugins/code-tidying docs scripts`; record every hit and its disposition
   here before editing. Known hits: `SKILL.md:39-40, 88-92, 107`, `reference/safety.md:58-61`,
   `reference/triage.md:84-96`, `reference/scope.md:29-30`, `reference/dissolving-moves.md:57, 61`,
   `README.md:129-136`.
2. Per-mode treatment of the hub rules that `aggressive` and `strip` touch, written into
   `SKILL.md` so the with-arm sees them:

   | Rule | Where | `aggressive` | `strip` |
   |---|---|---|---|
   | Information moves into code before a class-B comment goes | `SKILL.md:114-117` | holds | exception: deleted with narrative staged |
   | Class B misread as A is the information-destroying failure | `SKILL.md:255-256`, `triage.md:43-44` | holds | narrative staged for every deletion |
   | Staging with no landing place is not a deletion licence | `safety.md:206-209` | holds (next commit is the landing place) | holds |
   | Paired comment-plus-regression-test record | `safety.md:224-227` | kept | kept |
   | Shape used at scale is proposed | `SKILL.md:140-141` | holds | holds |
   | SSOT copy never edited; source edit forcing consumer bumps proposed | `SKILL.md:165-169` | holds | holds |
   | Marker-row identifier never renamed | new, workflow step 2 | holds | not applicable (no renames) |
   | Exempt surfaces | `SKILL.md:125-130` | hold | hold |

3. `skills/dissolve-comments/SKILL.md`:
   - frontmatter `description` names `aggressive` and `strip`; `argument-hint` becomes
     `[safe] [aggressive|strip] [override] [--notes <path>] [target]`;
   - `allowed-tools` adds `Bash(git ls-files:*)` `[EXEC-SHAPE]` for the tracked-path refusal;
   - Variables: posture accepts `aggressive`;
   - action router rows for `aggressive [target]`, `strip [target]`, `--notes <path>`, and the
     precedence from the design resolution;
   - the "posture ladder only descends" paragraph becomes "no knob loosens a gate", the survivor
     list (exempt surfaces, load-bearing warnings within `class_c_max_lines`, paired records), and
     the gate statement;
   - triage table and workflow steps 1, 2, 6, and 7 carry the `aggressive` and `strip` branches,
     the table in item 2, the conditional `Intentional-removal:` line (amendment 2), and the Python
     docstring ceiling;
   - doubt rule `[EXEC-SHAPE]`: under `aggressive`, doubt between A and B resolves to B, and doubt
     between B and C resolves to B (dissolve when the gate passes, else keep with a proposal); under
     `strip`, every doubted deletion stages its narrative; under both, doubt whether a comment is an
     exempt surface, a load-bearing warning, or a paired record keeps it;
   - "What this skill is NOT" first bullet names `strip` and its exempt-surface floor;
   - `## Next` naming `/source-control:commit`, placed before `## Gotchas`.
4. `reference/safety.md`: mode ladder rows for `aggressive` and `strip`; the knob paragraph at lines
   58-61; the staging section gains the conditional `Intentional-removal:` line and `--notes`; tier
   table reconciled with `reference/dissolving-moves.md` `[EXEC-SHAPE]` to the union of both, tier
   by tier (tier 2 adds Replace Nested Conditional with Guard Clauses and Introduce Special Case;
   tier 3 adds Inline Function; `dissolving-moves.md` tier 3 adds Extract Class).
5. The "of 15" counts at `SKILL.md:107` and `reference/dissolving-moves.md:57, 61` are recounted
   against the merged tables.
6. `reference/triage.md:84-96` and `reference/scope.md:29-30` name the new modes.
7. `plugin.json`: `comment_posture` description names `aggressive`; top-level description names
   `strip`; version `0.20.0`. Then `python3 scripts/sync-plugin-options-docs.py` regenerates the
   README options block; hand-edit `README.md:129-136`.
8. `CHANGELOG.md` `## [0.20.0]` entry.
9. `evals/evals.json`: entries 16 (`aggressive-deletes-non-exempt-rationale-with-staging`), 17
   (`strip-keeps-exempt-surfaces-and-rewrites-nothing`), 18
   (`standing-aggressive-posture-yields-to-safe`), each `narration: true` with `expectations`.

**Phase 3 record:**

- Item 1 sweep (run before the red run; read-only). Hits to edit: `plugin.json:30`
  (`comment_posture`), `README.md:129, 136, 160`, `SKILL.md:39, 88, 107, 152`,
  `reference/triage.md:95`, `reference/scope.md:30`, `reference/dissolving-moves.md:57, 61`. Hits
  kept as they are: `CHANGELOG.md` history entries; `evals/evals.json:151, 163` (posture narration
  cases, still valid); every hit outside `plugins/code-tidying/skills/dissolve-comments`,
  `README.md`, and `plugin.json` uses "narrows" or "widened" in an unrelated sense.
- Edits landed: `SKILL.md` (dial rows, `--notes`, survivor list, no-knob-loosens-a-gate wording,
  doubt rule, paired-record and marker-row rules, docstring ceiling, per-mode branches in steps 1,
  5, 6 and 7, `## Next`), `reference/safety.md` (mode-ladder rows, knob paragraph, staging section,
  tier table), `reference/dissolving-moves.md` (tier table, counts), `reference/triage.md`,
  `reference/scope.md`, `plugin.json` (posture value, description, 0.20.0), `README.md` (regenerated
  options block plus hand-written prose), `CHANGELOG.md`, `evals/evals.json` (entries 16 to 18),
  `docs/catalog.md` (regenerated).
- The skill's `description` was over the 1024-codepoint Agent Skills maximum once the dials were
  named (1199), and was on `main` at 978 with only 46 codepoints of headroom. It is now 1016 with
  every base trigger phrase preserved; `check-skill` warns that the next added clause breaches the
  limit.
- Gates: `check-skill` PASS (1 warning, the headroom note), `sync-plugin-options-docs.py --check`
  exit 0, `check-evals-quality.sh` PASS, `allowed-tools-pairing.test.sh` exit 0,
  `check-purged-em-dashes.sh` exit 0, tier tables agree tier by tier.

**Sanity Check:**

- `grep -rn "only descends" plugins/code-tidying --exclude=CHANGELOG.md` prints nothing (the
  changelog quotes the retired wording on purpose), and every hit recorded in item 1
  has a disposition line in this file.
- `grep -n '^## ' plugins/code-tidying/skills/dissolve-comments/SKILL.md` shows `## Next`
  immediately before `## Gotchas`.
- Tier tables match tier by tier. With `d=plugins/code-tidying/skills/dissolve-comments/reference`
  and `p='Rename Variable|Rename Field|Extract Variable|Replace Magic Literal|Introduce Assertion|Slide Statements|Decompose Conditional|Replace Nested Conditional with Guard Clauses|Introduce Special Case|Extract Function|Change Function Declaration|Extract Class|Introduce Parameter Object|Move Statements into Function|Replace Inline Code with Function Call|Inline Function'`,
  `for t in 1 2 3; do diff <(grep -E "^\| \*\*$t\*\*" $d/safety.md | cut -d'|' -f3 | grep -oE "$p" | sort -u) <(grep -E "^\| $t," $d/dissolving-moves.md | cut -d'|' -f3 | grep -oE "$p" | sort -u) || echo "tier $t differs"; done`
  prints nothing. On `main` today it prints tier 2 and tier 3 differences (run 2026-09-14).
- `python3 scripts/sync-plugin-options-docs.py --check`, `bash
  plugins/skill-quality/scripts/check-evals-quality.sh
  plugins/code-tidying/skills/dissolve-comments/evals/evals.json`, `bash
  plugins/code-tidying/scripts/allowed-tools-pairing.test.sh`, and `scripts/check-purged-em-dashes.sh`
  each exit 0.
- `jq -r .version plugins/code-tidying/.claude-plugin/plugin.json` prints `0.20.0`.

### Phase 4: Green run, calibration loop, PR [DOING]

**Pass 1 record (2026-09-15, `--runs 1 --ablation none --max-cost-usd 20`, 20.16 USD):** 21 of 23
cases ran before the ceiling stopped the run; 17 passed, overall score 0.92. The two
`real-statusline-stamp-*` cases never started.

Causes, classified from the traces and the kept workspaces:

| Case | Grader | Cause | Fix |
|---|---|---|---|
| `invented-class-c-aggressive` | `timeout-rationale-deleted` | skill wording: "warning of consequence" was undefined, and the load-balancer rationale read as both a warning and a boundary-semantics exempt surface | `SKILL.md` defines the term and excludes the reason a value was chosen |
| `invented-class-c-strip` | `no-comments-left` | same, plus the exempt bullet covered whole sentences | `safety.md` and `SKILL.md` narrow units, sentinels, ownership, thread-safety and ordering to annotations on the adjacent declaration |
| `real-hook-utils-header-aggressive` | `kept-comment-succinct`, `code-intact` | the run relocated a kept comment and wrote a new one, which no rule forbade | `SKILL.md` step 6 adds: a kept comment stays where it is and keeps its own words |
| `interaction-non-interactive-no-target` | `safe-mode-named`, `proof-ran` | the skill had no way to detect a non-interactive session, and the scaffold's untracked files keep the ladder on the uncommitted rung | `SKILL.md` step 1 ties non-interactive to `AskUserQuestion` being unavailable; the case's own expectation is still open (below) |
| `invented-class-b-aggressive` | `magic-literal-named` | grader anchoring: the run named the constant `seconds_per_day`, correct shell style for a `local` | pattern lowercased with `flags: i` |
| `invented-class-c-aggressive` | `no-intentional-removal-trailer` | grader anchoring: the report said it emitted no such trailer, and the bare token matched that sentence | pattern anchored to line start with `flags: m` |
| `real-silent-revert-design-strip` | `narrative-staged` | not a defect: the judge was skipped when the cost ceiling hit | re-run under a higher ceiling |

Grader changes and their reasons (anchoring only, per the phase rule): the three above, plus three
deletion anchors in `real-hook-utils-header-aggressive` (`description-deleted`,
`kill-switch-comment-deleted`, `is-enabled-comment-deleted`) widened to catch a reworded keep. They
had passed while the comment was kept in different words, which is a false pass.

**Open for the owner:** `interaction-non-interactive-no-target` cannot exercise the widened-rung
rule as written, because any untracked file (the harness writes `.claude/`) keeps the scope ladder
on the uncommitted rung with `files=0`, where the doctrine correctly stops. Either the case's
expectation narrows to the new non-interactive statement, or `scope-code-files.sh` changes to
advance on a rung with no code files, which is a script change this plan put out of scope.

**Pass 2 and the follow-ups (2026-09-15, ~12.3 USD total across passes 2 to 5):** 7 of 8 re-run
cases passed at `--runs 1`. `real-hook-utils-header-aggressive` took three rounds:

- the run treated the shell header block as an exempt public-API doc comment, so that exemption now
  names the language's structured doc-comment form and says a language without one (shell, make) has
  no exempt surface there;
- it kept a note explaining why a sibling helper exists, so a warning now has to address its own
  declaration's caller;
- the succinct-keep grader counted a `#` spacer between two two-line keeps as one oversized block,
  and now counts comment lines with content;
- the case's own expectation changed with the owner's agreement: the kill switch's required
  placement is a keep, because a required call order is what the doctrine defines a warning to be.
  The original round-3 call predates that definition.

Final scores: `real-hook-utils-header-aggressive` 0.93, `real-hook-utils-header-strip` 1.00,
everything else at 1.00 except `invented-class-c-aggressive` 0.90 (its landing-place line). Two
grader anchors were widened after a keep collided with a deletion check; both are logged above.

### Phase 4 remaining work [DONE]

The owner ended the calibration loop here and sent the work to a pull request: every case passed on
the final wording, case by case, at `--runs 1`. A single whole-suite confirmation pass on that
wording (~20 USD) was offered and declined, so no run has yet scored all 23 cases green in one
invocation. The measured comment-line deltas on the real fixtures under `aggressive`:
`hook-utils-header.sh` 46 to 4, `silent-revert-design.sh` 34 to 1, `statusline-stamp.sh` 8 to 1.

1. Run the full suite in WSL2 with `--runs 3 --threshold 0.8 --max-cost-usd <owner ceiling>`.
2. For each failing case, classify the cause from the `--keep-temp` trace before editing: a denied
   `reference/` read (the rule belongs in `SKILL.md`), doctrine wording, or grader anchoring. Fix the
   skill for the first two. A grader change is allowed only for anchoring (the key phrase or its
   comment-syntax anchor) or with the owner's agreement in session; log each grader change here with
   its reason.
3. Re-run `comment-census.sh --json` on each real fixture's post-run workspace and record comment
   lines before and after beside the Phase 2 baseline, distilled.
4. Commit, open a draft PR with the body contract (`No related issue: <reason>` or `Closes #`,
   Summary, Fix, Verification, Related), run the Phase 3 static checks plus
   `plugins/code-tidying/scripts/*.test.sh`, then mark ready.

**Sanity Check:**

- The suite command in item 1 exits 0.
- `gh pr view --json isDraft,body -q '.isDraft, (.body | test("## Verification"))'` prints `false`
  and `true` after the flip.

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| WSL2 wheels go into a uv venv put first on `PATH` | Phase 1 item 2; no system-wide install, no sudo | WSL2 `python3` is uv CPython 3.14 at `~/.local/bin`; `/usr/bin/python3` has no pip (probed); wrappers exec `python3` from `PATH` |
| Probe failures stop the work and return to planning; a slash-command failure switches prompts to an explicit Skill-tool instruction; an unresolvable scaffold directory switches fixtures to heredocs | Phase 1 item 6 | Pilot record: with-arm reads under the plugin directory were denied (`docs/specs/plugin-evals-pilot-measurement.md`) |
| Doubt under `aggressive` resolves A/B and B/C to B; under `strip` every doubted deletion stages narrative; doubt about exempt, warning, or paired record keeps | Phase 3 item 3, `SKILL.md` doubt paragraph | Brief AC: class B kept with a proposal when its gate fails; `SKILL.md:255-256` B-misread-as-A is the information-destroying failure |
| Tier tables merge to the union, tier by tier | Phase 3 item 4; `safety.md` gains three moves, `dissolving-moves.md` gains Extract Class | Tier comparison command output above (tier 2 and 3 differ today) |
| `Bash(git ls-files:*)` added to the skill's `allowed-tools` | Phase 3 item 3 | `--notes` must refuse a tracked path; `git ls-files --error-unmatch` answers that |
| `## Next` names `/source-control:commit`, before `## Gotchas` | Phase 3 item 3 | `.claude/rules/skill-bodies-state-current-rules.md`; the staged block is that skill's input (`SKILL.md:116`) |
| Fixtures committed with a `.txt` suffix | Phase 2 preamble | CI shellcheck lints changed `*.sh` (`ci.yml:381-386`); comment-hygiene scan excludes only audit-comment-residue |
| Baseline is a census over the real fixtures | Phase 2 item 2 | Brief goal is a measured comment-line count |
| Sequential, main-session execution | Execution shape | Phase 2 and 4 need the owner; Phase 3 files interlock |

## Blast radius

MEDIUM. One plugin, about 12 tracked files plus the new eval suite, reversible by revert. It still
triggers a stress-test: the change rewrites agent instructions for a skill that deletes text, and
it reverses a documented invariant.

## Stress-test summary

Two fresh-context reviewers ran on the first draft: a plan reviewer (1 critical, 13 important, 4
suggestions) and `/planning:devils-advocate` (1 critical, 5 high, 6 medium, 2 low). Findings were
checked against the files before applying. Confirmed and applied:

- Hub rules left contradicting `strip` and `aggressive` now have a per-mode table (Phase 3 item 2).
- The doubt rule names which class wins.
- `$TEMP` is unset in WSL2 (probed); the notes case moved into the workspace with a `Write` grant.
- The sudo fallback was dropped. WSL2 `python3` is uv's CPython at `~/.local/bin` (probed); a uv
  venv plus an environment probe case replaces it.
- A denied script in the with-arm is a hard stop (the pilot recorded denied plugin-directory reads).
- Code-preservation graders were added and the proof grader set to `arm: both`.
- The red run lists expected-red graders per case.
- Graders anchor on key phrases.
- The whole-file case became a manual record (amendment 1), and a cost gate precedes the red run.
- Each uncovered acceptance criterion got a case.
- Fixtures carry a `.txt` suffix.
- A slash-command fallback was added.
- `case.yaml` uses `execution:` nesting.
- The results `jq` path was corrected.
- Repo-relative script paths were fixed.
- The baseline moved to Phase 2.
- A Makefile test net was added (`make` present in WSL2, `bats` absent).
- The claim sweep was widened.
- The "of 15" counts were added.
- The `## Next` order check was added.
- `Intentional-removal:` became conditional (amendment 2).
- WSL runs use the main checkout.

Brief AC line 46 was corrected to match Q1 (load-bearing warnings kept).

## Execution shape

Fully sequential, all main session. Phase 1 gates Phase 2 (runner mechanics), Phase 2 gates Phase 3
(red cases exist first), Phase 3 gates Phase 4. Phase 2 is an owner interview and Phase 4 a
calibration loop, so neither suits parallel workers, and Phase 3's files interlock (hub rules,
references, tier tables).

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | WSL2 probing with stop conditions that re-plan |
| 2 | main session | owner marks every expected output |
| 3 | main session | interlocking prose edits to one skill |
| 4 | main session | failure classification and owner-gated grader changes |

## Open questions

None. Plan and Brief amendments approved by the owner 2026-09-14.

## Handoff to implementation

### User-approval gates

- Phase 1 item 6: a stop condition returns to `/planning:plan review`.
- Phase 2 item 4: every expected output is the owner's call, one fixture per round.
- Phase 2 item 6 and Phase 4 item 1: the owner sets the cost ceiling before each paid run.
- Phase 4 item 2: any grader change beyond anchoring needs the owner's agreement.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, main session, per the table above. Sanity Checks per phase as written.

### Mechanical work

- One commit per phase; `PLAN.md` phase tags and records ride each phase's commit.
- Version bump and CHANGELOG land in Phase 3's commit.
- Commit messages via heredoc with the attribution trailer; PR opened as a draft.
