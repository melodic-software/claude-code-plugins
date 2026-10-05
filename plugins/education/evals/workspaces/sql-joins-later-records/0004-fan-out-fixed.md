# Fan-out duplicate found and fixed

Given a report whose revenue total doubled after a join to `order_items`, traced the doubling to the
one-to-many join and fixed it by aggregating `order_items` in a subquery before joining. Then repeated
the fix on a work report the following week without help.

**Evidence**: bug-hunt exercise and a real work query, both unaided.
