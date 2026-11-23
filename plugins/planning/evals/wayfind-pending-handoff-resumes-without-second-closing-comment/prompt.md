---
description: "An open map with an empty frontier whose newest counted closing comment ends `Handoff: pending` resumes the handoff to its destination's skill and posts no second closing comment (work step 1). Why hard: the reflex is to run map closure again from the start, posting a fresh closing comment before handing on."
tags: [wayfind, handoff, pending-handoff]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The run sees that the map's author already posted the closing comment and that it ends `Handoff: pending`, so it resumes the handoff: it invokes /planning:prd with the closing comment's decisions and a `Source map: #520` line, and writes out no new closing comment on #520."
---

/planning:wayfind work 'Map: shared shopping lists' (#520). I'm here and can answer questions.

These tracker reads were already made this session; use them and do not re-run them.

Map #520 is open. Its author is `dana-m`. Destination: a PRD for shared shopping lists in the grocery app. Decisions-so-far: 'Who can edit a shared list?' (Q1, #521), 'How long does a deleted list stay recoverable?' (Q2, #522) and 'Do list edits made offline sync later?' (D3, #523). All three items are closed. The frontier holds no item, Not-yet-specified is empty, and the map has no dossier branch.

`/work-items:track view 520 --comments` returned these comments, oldest first:

```json
[
  {
    "user": { "login": "dana-m", "type": "User" },
    "created_at": "2026-11-02T10:14:03Z",
    "html_url": "https://example.com/acme/groceries/issues/520#issuecomment-6101",
    "body": "Closing comment: every decision on this map.\n\n- Q1 'Who can edit a shared list?' (#521): every member of the household.\n- Q2 'How long does a deleted list stay recoverable?' (#522): 30 days.\n- D3 'Do list edits made offline sync later?' (#523): yes; edits queue on the device and merge on reconnect, newest edit per item wins.\n\nNo dossier branch.\n\nHandoff: pending"
  },
  {
    "user": { "login": "lee-t", "type": "User" },
    "created_at": "2026-11-03T08:41:55Z",
    "html_url": "https://example.com/acme/groceries/issues/520#issuecomment-6117",
    "body": "Any news on the PRD for this one?"
  }
]
```

`gh api repos/acme/groceries/collaborators/dana-m/permission --jq .permission`: `admin`

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Where the skill hands the map to /planning:prd, invoke it with the Skill tool, its task description as the arguments, and stop as soon as that skill loads, before its first step. Invoke no other skill: where the skill would invoke one, write out the call (skill and arguments) and treat it as made. Put everything in your final reply, each tracker action you wrote out included. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
