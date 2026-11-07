---
description: 'Legacy decompose 7. A mid-flight reroute of a spec container: only the untouched obsoleted children close as not planned with a comment, the claimed child is coordinated first, merged children stay untouched, the container body is edited before regeneration, and the regenerated items pass the approval gate and publish with --parent and --blocked-by. not-planned reads the reply for the close reason. Read-only tools, graded on the reply.'
tags: [decompose, re-decompose, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Runs the reroute flow: enumerates the container''s children with list-sub-items --state all, closes #504, #505 and #506 as not planned through the bound adapter, each with a one-line comment linking the superseding direction, coordinates with #503''s claim holder instead of closing it, and leaves #501 and #502 untouched. Edits the container body to the streaming direction first, then drafts the replacement items, presents them, and on approval publishes them with create-item --parent and --blocked-by. A spec found wrong after ship would get a new spec, never a patch to the closed container.'
---

/work-items:decompose

Mid-flight review showed our spec container's remaining direction is wrong: the export feature should stream, not batch. Two sub-items are already merged, one is claimed and in progress by another session, three are untouched. Close out the old tickets and cut new ones for the streaming direction.

The container is #500 on GitHub. Its sub-items: #501 and #502 merged; #503 claimed by another session with a live lease; #504, #505 and #506 open and unclaimed, all three built for the batch direction. When you show the container body edit, the operator approves it; when you present the regenerated items, the operator answers: "Approved as drafted."

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
