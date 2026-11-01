---
bump: patch
---

### Security

- The lanes telemetry upsert scans the body it would post, from a file or stdin, with the shared leak scan before any API call, and withholds it whole on a hit (exit 3), naming the rule and never the match. It now needs node.
- A `--marker` whose instance the leak scan reads as a fleet or private hostname exits 3 before any API call, naming the instance rather than the body.
