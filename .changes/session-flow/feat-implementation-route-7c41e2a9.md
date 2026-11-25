---
bump: minor
---

### Added

- `implementation_route` setting (`local` or `factory`, default `local`), set per user or per repository in `docs/conventions/session-flow.yaml`. Under `factory`, `/session-flow:workflow` names the items decompose published as handed to the repository's unattended factory lanes and recommends no local implement stage; an item that needs a local dependency stays local and is named as such. `/session-flow:setup apply implementation_route=factory` writes it.
