# Choose a tool

Pick the tool that answers the question at the lowest cost: a model checker, a proof assistant, an
SMT-backed verifier, or another tool.

| The question | Usually suits |
|---|---|
| Whether events can happen in a bad order | A model checker over a small model of the design |
| Whether the code itself behaves for every input, as with memory safety, overflow, or a data-structure invariant | A verifier that runs on the code |
| A property that must hold at every size, where a bound is not enough | A proof |
| Any of these, when no verifier runs on this language | Generated-input tests of the real code, not a hand model of the function, and no `formal-<area>` skill |

No tool is the default. Which model checker, verifier or proof assistant fits is decided for this
repository, in this order:

1. **Recorded.** The area's own `formal-<area>` skill names one under `## Tool and why`: use it.
2. **Already in use.** Another `formal-*` skill here records a tool for a like question, or the
   repository's instructions, conventions or build already run one: recommend it first.
3. **Researched.** Otherwise find the candidates for this language and question with
   `/discovery:research` (if installed; otherwise read each candidate's official documentation),
   and weigh whether it runs on the code's language, what it can and cannot express, the cost of a
   run, and whether the repo's developers can install and run it.

Prefer a tool that the repo's developers can install and run, and tell the user why you chose it.
Attended, recommend one with its reason, name the others you weighed, and ask. Record the answer only
in the area's `## Tool and why`, never in this plugin or a settings file. A later `create` reads it
there.

For the recommended tool, also tell the user who installs it: this plugin's
`/formal-verification:setup` when this plugin's `prerequisites.json` declares it, otherwise the
user, from the tool's official install page, which you name.
