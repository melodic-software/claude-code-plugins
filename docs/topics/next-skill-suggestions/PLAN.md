# next-skill-suggestions

## Brief

### TLDR

- Add a presence-gated `## Next` section to 30 skills (Tier A 8, Tier B 22, listed in the
  interview's `CANDIDATES.md`) that today end with no successor named.
- The section is a plain mention of hardcoded successor skills. Never a Skill-tool chain, never
  a runtime lookup, never `/session-flow:show-options` or `/session-flow:workflow`.
- Two allowed shapes: one bare line, or two to four outcome bullets when the successor depends
  on the run's result.
- One advisory WARN in `skill-quality:check` for a stage-bearing skill missing the section.
- Three lines of authoring discipline in the existing skill-body rule so the successor graph
  stays current. No CI addition.

### Goal

A human running any of the 30 skills interactively sees, right after the work, which skill
normally runs next, named specifically and gated on the owning plugin being installed, at zero
runtime cost, in the same shape `performance:goal`, `performance:snapshot`, and
`performance:target` already use. The staged spine already routes; this closes the gap in the
skills that forgot to.

### Constraints

- Mention only. The invocation-mode convention's chaining section separates a mention from an
  operative chain; every `## Next` line stays a mention. No "invoke via the Skill tool" phrasing.
- No dynamic lookup. Router skills are REJECTED fleet-wide (`docs/conventions/invocation-mode/`),
  and ADR 0016 defers the Stop/TaskCompleted hook. Neither is reopened.
- Every cross-plugin token carries the seam-phrasing gate and fallback
  (`docs/conventions/seam-phrasing/`). Same-plugin tokens need no gate.
- Section placement: before `## What this skill does NOT do` or `## Gotchas`, whichever comes
  first, matching `performance:*`.
- Bodies state the current rule only (`.claude/rules/skill-bodies-state-current-rules.md`). No
  "added because the audit found" narration in any `## Next`.
- AFK drivers (`work-items:work-loop`, `work-items:work`, `source-control:babysit-loop`,
  `source-control:babysit-prs`, `implementation:implement-dispatch`,
  `session-flow:continue-in-background`) and `plugins/autonomy/hooks/lane-stop-gate.sh` are
  untouched.
- No new CI job, workflow, or script. The WARN lives inside the existing `check-skill.sh`.
- One worktree, one feature branch, one PR. Every touched plugin bumps its patch version and
  carries a CHANGELOG line.
- PR body follows `.claude/rules/pr-body-contract.md`; the PR opens as a draft per `AGENTS.md`.

### Acceptance criteria

- Each of the 30 skills in `CANDIDATES.md` Tier A and Tier B carries a `## Next` H2 placed before
  its `## What this skill does NOT do` or `## Gotchas` section.
- Every `/plugin:skill` token inside a `## Next` section resolves to an existing
  `plugins/<plugin>/skills/<skill>/SKILL.md` on the branch.
- Every cross-plugin token inside a `## Next` section carries an installed-ness gate and a stated
  fallback in the same or adjacent sentence.
- A `## Next` section is either one bare line or two to four bullets of the form
  `<outcome>: /plugin:skill (if that plugin is installed), else <fallback>`. Never more than four.
- No `## Next` section contains "Skill tool", "invoke", or any operative-chain phrasing.
- `check-skill.sh` emits a `WARN:` line for a fixture skill whose `workflow-stage` is one of
  explore, research, plan, implement, test, review, verify, pr, retro and that has no `## Next`
  H2, and emits none for a fixture at `anytime`, `operator`, `session`, `contract`, or no stage.
- `check-skill.sh` exits 0 on that WARN (advisory), and its existing test file covers the new
  case.
- `.claude/rules/skill-bodies-state-current-rules.md` carries three lines: new skill writes its
  `## Next` and updates the predecessor whose `## Next` should now name it; rename runs
  `/docs-hygiene:rename-references audit`; removal greps the token and edits each `## Next` that
  carried it.
- IF a `## Next` token names a skill that does not exist on the branch, THEN the PR review
  reports it and the PR does not merge until fixed. Enforced by the reviewer running the
  token-resolution grep in the PR's `## Verification` section, not by CI.
- Each touched plugin's `plugin.json` version is bumped and its `CHANGELOG.md` names the change.
- `scripts/affected-tests.sh --run` passes on the branch.

### Captured assumptions

- The 30-skill list in `CANDIDATES.md` is the scope. Revisit if a Tier B skill turns out to
  already carry a routing section the census missed.
- The specific successor per skill is chosen at implementation time from the skill's own
  boundary text and the routing tables of its siblings. Revisit if a skill has no defensible
  successor; drop it from scope and say so in the PR.
- `check-skill.sh` has a place to add one WARN alongside the existing "missing gotchas surface"
  check. Revisit if the script's structure makes that a larger change than a few lines.
- State-driven acceptance case: none applies. Unwanted-behaviour case captured above.

### Out-of-scope

- Any operative chain to `/session-flow:show-options` or `/session-flow:workflow`.
- Extending `lane-stop-gate.sh` or any AFK driver.
- A CI check that resolves `/plugin:skill` tokens repo-wide.
- Rewriting the 59 existing routing tables or the staged-spine skills.
- Amending ADR 0016. Nothing new cites `show-options`, so its text stays as is.
- Pocock-lineage skills already routing or terminal by design (25 of 28).

### Deferred questions

- None.

## Plan

<empty — populated by /planning:plan>
