# Telemetry comment upsert (per-instance singleton, race-converging)

How this lane maintains its one sentinel-identified status comment **for this lane instance**.
[`../SKILL.md`](../SKILL.md)'s "Telemetry" section owns that the comment exists and when it is
written; [`../../../reference/lane-telemetry-upsert.md`](../../../reference/lane-telemetry-upsert.md)
owns the script's contract: its arguments, what it writes, its checks and its exit codes.

Per the convention, this lane too maintains exactly one sentinel-identified status comment **per
lane instance** on its per-lane tracking issue in the target repository (default title
`Lane telemetry: attend-queue`, created through the seam `create-item` verb when absent), edited in
place each pass with the rows handled, the answers written, and the guard mode. Same script as the
worker loop. The marker names the writer, not the lane type, so two attended sessions on one
repository never overwrite each other's pass record. Resolve the instance from
`${user_config.lane_instance}` and pass it through; the script owns everything after that,
including the stored random-id fallback for an unset key and the validation that rejects a
non-conforming id.

## Invocation

```bash
bash "<plugin-root>/scripts/lane-telemetry-upsert.sh" \
  --lane attend-queue --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" --body-file "$BODY_FILE" --body-dir "<plugin-data>"
```

Add `--app-slug <slug>` under an App installation token. The `lane_app_slug` key feeds the
work-loop lane only, so here the launch prompt supplies it.

## What this lane adds

A lane without durable loop state carries an UNREPORTED outcome in the pass's own summary.

Report the instance on its own `instance:` line in the pass report, never appended to `lane:`: the
telemetry reader's lane capture is `[a-z0-9_-]+` and would truncate the suffix. This lane carries no
durable-state block, so the convention's instance-collision check does not bind here; the marker
partition alone is sufficient because an operator is present by definition and a duplicate id
surfaces to them in the same pass.

When the bound provider is not `github`, this upsert is unavailable: carry the same telemetry
content in the lane's pass report/log instead, with a notice that the comment surface is absent.
