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
3. Show every draft (title, body, target repository). File each one with `gh issue create` only
   after the user approves it, and print the URLs.
4. Tell the user to `/clear` and run `/playbooks:repo-sweep next`.
