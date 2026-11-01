# Tools that review the work

The generators in [SKILL.md](../SKILL.md) *make* things. The second half of the same workflow is a
tool that helps you review your work. Code has linters, type checkers and unit tests; reviewing
design is still a mostly manual process. Build a tool that reviews one part of the interface the
way a frame-by-frame recorder reviews an animation: it shows what is actually applied next to what
should be.

Build one only for a problem you hit often and check by hand, and be picky. Fixing problems you
encounter often speeds up the workflow, but time spent building things that help you do other
things is time not spent on the work: stop before setting up the tools costs more than the work
they serve.

A review tool is a prototype under [the shared discipline](../../../context/discipline.md): delete
it once it has answered the review it was built for. A review tool that saves anything follows
step 7, "Save writes a file", in [SKILL.md](../SKILL.md) for its save endpoint.
