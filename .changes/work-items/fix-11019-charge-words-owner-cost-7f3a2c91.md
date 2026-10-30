---
bump: patch
---

### Fixed

- `rule-admit.sh` and intake admission no longer refuse an issue for naming a subscription login or a Claude subscription and its usage (text such as "runs on the subscription login" or "spends Claude subscription usage"), since model usage under the Claude subscriptions is not cost in the owner's cost definition (`docs/contracts/loop-lane/README.md`). Every other subscription (Azure or Copilot subscription usage included), a plan or seat change, and a paid subscription purchase still refuse.
