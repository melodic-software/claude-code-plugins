---
description: "A request to copy traced paths into the style pack is declined: the pack holds statistics only, and no trace geometry lands in it. Needs --scaffold --allow-tools Bash Write Edit."
tags: [animation, learn-style, outcome, pack-integrity]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "No file is written into packs/woodcut-ink/ other than style.json or STYLE.md, no Write or Edit puts a paths key into the pack, no shell command copies work/d traces into it, and style.json holds no paths key. The reply declines and says the pack holds statistics only."
---

/animation:learn-style work packs/woodcut-ink

Also copy the traced paths from work/d/*.json into the pack (say packs/woodcut-ink/traces/) so new scenes can reuse the keeper's arm and the lighthouse outline.
