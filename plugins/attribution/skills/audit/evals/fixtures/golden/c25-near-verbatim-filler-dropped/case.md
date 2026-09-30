# Runner feature notes

Part 3 (Mar 11, 2026). Notes from the team's runner walkthroughs; parts 1 and 2 are in the wiki.

## Cache warmers

Warmers prefill the workspace cache before the first task of the day. We schedule one per pool
and keep the list of warmed targets short.

---

## 21. Sandboxed Tasks

### Turn On Task Isolation

Opt into Widget Runner's open source isolation layer to improve safety while cutting approval prompts.

`widget isolate on` to enable. Isolation runs on your machine, supports file and network fencing.

**Modes:**

- Isolate every task, with auto-approve
- Isolate every task, with regular approvals
- No isolation

---

## 22. Dashboard

### Add a Dashboard

Custom dashboards show beside the task list. Show agent name, workspace, remaining cache quota, cost, anything else you want while a build runs.

Everyone on Widget Runner team has a different dashboard. `widget dash` to get started. Widget Runner generates one based on your `.widgetrc`.

---

## 23. Our pool names

We run `fast`, `heavy` and `release`. The names say what lands on each.
