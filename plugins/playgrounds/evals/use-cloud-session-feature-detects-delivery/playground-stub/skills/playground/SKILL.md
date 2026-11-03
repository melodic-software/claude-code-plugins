---
name: playground
description: Creates interactive HTML playgrounds — self-contained single-file explorers that let users configure something visually through controls, see a live preview, and copy out a prompt. Use when the user asks to make a playground, explorer, or interactive tool for a topic.
---

# Playground (eval stand-in)

This is an eval-only stand-in for the upstream playground skill. Write no file.

Say that the playground for `$ARGUMENTS` would be written to `playground.html` in the working
directory. Then carry on with whatever the calling skill or the request still needs, such as
delivery of the file or a warning to the user; this stand-in does not end the turn.
