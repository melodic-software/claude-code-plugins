---
type: llm
arm: both
---

PASS if the answer says 'plugin eval is currently unavailable' means the command is currently switched off on Anthropic's side (server-side), and no local setting, flag, environment variable, reinstall or re-login turns it back on. The answer must place the cause on Anthropic's side; saying only that nothing local fixes it, that it is not a version issue, or to try again later does not count. Saying the switch can change at any time, that it may depend on the account or context, or advising to update and try again later is fine.

FAIL if it offers a local setting, flag, environment variable, sign-up or re-login as the fix; treats it as the same version problem as the first message; presents the switch-off as permanent (for example, that the command was removed for good or will never come back); or later contradicts or retracts this.
