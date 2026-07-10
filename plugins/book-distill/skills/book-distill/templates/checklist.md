# book-distill checklist

Copy into `${CLAUDE_PLUGIN_DATA}/{project-slug}/{target-skill-slug}/{book-slug}-checklist.md`. Derive `{project-slug}` from the basename of `${CLAUDE_PROJECT_DIR}` and `{target-skill-slug}` from the target skill name, each slugified to lowercase alphanumerics and hyphens. Tick as each phase completes; the ticked state is the cross-session resume pointer.

## Phases

- [ ] Phase 1: Setup — book file path; output skill target (existing skill to extend OR new skill creation); chapter list extracted
- [ ] Phase 2: Chapter-by-chapter distillation — per-chapter pass; key claim extraction; citation back to page/section
- [ ] Phase 3: Shared file merges — dedup across chapters; promote cross-cutting themes to skill-wide reference files
- [ ] Phase 4: SKILL.md update — integrate distilled content into the target skill body or `reference/` files; respect the 500-line SKILL.md cap + progressive disclosure
- [ ] Phase 5: Quality polish — verify no content loss; markdown lint clean; cross-references valid

## Skip criteria

- Phase 3 SKIPPED for single-chapter or thin books (no cross-chapter dedup opportunity)
- Phase 5 loss-check SKIPPED when Phase 4 is additive-only (new content, no existing rewrite)
