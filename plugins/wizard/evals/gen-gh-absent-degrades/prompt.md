---
description: "Legacy generate case gh-absent-degrades-not-fails, slash-invoked with a question and no repository: will a wizard break for people without the gh CLI? The reply says the run does not fail (it carries on), that the stages which write CI secrets or variables print a warning, and that the closing summary lists what the person still has to set themselves (SKILL.md lines 53-55 and 182-183). It does not propose removing, skipping or bypassing the CI-secret stages. Reply-only: no tool is graded. Hard because 'will it break' invites a hedge or a gh-is-required answer."
tags: [wizard, generate, outcome, gh-absent, reply-only]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says the wizard does not break without gh: the CI-secret and CI-variable stages print a warning, the closing summary names each value the person still has to set themselves, and the rest of the run carries on. It does not suggest removing, skipping or bypassing those stages."
---

/wizard:generate Some of the people who'll run the Textwave setup wizard won't have the gh CLI installed. Will the wizard break for them?
