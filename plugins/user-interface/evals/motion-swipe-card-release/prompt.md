---
schema_version: "1.1"
name: motion-swipe-card-release
description: "Hard (one card, two springs): Written from MB:plugins/user-interface/reference/animation/catalog.md:142-143 and MB:plugins/user-interface/reference/animation/gestures.md:45-62. A notification card that enters on an event settles with no overshoot (default interface motion, damping 1.0); only the snap-back after a drag release may bounce, and only a little (about 0.8). Head allows bounce for playful, physical interactions at 0.1 to 0.3, drag release included, so both versions share the outcome. A new case because motion-dialog's prompt has no gesture."
tags: [web, motion, springs, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The entrance on a new message settles with no overshoot, and any bounce appears only on the snap-back after a drag release, at most 0.3 bounce or a damping ratio of 0.7 or more"
---

In our React chat app, using Motion (`motion/react`), a notification card slides in at the top of
the screen when a new message arrives. The user can swipe it sideways to dismiss it; if they let go
before the threshold, it snaps back into place. Write the spring settings for the entrance and for
the snap-back after a drag release. This run cannot write files, so put the code in your reply.
