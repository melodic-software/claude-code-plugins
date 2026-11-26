---
bump: minor
---

### Changed

- **`check-skill.sh` check 27 checks every routing section against the skill-bodies rule.** A `## Next` bullet now warns when it names more than one skill, has no `<result>:` lead, is the only bullet, or routes an unsure reader to `/session-flow:workflow`; the two-to-four bullet cap is gone. `## Related` warns on a bullet not in `<condition>: /plugin:skill` form, `## See also` on any skill token, and the description on an existing skill named without its slash.
