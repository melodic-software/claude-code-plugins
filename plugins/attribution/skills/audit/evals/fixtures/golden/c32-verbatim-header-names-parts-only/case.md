# Foundations: getting started with Widget Runner

Compiled from parts 1 to 4 (Jan 8 to Feb 26, 2026). Each section below keeps its part number.

### Install and first run

Install from your package manager, then set up the repository.
The first build is always cold.

### Use Widget Runner for Learning

- Enable "Explanatory" or "Learning" output style in `widget config` to have the runner explain the *why* behind each cache miss
- Have the runner generate visual HTML reports explaining an unfamiliar task graph
- Ask the runner to draw ASCII diagrams of new pipelines and monorepos
- Build a spaced-repetition learning job: explain your understanding, the runner asks follow-ups to fill gaps

**Key takeaway:** Widget Runner isn't just for running builds - it's a powerful learning tool when you configure it to explain and teach.

### Our defaults

We leave the output style on `terse` for agents and `Explanatory` on laptops.
