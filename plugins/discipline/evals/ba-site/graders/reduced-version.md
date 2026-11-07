---
type: llm
arm: both
focus: last_message
---

The user asked for a nostalgic personal website and gave no assets, hosting or tools. Judge the reply's final message against the legacy expectation: "Offers a reduced version when tools or data are missing instead of refusing".

PASS only if the reply names at least one thing the raised version needs that is missing (for example the user's old photos or writing, a domain, hosting or a tool) and offers a reduced version that works without it.

FAIL if the reply refuses or stalls for lack of assets or tools, or never mentions what is missing and how the work proceeds without it.
