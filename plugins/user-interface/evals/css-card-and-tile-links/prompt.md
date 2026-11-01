---
schema_version: "1.1"
name: css-card-and-tile-links
description: "Hard (two link shapes in one prompt): Written from MB:plugins/user-interface/skills/write-css/reference/interaction.md:107-155. Graded on what both versions share: no <a> wraps a card with a second control, the card's button stays its own control, an image tile navigates across its whole area through one link, every link keeps a visible focus, and hover sits behind a hover query. Base stretches the card's heading link; head gives the card a distinct link and keeps the stretched link for tiles."
tags: [web, interaction, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The card is not wrapped in one <a> and its Save button stays a separate clickable control; each image tile navigates across its whole area through one real link; every link keeps a visible keyboard focus; hover styles sit inside a (hover: hover) query"
---

Write the HTML and CSS for two components on our reports site:

1. A report card: the report title, a two-sentence summary that people often copy text from, and a
   Save button. Opening the card goes to the report page.
2. A grid of category tiles. Each tile is just an image and a one-line label, and the whole tile
   goes to that category.

Include hover and keyboard focus styles. Plain HTML and CSS. This run cannot write files, so put
the code in your reply.
