# Run marker

The destructive guard gates only while a mutating clean run is open in the session. The marker is a
file, `<plugin-data>/clean-run/<session-id>.open`, holding the epoch second of its last write.

## Open

Right after the action resolves, for every action except `scan` and `scan-batch`, before the first
dry-run or `--apply`:

```bash
bash <skill-dir>/scripts/clean-run-marker.sh open --tier <resolved-action> --session <session-id> --data-dir <plugin-data>
```

`scan` and `scan-batch` exit 0 with `Marker: not armed` and write nothing. Any other failure (exit 2:
the data directory or session id did not resolve) means the guard cannot be scoped to this run: stop
and tell the user rather than continuing without it.

## Clear

When the run reaches its final outcome (applied, declined at the confirmation gate, or aborted):

```bash
bash <skill-dir>/scripts/clean-run-marker.sh close --session <session-id> --data-dir <plugin-data>
```

It succeeds when the marker is already gone. Until it runs, the guard keeps gating every Bash and
PowerShell call in the session.

## Idle timeout

The guard refreshes the marker on each call that names one of the skill's mutating scripts (a
dry-run included, and even when the marker is idle past the hour, so a long confirmation gate
still reaches its apply gated) and on each acknowledged or destructive call. Ordinary shell calls
leave it alone. A marker idle for an hour is deleted by the next ordinary call, which then allows
the command. This covers a run that ended without the clear step.
The guard stays armed, ignoring the marker, when `CLAUDE_PLUGIN_DATA` is empty in the hook process or
the hook input carries no usable `session_id`.
