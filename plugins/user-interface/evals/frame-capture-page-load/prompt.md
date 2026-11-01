---
schema_version: "1.1"
name: frame-capture-page-load
description: "Happy path: a motion review of an entrance that plays on page load, which the user has never seen frame by frame: the audit's reply arms the capture before the page loads (a page clock, and a script that holds declarative entrances, set up before navigation) and reads the CSS entrance by pausing and seeking it, not by trusting the page clock or a video"
tags: [web, motion, audit, frame-capture, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "user-interface:audit runs. The capture it describes is armed before the page's first script runs: a page clock installed, or an init script registered, before navigation, never a capture started after load. Script-driven motion (the requestAnimationFrame counter) is stepped on that clock; the declarative entrance (the CSS keyframes) is paused and set to each frame's time, and per-frame values are read from computed style, not from a video"
---

Run a motion review of our landing page intro. The hero fades and slides in with CSS keyframes when
the page loads, and a stats counter beside it counts up with `requestAnimationFrame`. It is over
before I can start a recording, so I have never seen either frame by frame. Tell me how the review
can capture both frame by frame. This run cannot write files or run the app, so put the steps and
any script in your reply.
