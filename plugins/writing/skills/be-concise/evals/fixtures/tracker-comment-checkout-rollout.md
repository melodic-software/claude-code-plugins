# Comment posted on PLAT-4412: checkout service rollout

So I wanted to give everybody a bit of an update on where we have actually
landed with the checkout service rollout, because I know there has been a
fair amount of back and forth on this over the last couple of weeks, and I
think it is probably worth writing it all down in one place so that nobody
has to go digging back through the thread history to work out what the
current state of play is.

We spent most of last week looking pretty carefully at the two options that
were on the table. The first option was a big-bang cutover over a single
weekend, which honestly a few people were fairly keen on, because it is
simpler to reason about and there is only one maintenance window to
coordinate across the three teams involved. The second option was a staged
rollout behind a feature flag, ring by ring, starting with internal users
only. After a lot of discussion, and after Priya Raman walked everyone
through the incident data from the previous two cutovers, we decided to
reject the big-bang weekend cutover. It simply carries too much blast
radius for a service that sits directly in the payment path, and the
rollback story for it is genuinely bad.

So the decision, in the end, is the staged rollout. Priya Raman is the
owner for the rollout as a whole, and she is the person to go to with
questions about sequencing or about the flag configuration.

In terms of the actual mechanics of the thing, we are shipping release
2.14.0 to the internal ring on 2026-09-18, and then assuming that stays
healthy for a full week we widen to 10 percent of external traffic and take
it from there. There is a hard deadline on this that we cannot move, which
is that the old payment gateway contract terminates on 2026-11-30, so
everything has to be off the legacy path before that date or we start
paying penalty rates on every transaction.

There is one thing we need from the platform team, and I really do not want
it to get lost right at the bottom of all this. We need the per-ring metrics
dashboard provisioned before the 2026-09-18 ship date, because otherwise we
are flying blind on the internal ring and we will not be able to make the
call about whether to widen. Could somebody please confirm by the end of
this week that it has been picked up.
