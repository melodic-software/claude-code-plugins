---
bump: patch
---

### Security

- The babysit-loop telemetry upsert reads its body file only when it resolves under `--body-dir` (or a `CLAUDE_PLUGIN_DATA` that names source-control): a symlink or an outside path exits 3 before any read, so a prompt-injected path can no longer post a credential file as a public comment. The reference now passes `--body-dir "${CLAUDE_PLUGIN_DATA}"`.
- The body is scanned with the shared leak scan before any API call and withheld whole on a hit (exit 3), naming the rule and never the match. The upsert now needs node.
- An unset lane instance falls back to a random id kept in the body dir instead of the hostname, which the public marker published. Comments written under a hostname marker are no longer found, so the next cycle starts a new one; the old comment keeps the hostname it already published.
