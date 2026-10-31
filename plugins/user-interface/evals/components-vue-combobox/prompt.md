---
schema_version: "1.1"
name: components-vue-combobox
description: "Hard (the model tends to name one library from memory): Written from MB:plugins/user-interface/reference/component-libraries.md:3-8. For a Vue app the choice turns on stated criteria and the stack's current options, checked at the time of the choice, not a recalled name. Head names a primitives default for React only, so a Vue prompt takes the rule both versions share."
tags: [web, components, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply advises against hand-rolling the combobox, gives the accessibility criteria the choice turns on, recommends no React-only library, and says to confirm current Vue options from the ecosystem or official docs"
---

Our Vue 3 app needs a combobox (an autocomplete select) for picking a customer. Should I build it
myself or use a library, and if a library, which one? Answer in under 250 words.
