---
board: event-storming/1
format: big-picture
title: Big Picture v1 - Online Course Marketplace
domain: Online Course Marketplace
version: 1
session: courses-20261118-a7f2
phase: wrapping-up
updated: "2026-11-18T05:30:00Z"
personas:
  - Instructor
  - Student
  - Support Agent
  - Finance
---

# Big Picture v1 - Online Course Marketplace

## Timeline

### Onboarding and content {#z1}

- [event] Instructor Signed Up {#s1 by=Instructor phase=chaotic-exploration}
- [event] Instructor Profile Verified {#s2 by="Support Agent" phase=chaotic-exploration}
- [event] Course Draft Created {#s3 by=Instructor phase=chaotic-exploration}
- [event] Course Content Uploaded {#s4 by=Instructor phase=chaotic-exploration}
- [event] Course Submitted For Review {#s5 by=Instructor phase=chaotic-exploration}
- [event] Course Approved {#s6 by="Support Agent" phase=chaotic-exploration}
- [event] Course Published {#s7 by=Instructor phase=chaotic-exploration}
- [event] Course Went Live {#s8 by="Support Agent" phase=chaotic-exploration}
  - [hot-spot] \[DIVERGENCE\] Course Published vs Course Went Live {#s9 by=facilitator phase=enforce-timeline}
- [pivotal] Course Published {#s10 by=facilitator phase=enforce-timeline}

### Discovery and purchase {#z2}

- [event] Student Signed Up {#s11 by=Student phase=chaotic-exploration}
- [event] Student Enrolled {#s12 by=Instructor phase=chaotic-exploration}
  - [hot-spot] \[DIVERGENCE\] Student Enrolled means platform signup here {#s13 by=facilitator phase=enforce-timeline}
- [event] Course Added To Cart {#s14 by=Student phase=chaotic-exploration}
- [event] Checkout Started {#s15 by=Student phase=chaotic-exploration}
- [event] Payment Authorized {#s16 by=Finance phase=chaotic-exploration}
- [event] Payment Captured {#s17 by=Finance phase=chaotic-exploration}
- [event] Enrollment Granted {#s18 by=Student phase=walk-through}
  - [hot-spot] Enrollment here means course access {#s19 by=facilitator phase=walk-through}
- [pivotal] Payment Captured {#s20 by=facilitator phase=enforce-timeline}

### Learning and completion {#z3}

This zone runs in parallel with course authoring, on a different timescale.

- [event] Lesson Started {#s21 by=Student phase=chaotic-exploration}
- [event] Lesson Completed {#s22 by=Student phase=chaotic-exploration}
- [event] Quiz Passed {#s23 by=Student phase=chaotic-exploration}
- [event] Course Completed {#s24 by=Student phase=chaotic-exploration}
- [event] Certificate Issued {#s25 by=Student phase=people-and-systems}

### Money and disputes {#z4}

- [event] Refund Requested {#s26 by=Student phase=chaotic-exploration}
- [event] Chargeback Filed {#s27 by=Finance phase=chaotic-exploration}
  - [hot-spot] \[DIVERGENCE\] Refund Requested vs Chargeback Filed {#s28 by=facilitator phase=enforce-timeline}
- [event] Refund Reviewed {#s29 by="Support Agent" phase=chaotic-exploration}
- [event] Refund Issued {#s30 by=Finance phase=chaotic-exploration}
- [event] Instructor Payout Calculated {#s31 by=Finance phase=reverse-narrative}
- [event] Instructor Payout Sent {#s32 by=Finance phase=reverse-narrative}

## People and systems

- [person] Instructor: authors and publishes courses {#s33 by=facilitator phase=people-and-systems}
- [person] Student: discovers, buys, learns {#s34 by=facilitator phase=people-and-systems}
- [person] Support Agent: reviews courses, mediates refunds {#s35 by=facilitator phase=people-and-systems}
- [person] Finance: payments, refunds, payouts {#s36 by=facilitator phase=people-and-systems}
- [external-system] Payment Gateway {#s37 by=Finance phase=people-and-systems}
- [external-system] Email Service {#s38 by=Student phase=people-and-systems}

## Problems

- [hot-spot] \[DIVERGENCE\] Enrollment: signup or course access? {#s39 by=facilitator phase=problems-and-opportunities}
- [hot-spot] Refund disputes take 6+ days {#s40 by="Support Agent" phase=problems-and-opportunities}
- [hot-spot] Who approves a course? {#s41 by=Instructor phase=problems-and-opportunities}

## Opportunities

## Votes

- [vote] Refund disputes take 6+ days {#s42 by=Finance phase=arrow-voting on=s40}
- [vote] Refund disputes take 6+ days {#s43 by="Support Agent" phase=arrow-voting on=s40}
- [vote] Refund disputes take 6+ days {#s44 by=Student phase=arrow-voting on=s40}
- [vote] Who approves a course? {#s45 by=Instructor phase=arrow-voting on=s41}

## Ubiquitous language

## Bounded contexts

## Exploration map

- Arrow-voting winner: Refund disputes take 6+ days

## Legend

| Kind | Meaning |
|---|---|
| `event` | Domain event: something that happened, past tense |
| `person` | Person or actor |
| `external-system` | External system: whatever we can put the blame on |
| `hot-spot` | Hot spot: a problem, question or disagreement |
| `pivotal` | Pivotal event: a phase boundary |
| `vote` | Arrow vote |
