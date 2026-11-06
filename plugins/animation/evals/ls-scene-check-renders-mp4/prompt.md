---
description: 'Legacy learn-style check-a-new-scene-against-the-woodcut-pack. learn-style SKILL.md lines 63-66: render the scene through render.py at the pack''s base_fps (24 in styles/woodcut-ink/style.json) with --encode mp4, then inkstats.py with --pack; lines 70-74: read crops at 1:1 before calling it a match; line 78: tune the scene, never the check. ran-render-encode needs render.py on scenes/harbor.js with --encode mp4; render-at-base-fps and inkstats-has-pack fail a render at another fps and an inkstats.py run without --pack; no-pack-write, no-pack-edit and no-shell-pack-write keep the workspace copy of the pack untouched; no-unread-match-claim fails a reply that calls the scene a match. Held: the inkstats.py run and the crop reading as positives, since render.py needs the Python packages and Chromium that an eval run may lack. The pack is a workspace copy (packs/woodcut-ink) so a wrong edit is graded instead of denied in the plugin directory. Paths refit from ~/scenes. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, learn-style, outcome, process, pack-integrity, no-network]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'The skill renders scenes/harbor.js through render.py with --encode mp4 at 24 fps, runs no inkstats.py without --pack, leaves packs/woodcut-ink/style.json untouched, and does not call the scene a match.'
---

Does my new scene match the woodcut pack? The scene is scenes/harbor.js, and our copy of the pack is packs/woodcut-ink.
