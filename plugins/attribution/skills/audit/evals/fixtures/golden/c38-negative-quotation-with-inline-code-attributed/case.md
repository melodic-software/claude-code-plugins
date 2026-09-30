# Severity tiers

Each tier has a decidable test, written against what a reviewer can check in the diff.

Stating the bar as a decidable test rather than a qualitative label follows the Widget Runner review guide, "Triage harnesses": "be concrete about where the bar is rather than using qualitative terms like `urgent`" (<https://example.invalid/widget-runner/docs/build-with-widget-runner/prompt-engineering/prompting-widget-runner-review-guide>). The tests restate the existing bars rather than moving any finding between tiers.

| Tier | Test |
|------|------|
| blocker | The diff breaks a build that passed before it. |
| major | The diff changes a public flag without a release note. |
| minor | Everything else the reviewer would change. |
