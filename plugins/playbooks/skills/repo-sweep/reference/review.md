# review

Turn what went wrong in the last step into filed issues. Nothing is filed without the user's
approval.

1. Ask the user what went wrong in the last step: wrong findings, missed findings, a skill that
   ignored its override, a confusing prompt, a catalog entry in the wrong place or with the wrong
   arguments. Add anything you saw yourself, including `guard.sh` stop lines.
2. Sort each problem:
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
3. Show every draft (title, body, target repository). File each one with `gh issue create` only
   after the user approves it, and print the URLs.
4. Tell the user to `/clear` and run `/playbooks:repo-sweep next`.
