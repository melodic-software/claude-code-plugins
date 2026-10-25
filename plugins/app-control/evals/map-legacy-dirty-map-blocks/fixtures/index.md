---
description: "Read this feature map before driving Clockwork web."
disable-model-invocation: false
---

- Application: Clockwork web, built from `apps/web`
- Launch: `run-clockwork` (project skill)
- Driver: playwright, from docs/conventions/testing.yaml
- Doctor: `curl -fsS http://127.0.0.1:5180/healthz` prints `{"status":"ok","build":"<sha>"}`
- Isolation: one instance per port; set `CLOCKWORK_DB` to a scratch file per run
- Written at: 3f9c2a1

## Features

- Start a timer: `start-a-timer.md` (2 entry points)
