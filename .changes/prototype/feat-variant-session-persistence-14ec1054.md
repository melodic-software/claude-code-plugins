---
bump: minor
---

### Changed

- **The real-stack switcher keeps the chosen variant across in-app navigation.** When `/prototype:explore-directions` mounts the switcher in a layout shared across routes, it also keeps the current variant in session storage, so navigation that drops the query string no longer loses the choice. A `?variant=` in the URL still wins over the stored value.
