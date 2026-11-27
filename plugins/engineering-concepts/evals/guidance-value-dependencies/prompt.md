---
description: "Value test, not for merge: does the team's design guidance change a library choice and its abstractions? Compare run, merge base (no guidance skill) against head (design-guidance skill). Graders check the abstraction-name, swappable-dependency and free-default positions in the reply."
tags: [engineering-concepts, guidance-value]
max_turns: 8
timeout_seconds: 300
expected_outcome: "Interfaces carry no vendor names, each dependency is swappable behind one, and the default providers are free and need no key, paid ones opt-in."
---

We need to add outgoing email and PDF invoice generation to a .NET web app that other teams will also install and run. Pick the libraries or services, and sketch the interfaces and class names the app code will call. Before you answer, use any design guidance our installed skills offer. Keep it under 500 words.
