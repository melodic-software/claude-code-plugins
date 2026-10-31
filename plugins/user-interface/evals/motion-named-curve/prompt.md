---
schema_version: "1.1"
name: motion-named-curve
description: "Hard (the curve asked for is not configured): Written from MB:plugins/user-interface/reference/animation/catalog.md:113-114. A curve that is neither configured nor in the plugin's easing library (a sine in-out) comes from an established easing collection, named, never invented control points. Head adds the animation.easing_library step first; sine is in neither version's configured curves, so both reach this rule."
tags: [web, motion, easing, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The pulse loops on a named in-out curve from an established easing collection, never a built-in keyword or unnamed invented cubic-bezier control points, and the reply presents it as a default to tune"
---

Our call app shows a red recording dot that gently pulses (scale and opacity) back and forth for as
long as a recording runs. Our in-out curve is too punchy for this; I want something softer and
sine-like. Plain CSS. This run cannot write files, so put the CSS in your reply.
