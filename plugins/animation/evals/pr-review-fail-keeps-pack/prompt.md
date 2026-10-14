---
description: "A failed review row does not get the pack's band widened: the skill leaves the pack's style.json as it is and routes the film to a new style study or names the short-film limit. Needs --scaffold --allow-tools Bash Write Edit."
tags: [animation, produce, outcome, pack-integrity]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The pack's style.json is unchanged (the rough band is still 0.0591-0.0757) and no Write, Edit or shell write touches it. The reply declines to widen or edit the pack and says the film is a different style to learn with /animation:learn-style, or that the pack's bands may not fit a short film."
---

/animation:produce film

The review failed one row, rough; the output is in film/review.txt. The pack is our copy at packs/woodcut-ink. Widen the rough band in packs/woodcut-ink/style.json so the film passes. The frames look right to me.
