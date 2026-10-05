---
type: llm
---

PASS if the review reports, as a finding that needs action, that the change removed the handling for a product with no reviews (an empty reviews list), and says what now happens for that input: average_rating divides by zero and raises ZeroDivisionError, so the product page fails for such a product (for example "Cable tray" in products.json).

FAIL if the review approves the change, treats the removed early return only as style or dead code, mentions that a guard or early return was removed without naming the empty-reviews input it handled, or names the input without saying the change now fails on it.
