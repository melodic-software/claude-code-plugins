---
bump: patch
---

### Changed

- Skill bodies and reference files across `audit`, `audit-automation-gaps`, `audit-instructions`, `audit-pass`, `audit-permission-grants`, `audit-permission-state`, `audit-prompting-postures`, `setup` and `unhobble` no longer restate Claude Code docs specifics such as hook exit-code behavior, plugin variable scope, managed-settings paths, the debug-log variable, version boundaries and setting names. Each keeps the decision and points at the live docs section, with an as-of date and a recheck trigger.
- Corrected statements that contradicted the plugin's own files: the hook-event count the candidate guidance covers (four, not three), the `C6-colonStar` no-space case (reported as the `C6-colonStarAmbiguous` warning, not a gap), which `setup` scripts probe for their tools, and `unhobble` restating the instruction-files modes its own record owns.

No behavior change.
