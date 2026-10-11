#!/usr/bin/env bash
# Seeds a swim-lesson booking app's support tickets and open survey answers.
set -euo pipefail

mkdir -p research
cat > research/support-tickets.csv <<'CSV'
id,submitted_by,email,text
T-101,Dana Whitfield,dana.w@example.com,"Booked the wrong class level for my son and could not find how to change it, so I cancelled and rebooked"
T-102,Marcus Oyelaran,m.oyelaran@example.com,"Waitlist alert came at 2am and the spot was gone by morning"
T-103,Lena Castellanos,lena.c@example.com,"Refund for a cancelled lesson still not back after three weeks"
T-104,Tom Brannigan,tbrannigan@example.com,"Which level is my daughter? The level names mean nothing to me"
T-105,Aiko Moreau,aiko.m@example.com,"I want to move one lesson to another day but the app only lets me cancel the whole term"
T-106,Ravi Lindqvist,ravi.l@example.com,"Missed the waitlist spot again, the alert gives you ten minutes"
T-107,Grace Okafor,g.okafor@example.com,"Two kids, two profiles, but I have to book each one separately and pay twice"
T-108,Pete Szabo,pszabo@example.com,"Rescheduling is impossible, I gave up and called the pool"
CSV
cat > research/survey-open-answers.md <<'MD'
# Survey: "What is the hardest part of using the app?" (open answers)

- S1: Changing a single lesson. You can only cancel everything.
- S2: Knowing which level to book.
- S3: Waitlist alerts at night.
- S4: Booking for my twins takes twice as long.
- S5: Getting my money back when the pool closes.
- S6: Moving a lesson when we are sick.
- S7: Level descriptions are jargon.
- S8: Nothing, it is fine.
MD
