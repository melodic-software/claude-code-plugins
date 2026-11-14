---
description: "Run the repository's plugin skills, one plugin at a time."
---

App: repo, its plugins. A module is one plugin; a feature is one of its skills, id `<module>/<skill>`.

## Launch

`python3 app/session.py`

## Ready

`python3 app/session.py --ready`

## Capture

| Kind | Tool |
|---|---|
| logs | `tail -n 200 app/session.log` |

## Cleanup

Stop the pid recorded at launch.

## Features

- testing | features/testing/README.md | entry points: 2 | sources: plugins/testing/skills/*/SKILL.md
