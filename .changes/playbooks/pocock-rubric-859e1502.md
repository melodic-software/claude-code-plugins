---
bump: minor
---

### Changed

- **`skill-authoring` criteria: evals decide a cut ([#6476](https://github.com/melodic-software/claude-code-plugins/issues/6476)).** The deletion test now proposes and the evals decide: a cut to an existing skill ships only with eval evidence of no loss. New body rules keep contract sections (argument grammar, mode selection, ask-or-proceed, stop gates) explicit, scope a skill as one vertical slice grown by progressive disclosure instead of split, and aim for a short hub that routes each task to the file it needs. Descriptions keep a quoted user idiom when probes show it moves triggering. The rewrite protocol adds cases before the rewrite, a blind held-out probe set per round, concurrent before/after runs per model, a 5-point non-inferiority margin, separate description and body decisions, and which artifacts a run commits.
