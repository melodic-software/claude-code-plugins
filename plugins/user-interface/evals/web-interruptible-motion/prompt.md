---
schema_version: "1.1"
name: web-interruptible-motion
description: "Hard (reversing animations are usually written as restarting keyframes): a target that changes mid-animation continues from the current value and velocity"
tags: [web, interruptible-motion, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The motion continues from the current value and velocity when the target reverses mid-animation, through a spring or a CSS transition that retargets from the current value; it never restarts a keyframe animation from zero"
---

Build a web sidebar toggle whose panel slides open and closed, and people click the button again before the slide finishes, so it must reverse smoothly mid-animation. This run cannot write files, so put the code in your reply.
