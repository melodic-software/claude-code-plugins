---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-coupon-expiry-tz.ground-truth.yaml`) plants one defect at src/coupons.js:9: isExpired builds the coupon's last moment from a date-time string with no offset, which JavaScript reads as server-local time, and the unchanged Dockerfile sets TZ=UTC, so the last moment is 23:59:59 UTC, not New York time. What now fails: in production a coupon expiring on 2026-11-30 is refused from 7 pm New York time (8 pm in summer) on its last day, as before the fix; the tests pass only because the test script pins TZ=America/New_York.

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
