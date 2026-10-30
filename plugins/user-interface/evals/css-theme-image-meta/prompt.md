---
schema_version: "1.1"
name: css-theme-image-meta
description: "Hard (the theme has an image as well as colors): Written from MB:plugins/user-interface/skills/write-css/reference/foundations.md:169-174. A two-theme site adds the light dark color-scheme meta tag, and an image that differs by theme switches with both the OS setting and the switch. Base gives the image its own rule; head also allows light-dark() with two images after a support check; the grader accepts either, the outcome both versions share."
tags: [web, theming, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The head gets <meta name=\"color-scheme\" content=\"light dark\">, and the hero illustration switches with the theme under both the OS setting and the header switch, through its own rule or through light-dark() with a support caveat"
---

Add light and dark themes to our marketing site. The theme follows the visitor's OS setting, and a
switch in the header can override it. The hero has a background illustration with a light version
(`/img/hero-light.svg`) and a dark version (`/img/hero-dark.svg`). Colors today: background
`#ffffff`, text `#1a1a1a`, accent `#2563eb`. This run cannot write files, so put the HTML `<head>`
changes and the CSS in your reply.
