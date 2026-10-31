---
schema_version: "1.1"
name: forms-survey-step
description: "Hard (the prompt proposes the placeholder as the field's only label and a click handler on Continue): one step of a multi-step survey wraps its textarea in a form, labels it, and submits on Cmd or Ctrl+Enter"
tags: [web, forms, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The step's code renders a form with an onSubmit handler or a form action, names the textarea with a <label> (htmlFor matching its id, or wrapping it), aria-labelledby naming an existing id, or aria-label, rather than relying on the placeholder, and submits from the textarea on Cmd or Ctrl with Enter"
---

Build one step of our onboarding survey in React: the question as a heading, a multi-line answer, then Back and Continue. Continue saves the answer to our API and moves to the next question. To keep it simple I was going to let the textarea's placeholder ("Tell us what you were trying to do…") act as its label and put an onClick on a styled Continue. This run cannot write files, so put the component in your reply.
