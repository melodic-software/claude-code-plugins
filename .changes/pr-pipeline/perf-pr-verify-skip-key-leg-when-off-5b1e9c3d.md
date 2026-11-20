---
bump: patch
---

### Changed

- pr-verify skips its API-key job (Check Intent) while `vars.CLAUDE_API_KEYS_DISABLED` is `true` and starts the subscription job directly, with reason `no-key`, so a judged pull request no longer spends the key job's GitHub reads and one job hop before the subscription leg judges. The subscription job keys on the key job's result, not on the variable, so a switch flipped between the two jobs neither judges twice nor leaves the run unjudged. With the switch off the chain is unchanged.
