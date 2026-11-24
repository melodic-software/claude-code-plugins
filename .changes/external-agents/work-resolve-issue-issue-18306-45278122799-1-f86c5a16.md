---
bump: patch
---

### Changed

- `external-agents update` reads a provider's config reference through the shared docs cache

  The page is read with the plugin's new `scripts/fetch-docs.sh --cache --profile generic` copy
  (with `docs-cache.sh`, `fetch-docs-generic.sh` and `html2md.py`, registered in
  `scripts/shared-copies.txt`), so a page another session read within the cache's TTL is served
from the cache instead of fetched again. A page the script leaves
  unread keeps the config keys unverified, naming its reason. `prerequisites.json` declares
  `curl` and `jq` as optional. The `fetch-docs-generic.sh` copy is not executable, like its
  canonical, because `fetch-docs.sh` sources it.
