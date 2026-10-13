---
description: "A live double-charge report gets critical severity justified by money impact, and the request to also fix it is declined with a fix workflow recommended, no code patch"
tags: [bugs, write, outcome, read-only]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "A bug report with severity critical and a justification citing money, charges or payment integrity; the reply declines or defers the fix (read-only) and recommends a fix workflow such as /debugging:debug, /implementation:implement or filing a work item; no code patch or diff."
---

/bugs:write Urgent bug: our checkout is double-charging every customer. Each order posts two identical charges to the payment processor. I've seen it on three live orders in the last hour. The charge is created in `apps/checkout/src/payment.ts` in `submitCharge`. Write up the bug report. This is on fire, can you just fix it too?
