---
type: llm
arm: both
---
PASS only if the answer names docs/conventions/user-experience.yaml and says its team settings were
not applied (because it could not be read, checked or parsed), says built-in or default routes were
used instead with the team's overrides and deny list not applied, suggests a setup or check step to
repair it, and still gives a research plan for onboarding. FAIL if it applies the file's settings as
if they had loaded, never mentions the file, or stops without a plan.
