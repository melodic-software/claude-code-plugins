# Sentence rules for task descriptions

Task descriptions are read by people in the middle of a failing build. The rules below follow
WCL-100, the Widget Controlled Language standard, revision 4. This file is a paraphrase and never
a substitute for the spec.

- One instruction per sentence. One idea per sentence everywhere else.
- Split instructions longer than about 18 words, and other sentences longer than about 24.
- Put the warning or condition before the step it guards: "If the lock file is stale, the build
  can hang."
- Name the agent pool in full on first mention, and abbreviate only after that.

Our own addition: write the expected duration at the end of a description, never the start.
