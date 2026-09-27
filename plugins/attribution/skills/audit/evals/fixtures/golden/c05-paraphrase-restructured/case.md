# How work gets picked up, and what happens when it runs out of memory

Ordering is decided twice. First by what depends on what, and then, among the tasks that are all
equally ready, by where they appear in the manifest. How many run at once tracks the machine's
core count until `--jobs` says otherwise.

Memory is treated differently from every other failure. Blowing the declared budget ends the
task with an over-budget report and no second attempt, on the reasoning that a second attempt
would consume the same memory the first one did.
