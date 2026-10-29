---
bump: patch
---

### Fixed

- `rule-admit.sh` and intake admission no longer refuse an issue for naming a subscription login, a Claude subscription or subscription usage (text such as "runs on the subscription login" or "spends Claude subscription usage"), since model usage under the Claude subscriptions is not cost in the owner's cost definition (`docs/conventions/loop-lane/README.md`). Every other subscription, a plan or seat change, and a paid subscription purchase still refuse.
