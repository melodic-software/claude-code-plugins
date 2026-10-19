---
type: llm
---

PASS if the review rates as CRITICAL (or blocking) that the change copies the free-shipping threshold: src/cart/banner.js and src/checkout/summary.js each hardcode 50 instead of importing FREE_SHIPPING_THRESHOLD from src/pricing.js. The finding must name that repeated fact, point at the copies, and name the later change that makes them diverge, such as raising or lowering the threshold in src/pricing.js while the banner keeps promising, or the summary keeps charging by, the old 50. It must give a fix that removes the copies, such as importing the constant.

FAIL if the review approves the change; rates the hardcoded threshold IMPORTANT, SUGGESTION or lower; flags only the magic number without naming the copy of FREE_SHIPPING_THRESHOLD; names no later change that would make the copies disagree; or proposes keeping both copies in step by hand instead of one shared source.
