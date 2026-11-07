---
description: "Legacy visualize 7. The scaffold makes the workspace its own git repository with a tracked docs/conventions/rendered-views.yaml setting 'medium: file' and no personal override; run by hand there, the resolver prints 'view: file (team)'. The skill runs the resolver and leaves every settings file to it (SKILL.md lines 118-135); with a file medium and mmdc absent the mermaid gate keeps the source, so lines 188-197 call for the source fence with an unrendered notice. resolver-ran (with-only) needs the resolver call; no-convention-read and no-convention-shell-read that no Read or Bash command names a rendered-views file; report-line-team the printed line; no-override-error that the absent personal override is not called an error; gate-ran (with-only) the mermaid gate run (lines 199-204); source-fence-notice the fence plus the notice. Held: the legacy 'writes a local HTML page' (mmdc is absent, see the map). Needs --scaffold --allow-tools Bash Write."
tags: [visualization, visualize, outcome, rendered-view, no-network]
max_turns: 16
timeout_seconds: 480
allowed_tools: [Skill, Read, Write, Bash]
expected_outcome: "The resolver runs with --lane visualization:visualize and no Read or Bash command names a rendered-views file; the reply prints 'view: file (team)' and gives the pipeline as a mermaid source fence with a line saying it is unrendered."
---

/visualization:visualize the deploy pipeline we discussed as a diagram. To recap: a push to main builds the image, runs the unit tests, pushes the image to the registry, deploys to staging, runs the smoke tests there, waits for a manual approval, then deploys to production; a failed smoke test rolls staging back.
