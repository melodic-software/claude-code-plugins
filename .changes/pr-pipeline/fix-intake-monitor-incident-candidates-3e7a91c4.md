---
bump: patch
---

### Fixed

- Intake refinement flags a person's issue as a duplicate of an open factory-monitor incident the monitoring lane already tracks. The match is made in code, with no model: an open github-actions[bot] issue whose first body line is the `<!-- factory-monitor key=… fp=… -->` marker matches when the new issue's title or body contains its key, or when the two titles are equal after lowercasing and collapsing punctuation. The model sees only the incident's number and key, never its title or body; a match is listed as a duplicate and turns an exact refinement into a question whether to close the issue.
