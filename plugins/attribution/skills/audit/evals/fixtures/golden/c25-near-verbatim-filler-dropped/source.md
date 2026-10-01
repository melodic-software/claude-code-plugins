# Widget Runner: compiled tips

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/tips/compiled`.

## 21. Sandboxed Tasks

### Turn On Task Isolation

Opt into the Widget Runner open source isolation layer to improve safety while also cutting down on the approval prompts.

`widget isolate on` to enable. Isolation runs on your machine, and supports file and network fencing.

**Modes:**

- Isolate every task, with auto-approve
- Isolate every task, with regular approvals
- No isolation

---

## 22. Dashboard

### Add a Dashboard

Custom dashboards show beside the task list. Show the agent name, the workspace, the remaining cache quota, the cost, anything else you want while a build runs.

Everyone on the Widget Runner team has a different dashboard. Use `widget dash` to get started. Widget Runner generates one based on your `.widgetrc`.
