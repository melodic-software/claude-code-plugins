---
bump: patch
---

### Fixed

- `/work-items:scan-todos` can now file a significant marker through `/work-items:track add` ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). `track add`'s authorization gate names a scan-todos step as authorization when it files a marker from the group the user selected, or that `--work` selected, in a run the user invoked; a run the model or another skill started still files nothing. Before this, scan-todos told the model to file through `track add` and the gate refused it.
