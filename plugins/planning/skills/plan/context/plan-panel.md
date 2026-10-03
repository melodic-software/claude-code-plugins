# Multi-angle plan panel (opt-in)

For a hard or wide plan, Step 2 can formulate through the saved `planning:plan-panel` workflow
instead of one draft: independent planners draft from distinct angles, independent judges score
the drafts against a rubric, and one agent synthesizes a plan from the winner, grafting the best
runner-up ideas. Everything after Step 2 is unchanged: the synthesized plan goes through the
Step 3 fresh-context plan-reviewer dispatch, blast radius, the Step 4.7 outcome gate and the
Step 5 approval gate like any other plan.

## When to take it

Take the panel only when one of these holds; otherwise formulate on the main thread as usual.

- The user asks for it ("plan this with a panel", "draft competing plans", "multi-angle plan").
- `/multi-agent:assess` resolves in this session and, given the planning task, returns
  `workflow`. Do not invoke it for a trivial or small plan (Step 2's scale table); the panel is
  for the medium and large rows where the solution space is wide.

## Availability gate

Before any launch, check whether the `Workflow` tool is in this session's toolset (listed or
loadable). A grant in this skill's frontmatter does not count. When it is absent, or availability
cannot be confirmed, take the main-thread fallback: formulate the single plan per Step 2 and say
in one line that the panel was unavailable and why. For the switches that turn workflows off, see
[Turn workflows off](https://code.claude.com/docs/en/workflows#turn-workflows-off) (as of
2026-10-02; recheck when a switch is added or renamed there).

## Launch

1. **Roles.** When `/multi-agent:route` resolves in this session, invoke it as
   `/multi-agent:route all session=<this session's model alias>` and keep the `roles` object of the
   JSON it prints. When it does not resolve, omit `roles` and say once that enabling the
   multi-agent plugin makes this routing configurable; the workflow's built-in fallbacks then
   apply.
2. **Launch** `Workflow({ name: "planning:plan-panel", args: { task, context, angles, roles, maxConcurrent } })`:
   - `task`: the task as Step 1 scoped it (required; a missing `task` returns
     `{ error: "missing-task" }` and runs nothing).
   - `context`: what the planners need that the code does not show: the Brief, the design
     resolution, the standards sections loaded above, and the exploration and research findings.
   - `angles`: optional, 2 to 6 strings or `{ name, focus }` objects; the defaults are
     MVP-first, risk-first, reuse-first and testability-first.
   - `judges`: optional judge count, 1 to 5 (default 3).
   - `maxConcurrent`: optional wave size (default 4).
3. **Read the result.** It returns `plan` (the synthesized plan, or the winning draft when
   `synthesized` is false), `winner`, `scores` (per draft: mean per rubric criterion and the
   total), `grafted` (idea and source draft), `dissent`, `nulls` and `roles`. An `error` return
   (`missing-task`, `no-drafts`, `no-judges`) means no synthesized plan exists: take the
   main-thread fallback, and on `no-judges` start from the returned drafts.

## Using the result

Shape the returned `plan` into the Step 2 template; it is a draft, not a finished plan. Carry the
runner-up drafts (`drafts`, each with its full `plan` and `key_ideas`) into "Alternatives
considered" with their switch conditions, and carry `dissent` into "Risks and mitigations" or the
Step 5 open items. Name every `nulls` entry in the Step 5 presentation, so a dropped angle or
judge is never read as full coverage; a judge that did not score every draft exactly once counts
as null.

Every agent in the run is told not to edit files or change state, but nothing enforces it: they
are generic workflow agents with the session's tools, and `task` and `context` reach their
prompts verbatim. Pass `context` you would hand a subagent with the same tools, summarize
untrusted fetched text rather than pasting it, and check `git status` after the run.

If a run is interrupted, relaunch `planning:plan-panel` with the same `args`. For which agents
return saved results on relaunch, see
[Resume after a pause](https://code.claude.com/docs/en/workflows#resume-after-a-pause) (as of
2026-10-02; recheck when the resume rules change).
