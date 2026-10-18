# Keep guest use of Claude the owner's own use

- Status: accepted
- Date: 2026-10-16
- Related: [ADR 0077](0077-expose-only-a-guest-listener-through-the-shared-interview-tunnel.md)
  (how guests reach the session at all). The request rules are in
  `plugins/planning/skills/interview/context/lane-shared.md`, "Request routing".

## Context

In a `/planning:interview` shared session, guests (people without the owner's Claude account) can
ask for work on a question: an answer, research, a look through the session's material, a design
pass, a prototype. The work runs in the owner's Claude Code session, signed in with the owner's own
account, which may be a Free, Pro or Max plan.

Two upstream texts bound what that may look like, both read 2026-10-16:

- [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) (effective 2025-10-08), section 2
  "Account creation and access": a user "may not share" their account credentials and "may not
  make your Account available to anyone else", and is "responsible for all activity occurring under
  your Account".
- [Claude Code legal and compliance, Usage policy](https://code.claude.com/docs/en/legal-and-compliance#usage-policy):
  plan usage limits "assume ordinary, individual usage", and developers may not "route requests
  through Free, Pro, or Max plan credentials on behalf of their users".

A guest typing straight into the owner's Claude, or holding a private Claude conversation on the
owner's plan, would make the owner's account available to that guest. The value of the feature is
that the group can still ask for research and get it.

## Decision

1. **Guests never reach Claude directly.** A guest's request waits in the owner's queue. The owner
   can edit, decline or run each one; "Run all shown" runs only the requests visible to the owner
   at that moment; nothing runs on its own.
2. **Results wait for the owner.** A result lands unpublished in the owner's queue and reaches
   guests, the requester included, only after the owner publishes it.
3. **The work is the owner's.** The owner's session routes each run request to the tools enabled in
   it, read-only and scoped to the question; anything that would write, push, spend or reach outside
   the repository and the session folder needs the owner's yes in the terminal. A guest's text
   asking Claude to act is reported to the owner as a finding, never followed.
4. **No private guest Claude on the owner's plan.** A guest who wants their own Claude connects it
   ("Connect your Claude"): those requests run on the guest's own account, never enter the owner's
   queue and never reach the owner's session.
5. **An API-key mode is later work.** Serving guests from an API key billed to its owner under the
   Commercial Terms is a separate decision with its own record.

## Alternatives considered

- **Auto-run guest requests on the owner's session.** Rejected: every guest would be using the
  owner's account with no review, which is making the account available to others.
- **A private Claude chat per guest on the owner's plan.** Rejected for the same reason, and its
  usage would not be ordinary individual use.
- **No guest requests at all.** Rejected: research on demand is part of what the session is for,
  and owner review keeps it the owner's own work.

## Consequences

- The owner is a bottleneck for guest requests by design; the queue, "Run all shown" and
  per-request status (Waiting, Running, Declined, Done, Failed) make that visible to guests.
- The server never moves a guest request to running except on the owner's token, and never shows a
  result to guests before the owner publishes it.
- Recheck this decision when either upstream text above changes, or when the API-key mode is
  designed.
