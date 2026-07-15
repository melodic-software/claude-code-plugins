# Big Picture board export — "Online Course Marketplace"

Text export of a completed Big Picture EventStorming board (People & Systems and
Walk-through phases done). Use this as the board data for a `--discover-bcs` run —
run Brandolini's 6 heuristics against it. No live Miro read is required; treat the
rows below as the parsed board items.

## Timeline (orange domain events, left → right), grouped by timeline zone

### Zone 1 — Onboarding & content

- `Instructor Signed Up` — persona: Instructor — y-row: instructor
- `Instructor Profile Verified` — persona: Support Agent — y-row: support
- `Course Draft Created` — persona: Instructor — y-row: instructor
- `Course Content Uploaded` — persona: Instructor — y-row: instructor
- `Course Submitted For Review` — persona: Instructor — y-row: instructor
- `Course Approved` — persona: Support Agent — y-row: support
- `Course Published` — persona: Instructor — y-row: instructor
  - NOTE: Support Agent's sticky for this same moment reads `Course Went Live`

`--- PIVOTAL: Course Published ---`

### Zone 2 — Discovery & purchase

- `Student Signed Up` — persona: Student — y-row: student
  - NOTE: Instructor referred to this moment as `Student Enrolled` (see divergence below)
- `Course Added To Cart` — persona: Student — y-row: student
- `Checkout Started` — persona: Student — y-row: student
- `Payment Authorized` — persona: Finance — y-row: finance — external: Payment Gateway
- `Payment Captured` — persona: Finance — y-row: finance — external: Payment Gateway
- `Enrollment Granted` — persona: Student — y-row: student
  - NOTE: this is enrollment INTO A COURSE, distinct from `Student Signed Up`

`--- PIVOTAL: Payment Captured ---`

### Zone 3 — Learning & completion (runs in parallel with Zone 1 authoring — different timescale)

- `Lesson Started` — persona: Student — y-row: student
- `Lesson Completed` — persona: Student — y-row: student
- `Quiz Passed` — persona: Student — y-row: student
- `Course Completed` — persona: Student — y-row: student
- `Certificate Issued` — persona: Student — y-row: student — external: Email Service

### Zone 4 — Money & disputes

- `Refund Requested` — persona: Student — y-row: student
  - NOTE: Finance's sticky for this same moment reads `Chargeback Filed`
- `Refund Reviewed` — persona: Support Agent — y-row: support
- `Refund Issued` — persona: Finance — y-row: finance — external: Payment Gateway
- `Instructor Payout Calculated` — persona: Finance — y-row: finance
- `Instructor Payout Sent` — persona: Finance — y-row: finance — external: Payment Gateway

## People (small yellow)

- Instructor — authors and publishes courses
- Student — discovers, buys, learns
- Support Agent — reviews courses, mediates refunds
- Finance — handles payments, refunds, payouts

## External systems (pink)

- Payment Gateway — authorizes, captures, refunds, pays out
- Email Service — sends certificates and notifications

## Hot spots (magenta)

- `[DIVERGENCE] "Enrollment"` — Student uses it for platform signup (`Student Signed Up`);
  Instructor/Finance use it for course access (`Enrollment Granted`). Same word, two meanings.
- `Refund disputes take 6+ days` — Support and Finance both touch refunds; nobody owns the SLA.
- `Who approves a course — Support or an editor?` — approval ownership unclear.

## Arrow voting

- Winner (most votes): `Refund disputes take 6+ days`
