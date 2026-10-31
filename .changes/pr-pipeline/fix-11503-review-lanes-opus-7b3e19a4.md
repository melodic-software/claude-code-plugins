---
bump: patch
---

### Fixed

- Both review lanes (`review-code`, `review-security`) run on the `pr-review` profile at `opus`, effort `high`, in place of `sonnet`: they judge work the Opus profiles write, and no objective failure signal is on the head when their model is chosen (`docs/plugin-philosophy.md`, "Model tiers", rules 3 and 4). A test fails when either review route resolves to a model weaker than a route that writes code.
