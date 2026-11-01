---
bump: patch
---

### Security

- The lane telemetry upsert reads its body file only when it resolves under `--body-dir` (or a `CLAUDE_PLUGIN_DATA` that names work-items): a symlink or an outside path exits 16 before any read, so a prompt-injected path can no longer post a credential file as a public comment. The work-loop and attend-queue references now pass `--body-dir "${CLAUDE_PLUGIN_DATA}"`.
- The body is scanned with the shared leak scan before any API call and withheld whole on a hit (exit 17), naming the rule and never the match. The upsert now needs node.
- An unset lane instance falls back to a random id kept in the body dir instead of the hostname, which the public marker published. Comments written under a hostname marker are no longer found, so the next cycle starts a new one; the old comment keeps the hostname it already published.
- A lane instance the leak scan reads as a fleet or private hostname (a `lane_instance` set to the machine name, or one carried in a resumed state block) exits 18 before any API call instead of failing the body scan every cycle; work-loop re-runs once with the stored random id.
