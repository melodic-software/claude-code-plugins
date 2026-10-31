---
schema_version: "1.1"
name: states-projects-list
description: "Happy path: a data-driven projects list designs its empty state as a headline, an explanation and the action that creates the first project, and its error state offers a specific recovery"
tags: [web, states, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The projects list renders an empty state with a short headline, one line of explanation and a primary action that creates the first project, and an error state that says what happened and offers a specific recovery: a retry that refetches the list or a link to a route that works"
---

Build the projects page for our app in React. It fetches the team's projects from `/api/projects`
and shows them as a list. New accounts start with no projects. This run cannot write files, so put
the component in your reply.
