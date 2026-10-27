---
bump: minor
---

### Added

- **`interview` page surface:** a `tldr` restate section, shown first on the page as `Scope (TLDR)`, so the user confirms scope before the export. `export-brief` writes its bullets at the head of the Brief's `### TLDR`, ahead of the counts and the stamp, and `restate` refuses a `tldr` line opening `Restatement:` or `Page title:`, the labels the `--brief` gate reads. A `tldr` over five lines warns ([#6051](https://github.com/melodic-software/claude-code-plugins/issues/6051)).

### Fixed

- **`interview` page surface:** `export-brief` no longer lists each confirmed commitment under `### Captured assumptions` as `confirmed on Q<N>; revisit if Q<N> changes`. `/planning:plan` turned each of those lines into an assumption to revisit, but a confirmed commitment is a decision. It already sits on its decision's line, and a decision still open on unticked commitments now lists its ticked ones on a TLDR line, `- Q<N> confirmed so far: <commitments>`. Captured assumptions now holds unconfirmed commitments as named risks, plus each `needsAnswer` Notes line no user note answered, as `- asked in Notes, not answered: <text>`. That line is how an unanswered acceptance-criteria coverage prompt reaches the Brief ([#6051](https://github.com/melodic-software/claude-code-plugins/issues/6051)).
- **`interview` page surface:** `restate` refuses an `acceptance` line that asks the user something: a question mark, "tell me", "please confirm", or a line opening on say or choose. Before this, a question such as the coverage prompt could be exported and confirmed as a criterion ([#6051](https://github.com/melodic-software/claude-code-plugins/issues/6051)).
- **`interview` page surface:** `round.py` warns on `add`, `add-round`, `apply` and `revise` when a recommendation with no commitments points at a table, visual, diagram, chart or figure while the file holds a visual or the question's `facts` hold a markdown table. The Brief exports only the recommendation and its commitments, so criteria kept only in a visual never reached the planner ([#6051](https://github.com/melodic-software/claude-code-plugins/issues/6051)).
