# review

Turn what went wrong in the last step into filed issues. Nothing is filed without the user's
approval. `W` is `.work/repo-sweep/` in the worktree root (create it when filing).

1. Ask the user what went wrong in the last step: wrong findings, missed findings, a skill that
   ignored its override, a confusing prompt, a catalog entry in the wrong place or with the wrong
   arguments. Record their answer as given. Add only the `guard.sh` stop lines the step printed,
   quoted from `W` or the PR checklist; add nothing you observed yourself, so the session that ran
   the step does not grade its own work.
2. Dispatch a separate reviewer agent (Task tool or subagent). It must not be the session that
   ran the step. Give it only:
   - repo-sweep procedure files (`reference/next.md`, this file, the step skill's SKILL.md and
     references it used),
   - the step's artifacts (`.work/repo-sweep/`, the PR checklist line for that step, `git diff`
     from the step base or the absence of a diff),
   - and the user's complaints from step 1.

   Never give it the executing agent's reasoning, tool transcript, or chat history. It returns a
   problem list, each problem in one of four classes: skill defect, catalog defect,
   executing-agent error, harness issue.
3. Merge the reviewer's list with the user's report.
4. Sort each problem by class:
   - Skill defect: invoke `/plugin-quality:audit` via the Skill tool on that skill, passing the
     problem as the evidence. Draft an issue against the plugin that owns the skill.
   - Catalog defect (order, membership, arguments, applies-when, override text): draft an issue
     against `melodic-software/claude-code-plugins` for the `playbooks` plugin's repo-sweep
     catalog. Keep it separate from skill defects.
   - Executing-agent error: report it to the user and file nothing. When it traces to unclear
     repo-sweep procedure text (its SKILL.md, reference files, or scripts), it is a repo-sweep
     defect instead: invoke `/plugin-quality:audit` via the Skill tool on `playbooks:repo-sweep`,
     passing the problem as the evidence, and draft an issue against
     `melodic-software/claude-code-plugins` for the `playbooks` plugin, separate from catalog
     defects.
   - Harness issue: report it to the user and file nothing here. A Claude Code defect goes to
     `/bug`, as below.

   A defect in a skill bundled with Claude Code (a bare name in the catalog, such as `claude-api`)
   has no plugin here to file against: ask the user to report it to Anthropic with `/bug`
   ([commands](https://code.claude.com/docs/en/commands), fetched 2026-09-27; recheck when that
   page drops or renames `/bug`).
5. Show every draft (title, body, target repository). For each approved draft, write the body to
   a file under `W` (for example `W/issue-<slug>.md`) and file with `gh issue create ... --body-file
   W/issue-<slug>.md` only after the user approves it. Do not pipe the body from stdin or a
   heredoc: worktree-isolated sessions can refuse `gh issue create --body-file -` when the text
   mentions git (record in `SKILL.md`). Print the URLs.
6. Tell the user to `/clear` and run `/playbooks:repo-sweep next`.
