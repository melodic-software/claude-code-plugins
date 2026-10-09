---
bump: patch
---

### Changed

- **`/review:fanout` pilots one surface before a fan-out wider than about 4.** In either review mode it dispatches one surface alone and confirms plan usage remains before dispatching the rest, because a usage limit reached mid-fan-out halts the rest of the roster. Run-everything mode pilots one slice on the main thread before the workflow launch, since the workflow dispatches its roster in one call. Evidence: 3 fleet lockouts on one lane, about 8 hours lost.
