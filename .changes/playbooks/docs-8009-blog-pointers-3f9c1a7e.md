---
bump: patch
---

### Fixed

- `skill-authoring` now cites Thariq Shihipar's "Lessons from building Claude Code: How we use skills" blog post, with a dated pointer record, and corrects drift against it: the category names and examples, two tip headings, the day-1-to-month-3 gotchas example (one line to four), the AskUserQuestion setup tip, the context cost of checked-in skills, and the product-verification note. It drops the SKILL.md line-count target and the "curate before release" advice, since the post has neither and says no central team decides what ships. The `CLAUDE_PLUGIN_DATA` advice now cites the plugin manifest reference.
- `fable-5`'s verification chapter points to "Building effective agent automations" for a worked Managed Agents automation that checks its own output, with its code under "Get the code".
