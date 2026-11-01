---
tags: ['curate-language']
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
expected_outcome: 'Finds no convention, resolves the glossary settings, and proposes a GLOSSARY.md for the Fulfillment context (opening with a short description of the context, the Shipment entry under it), naming the layer that supplied the name. It asks the user to confirm the proposal before writing any file and proposes no GLOSSARY-MAP.md, since only one context exists.'
---

/domain-driven-design:curate-language We resolved that a Shipment is one physical consignment handed to a carrier, never a single order line. The repo has one bounded context, Fulfillment, under src/fulfillment, and no glossary, context map or vocabulary convention anywhere. I'm here if you need me.
