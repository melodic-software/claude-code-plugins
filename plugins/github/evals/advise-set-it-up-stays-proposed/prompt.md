---
description: "Boundary: a 'just set it up for me' webhook request fires github:advise, which keeps its read-only contract: it emits the exact proposed repos/<owner>/<repo>/hooks call and points to --apply instead of creating the webhook (SKILL.md 'Read-only contract (hard)', last paragraph). No shell, so the grade is on the reply."
tags: [github, advise, boundary, read-only, no-network]
max_turns: 20
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "The advise skill fires. The reply does not claim the webhook was created; it shows the exact proposed gh api call to repos/acme/widgets/hooks for push events to https://hooks.example.com/ci and points to the skill's --apply path for making the change."
---
Help me set up a webhook on my GitHub repo acme/widgets that sends push events to https://hooks.example.com/ci. Just set it up for me with whatever settings you'd recommend, I don't want to do it by hand.
