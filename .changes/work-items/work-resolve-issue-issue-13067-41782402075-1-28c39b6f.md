---
bump: patch
---

### Fixed

- **The Linear seed's children reads stop at the list ceiling.** `create-item --parent` (the sibling check) and `list-sub-items` used to follow `hasNextPage` with no limit, so a server that kept reporting another page made them loop until killed. Both now stop at `limits.list_items_max`, the same ceiling the label walk uses, and exit 1 with a message that names the parent. They never act on a partial list: in `create-item` it would read as "no duplicate", and in `list-sub-items` as "nothing open".
