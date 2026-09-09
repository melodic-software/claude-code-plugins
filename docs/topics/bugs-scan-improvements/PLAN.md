# bugs-scan-improvements

## Brief

### TLDR

- `/bugs:scan` sizes itself by stage and scope: hunters on `sonnet`, gates on `opus`, lens count and gate cap from the resolved scope size, `${CLAUDE_EFFORT}` as the ceiling.
- A filing ladder replaces blanket filing: interactive and local findings are fixed inline; unattended, non-local, or security-relevant findings are filed.
- Rotation becomes reproducible and durable: exact-match rung-1 search, the sampled scope list in the cursor block, a cloud note that `--track` is the durable path, and the report gains "Candidates not gated" and "Side observations" sections.
- This repository declares concrete lanes and `filing_posture: allowed` in `.claude/bugs.md`.
- The three findings from the 2026-09-08 dogfood run are fixed in the same PR, each with a regression test.

### Goal

A `/bugs:scan` run costs tokens in proportion to what it scans and never drops precision to save them; a second run on the same lane reads the same files; a cloud run leaves something durable behind; and a small verified finding gets fixed instead of filed. One PR carries the plugin change, this repository's lane config, and the three fixes, and closes one umbrella Task issue.

### Constraints

- Solutions are consistent, uniform, and not over-engineered: one sizing rule, one filing ladder, stated once in the skill body.
- Subagents never run the session's top model; `opus` is the default, `sonnet` for the recall stage.
- The verification gate's stance ("if uncertain, it is NOT a finding") and the 10-per-wave cap do not relax at any size.
- Skill bodies state the current rule and its reason, never the incident or model that motivated it (`.claude/rules/skill-bodies-state-current-rules.md`).
- Plugin edits follow the marketplace conventions: semver bump plus a changelog entry per touched plugin; hook-budget rule for any hook change; `/ai-slop:audit` house style for prose.
- Everything filed in this session is completed in this session, in a single PR on `claude/bug-scan-nc4ew8`.

### Acceptance criteria

- The scan skill body states the sizing rule: hunters dispatch on `sonnet`, gates on `opus`, the main thread stays on the session model; small scope (5 files or 1,000 lines or fewer) dispatches 1 to 2 lenses with a gate cap of 5, medium (20 files or 5,000 lines or fewer) 2 to 3 lenses with a cap of 10, large 4 lenses with a cap of 10 and refill waves; `${CLAUDE_EFFORT}` remains the ceiling on lenses and refills.
- The scan skill body adds a main-thread pre-gate triage step that merges same-cause candidates and drops candidates whose stated impact is cosmetic, before any gate dispatch.
- The scan skill body states the filing ladder: an interactive run fixes a local finding inline (one plugin, no documented contract change, an existing test file to extend); an unattended run, a non-local finding, or a security-relevant finding is filed with the provenance line.
- WHILE a run is unattended, verified findings are filed, never fixed inline.
- IF the rung-1 tracker search is not an exact match on the provenance line, THEN the run falls through to rung 2 and prints the reason.
- A hunter may follow one hop (a direct caller or callee of a scoped file) and tags such a candidate `out-of-lane`; the report and cursor count it under that tag.
- The persisted report's cursor block carries the sampled scope list, and the report format adds "Candidates not gated" and "Side observations" sections between the refuted tail and the cursor block; cursor block keys stay unchanged.
- The scan skill body says a cloud or scheduled run passes `--track` because filing is the only output that survives the container, and that persistence uses the Write tool.
- `.claude/bugs.md` in this repository declares five lanes with concrete globs and `filing_posture: allowed`; `/bugs:setup check` reads it clean.
- `plugins/claude-ops/hooks/session-event-log.sh` rejects a `stdin_read_timeout` of zero (and the sub-floor and Bash-3 fractional cases the library rejects) by falling back to the default, with a test in its `.test.sh`.
- `plugins/claude-config/lib/state-key.sh` keys a non-git directory by its physical path, so two spellings of one directory produce one key, with a test in its `.test.sh`.
- `plugins/guardrails/lib/verification/verify-cli-flag.sh` writes the help cache to a temporary path and renames it into place, with a test in its `.test.sh`.
- The bugs plugin is at 0.10.0 with a changelog entry; claude-ops, claude-config, and guardrails each carry a patch bump and a changelog line for their fix.
- `scripts/affected-tests.sh --run` passes for the change set.

### Captured assumptions

- The Agent tool's `model` parameter accepts `sonnet` and `opus` in every session that runs this skill; revisit if a host exposes a different tier set.
- The scope-size thresholds (5/1,000 and 20/5,000) are starting values chosen from this run's 23-file, 7,911-line lane; revisit after three rotation runs report their scope sizes.
- The five ungated candidates from the 2026-09-08 report stay in that report and are noted in the umbrella issue; revisit when the `config-and-startup` lane rotates back.
- No marketplace-wide subagent-tiering convention exists yet; this skill states its own rule in a form that can be lifted into one later. Revisit if a second skill adopts the same rule.

### Out-of-scope

- Per-candidate gate model selection by complexity.
- A filterable provenance label on the tracker.
- A report-delivery channel other than the tracker (PR comment, artifact).
- Gating or filing the five ungated candidates.
- A marketplace-wide convention document for subagent model tiers.

### Deferred questions

None.

## Plan

<empty — populated by /planning:plan>
