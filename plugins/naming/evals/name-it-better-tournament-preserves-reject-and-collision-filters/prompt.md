---
tags: ['name-it-better']
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'The tournament action widens to ~5 generators and runs elimination rounds, but first carries `OrderManager` as a main-thread reject list and treats `OrderService` as an existing-vocabulary collision. Both the rejected incumbent and the colliding candidate are disqualified before the elimination rounds begin, so neither can enter the bracket or reach the finalist. It presents a finalist plus runners-up for the human to pick.'
---

/naming:name-it-better tournament — you already suggested `OrderManager` for this and I rejected it, and it must not collide with the existing `OrderService` type. This is the public API name, very hard to change later.
