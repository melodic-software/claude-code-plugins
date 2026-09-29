# review

Turn what went wrong in the last step into filed issues. Nothing is filed without the user's
approval. `W` is `.work/repo-sweep/` in the worktree root (create it when filing).

1. Dispatch a separate reviewer agent (Task tool or subagent). It must not be the session that
   ran the step. Give it only:
   - repo-sweep procedure files (`reference/next.md`, this file, the step skill's SKILL.md and
     references it used),
   - the step's artifacts (`.work/repo-sweep/`, the PR checklist line for that step, `git diff`
     from the step base or the absence of a diff),
   - and the user's complaints once you have them (step 2 below).
   Never give it the executing agent's reasoning, tool transcript, or chat history. It returns a
   classified problem list: skill defect, catalog defect, executing-agent error, harness issue.
2. Ask the user what went wrong in the last step: wrong findings, missed findings, a skill that
   ignored its override, a confusing prompt, a catalog entry in the wrong place or with the wrong
   arguments. Add anything you saw yourself, including `guard.sh` stop lines.
3. Merge the reviewer's list with the user's report, then sort each problem:
   - A skill defect: invoke `/plugin-quality:audit` via the Skill tool on that skill, passing
     the problem as the evidence. Draft an issue against the plugin that owns the skill.
   - A catalog problem (order, membership, arguments, applies-when, override text): draft an
     issue against `melodic-software/claude-code-plugins` for the `playbooks` plugin's
     repo-sweep catalog. Keep it separate from skill defects.
   - A repo-sweep defect (its SKILL.md, reference files, or scripts): invoke
     `/plugin-quality:audit` via the Skill tool on `playbooks:repo-sweep`, passing the problem as
     the evidence. Draft an issue against `melodic-software/claude-code-plugins` for the
     `playbooks` plugin, separate from catalog problems.

   A defect in a skill bundled with Claude Code (a bare name in the catalog, such as `claude-api`)
   has no plugin here to file against: ask the user to report it to Anthropic with `/bug`
   ([commands](https://code.claude.com/docs/en/commands), fetched 2026-09-27; recheck when that
   page drops or renames `/bug`).
4. Show every draft (title, body, target repository). For each approved draft, write the body to
   a file under `W` (for example `W/issue-<slug>.md`) and file with `gh issue create ... --body-file
   W/issue-<slug>.md` only after the user approves it. Do not pipe the body from stdin or a
   heredoc: worktree-isolated sessions can refuse `gh issue create --body-file -` when the text
   mentions git (record in `SKILL.md`). Print the URLs.
5. Tell the user to `/clear` and run `/playbooks:repo-sweep next`.
