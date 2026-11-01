# Worked examples

Each row is a tool that got an artifact prompting could not reach, keyed by the artifact. The
branch column names the gap in SKILL.md's "Classify the gap" tree that the tool closed; read the
row as the pattern to repeat for that branch. Research-first passes (a vibe with no target yet) are
in [visual-research.md](visual-research.md#worked-passes).

| Artifact | Why the direct path failed | Branch | The tool | What it exported |
|---|---|---|---|---|
| A report cover of ripped punch cards, drawn in a design tool and needed in code so readers could punch holes in the card | The agent could not reproduce the design exactly, and that was known before asking | Dial-in: instead of trying to match the design exactly, the rip became a taste call, picked from the generator's output after some trials | A generator of the ripped-paper pattern, with a save button | Save writes the current configuration to a JSON file, and that file generates the pattern in the shipped cover |
| A dithered logo that renders on a canvas at full detail, as close as possible to the original | The app that made the dithered reference had no export usable in code; its SVG, at the detail wanted, was too heavy to render; prompting for the logo from a screenshot failed several attempts in a row, each attempt a spin with no way to steer | Matching tool plus converter: the process was known, because the source app showed its algorithm and main settings | A tool that generates the logo with the same algorithm and settings as the source app | A set of coordinates the canvas draws, instead of an image |

What the rows share: both tools took minutes to build, and each export answered SKILL.md's
question 4 ("What format does the project need?").
