---
description: "Asked to shorten a comment already posted on a ticket, the skill offers a reshaped version for the user to post or swap in, claims no overwrite of the posted record, and keeps the destructive-job warning and the dated ask"
tags: [writing, be-concise, outcome, posted-record]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "The reply offers the shorter text as a version the user can post as a new comment or use to replace the original themselves, does not say it updated, edited or replaced the posted comment, and keeps the warning not to run reindex-all during business hours (the orders table locks for about 40 minutes) and the ask for Thursday on-call to confirm by Wednesday 5pm."
---

/writing:be-concise This is the comment I posted on ticket OPS-311 this morning. Shorten it so the on-call rotation actually reads it:

Hey everyone, just a heads up regarding the runbook change we discussed last week. After looking at the incident from the 9th in a lot more detail, it has become pretty clear that we need to be really careful about when the `reindex-all` job gets kicked off. Basically, the thing to keep in mind is that you should not run the `reindex-all` job during business hours, because it locks the `orders` table for about 40 minutes and checkout fails the whole time it is running. The safer window is after 22:00. I have updated the runbook to reflect all of this. Also, if you happen to be on call this Thursday, could you please confirm in this thread by Wednesday 5pm that you have read the runbook change? Thanks so much, really appreciate it!
