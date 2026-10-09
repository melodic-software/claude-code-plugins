# user-experience

Front door for user experience on the app being built, at any stage: an idea with no code, a new
build, an existing app or a legacy one. It helps an agent, and the person driving it, work out who
uses the app and what they need. It uses the project's own research, personas and analytics first,
routes to the tools installed, and labels every deliverable evidence-based, assumption-based or
mixed.

| Skill | What it does |
|---|---|
| `/user-experience:shape` | Detect the app's stage and the project's own evidence, then hand the job to the right skill |
| `/user-experience:plan-user-research` | Plan user research and write its instruments, starting with a discussion guide |

The routes live in [`reference/routing.json`](reference/routing.json), validated by
[`reference/routing.schema.json`](reference/routing.schema.json).
[`scripts/detect.mjs`](scripts/detect.mjs) reports the project's signals and which routes are
installed. Every deliverable follows [`reference/deliverable.md`](reference/deliverable.md).
