# Getting Started With Loops

Excerpt of a real upstream page, kept for the attribution golden set. The passages below carry the
page's own words with its markup removed, and nothing else from that page is reproduced.

Canonical location for the purposes of this case: `https://howborisusesclaudecode.com/`.

## The Four Loops

<!-- ai-slop-ignore-start: verbatim text of the upstream page -->
Every loop in Claude Code fits one of four shapes. They differ by what triggers them, what stops them, and — most usefully — how much of the loop you hand off:

- Turn-based, the agentic loop: Triggered by a prompt; stops when Claude judges the task done. Best for shorter, one-off tasks. You hand off the check.
- Goal-based, /goal, until the condition is met: Triggered by a prompt; stops when the goal is met or a turn cap is hit. Best when you have verifiable exit criteria. You hand off the stop condition.
- Time-based, /loop and /schedule, on an interval: Triggered by a time interval; stops when you cancel or the work completes. Best for recurring work or reacting to external systems. You hand off the trigger.
- Proactive, event-driven, no human: Triggered by an event or schedule with no human in real time; each task exits at its goal, the routine runs until you turn it off. Best for recurring streams of well-defined work. You hand off the prompt.

Notice the progression: moving from turn-based to proactive, you hand off more of the loop each step — first the verification check, then the stop condition, then the trigger, and finally the prompt itself.
<!-- ai-slop-ignore-end -->
