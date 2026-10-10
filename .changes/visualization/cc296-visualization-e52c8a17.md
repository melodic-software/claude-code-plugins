---
bump: patch
---

### Fixed

- **`/visualization:visualize` no longer lists the Artifact page's allowed CDN hosts.** The decision matrix named four script hosts in three places, and Claude Code 2.1.281 added a fifth. It now states only the plugin's own policy (inline everything; if a page ever has to load something external, use only a host the artifacts page allows and check that list live first), with a pointer to the artifacts page's "Page constraints" section in place of the host list.
