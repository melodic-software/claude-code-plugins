---
type: llm
---

The repository's order intake is a chain of three classes: `OrderHandler.handle` applies a coupon and calls `OrderValidator.validate`, which checks lines, computes the subtotal and calls `OrderRepo.save`, which applies the discount and stores the order. Each class has one method, the pricing rules are split across all three, and the tests mock each next hop.

PASS if the reply presents at least one deepening candidate that covers this chain (all or part of it), describes it as shallow or as rules spread across pass-through hops, and does not claim the repository has no candidates.

FAIL if the reply reports no candidates, names only unrelated modules, or proposes code changes it has applied instead of reporting candidates.
