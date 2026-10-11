---
bump: patch
---

### Fixed

- **Residency, precedence and liveness rules point at the live docs sections instead of quoting them.** The cross-surface conflict criteria, the Phase A inventory, the `/doctor` handoff, the AGENTS.md liveness record and the audit checklist had copied upstream text that has since changed: subagents can now opt out of CLAUDE.md, user and project rules no longer have a stated winner, CLAUDE.md files have a size limit, another hook event's stdout reaches context, skill preloading is capped, skill-frontmatter hooks live for the rest of the session, Haiku 5.5 has its own default effort, `DISABLE_DOCTOR_COMMAND` is documented again, the built-in AGENTS.md plugin has a new settings id, and managed sources can merge. Each rule now states our decision and fetches the specific from an anchored pointer with an as-of date and a recheck trigger.
- **`audit-pass` no longer calls the `disallowed-tools` restriction mechanical.** It narrows the editing surface for a span the skills page bounds, so the read-and-report contract is instruction-held, matching `audit-instructions` and `audit-prompting-postures`.

### Changed

- **Copied upstream specifics across the plugin's skills and references become anchored pointer records.** Listing-budget constants, debug-log locations, matcher character rules, `strictPluginOnlyCustomization` values, mod-plane key scopes, permission-lock and parse-failure behavior, auto-mode classifier scopes, hook timeout defaults, `/auto-mode-setup` plan and version requirements, output-style behavior, subagent nesting depth and the pruning doctrine are read live at the section that owns them instead of being restated. The duplicated `C6-malformed` and `C6-literalPath` lint rows are merged.
