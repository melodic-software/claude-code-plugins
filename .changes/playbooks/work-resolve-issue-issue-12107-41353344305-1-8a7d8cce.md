---
bump: patch
---

### Fixed

- The model-adaptation chapters and the `boris`, `fable-5` and `skill-authoring` skills point at the live upstream sections with an as-of date and recheck trigger for each drifted claim. Dead per-model effort anchors and the models-overview anchor are re-pinned. Stale claims are corrected: `ultracode` no longer "guarantees" a workflow, `/goal` has no built-in turn cap, the auto mode plan list is gone, and Fable is no longer called the current default. The subagent omitted-`model` sentence no longer gives a stale fallback and points at the subagent model docs instead ([#12107](https://github.com/melodic-software/claude-code-plugins/issues/12107)).
