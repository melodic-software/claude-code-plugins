---
type: review-findings
date: 2026-01-01T00:00:00Z
branch: fixture
tier: small
---

## Findings

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | IMPORTANT | high | src/Booking.ts:12 | code-reviewer | Booking has both isCancelled and isConfirmed booleans, and BookingService.confirm sets the second without clearing the first, so a booking can be cancelled and confirmed at once. | Fix the confirm path. |
| 2 | CRITICAL | high | src/eval.ts:4 | security-reviewer | Passes user input to a dangerous eval call. | Match the call shape and block it. |
