# Project-type recipes

Used when no project or plugin `control-<app>` skill is found and the bundled `run` skill does not
resolve.
Find the launch command, the port or entry point and the data from the repository's own docs and
manifests; name no stack the repository does not use. Report the line
`No control skill: drive used project-type recipe (<type>).`

| Type | Launch | Ready | Drive and observe |
|---|---|---|---|
| CLI | Run the documented command with its documented arguments | The command exits as documented on a harmless argument such as its version or help | Run each documented command; record the arguments, exit code and output |
| Server | Run the documented start command in the background, noting the process it starts | The documented health or root URL answers and the response names the expected build when it exposes one | Send the documented requests; record each request and response |
| TUI | Start the documented command in a terminal session this run owns | The screen shows the documented first view | Send the documented keys; record the screen text after each |
| Browser app | Start the documented dev server, then open its URL with the browser tool the project documents | The page loads and shows the documented first view | Take the documented user steps; record page text and a screenshot per step |
| Library | No app to launch | The documented example or entry file runs | Run the documented example; record the output |

When the repository documents none of these, stop and report the gap, naming what was missing.
