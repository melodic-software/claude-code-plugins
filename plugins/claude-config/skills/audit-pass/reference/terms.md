# audit-pass — run-contract terms

This file owns the run contract's shared vocabulary — the terms every other file in the contract uses
without redefining.

Full index: [run-contract.md](run-contract.md).

Finding identity, where the report lives, run state, resumability, the report schema, and the three
finding tiers with their properties. Every rule here is stated as a condition a test can assert.

Terms: a **run** is one invocation against one **target**; a **lane** is **one delegated invocation
at the finest filter that skill's own interface accepts**, never finer — the pass dispatches skills
and never reaches inside one, so a lane it cannot invoke is a lane it cannot have; the **scan set**
is the set of files a run reads. A surface is **live** when the
harness actually loads it for that target — read from `InstructionsLoaded` for the memory layer and
`/context` for skills, subagents, and MCP tools, never inferred from a filesystem walk alone. The
**live surface set** is every live surface at the moment a run starts; it can change without the tree
changing, because startup scope depends on the launch directory and on settings the tree does not
contain.
