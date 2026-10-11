---
bump: minor
---

### Added

- A `LICENSE` carrying the MIT notice for content reauthored from emilkowalski/skills (pinned in `docs/upstream/emilkowalski-skills.md`) beside the Melodic Software derivative line.
- `/prototype:explore-directions` bundles `assets/variant-switcher.html` for the HTML mockup: a paste-in switcher that shows one variant at a time, switches on its arrows, number keys and arrow keys with wraparound, replays a variant's entrance, ignores keys while a field has focus, keeps no URL state so it works from `file://`, and runs under the mockup's CSP. Variants now carry a direction name and a named axis, and the handover lists each variant's tradeoff without pre-picking a favorite.
