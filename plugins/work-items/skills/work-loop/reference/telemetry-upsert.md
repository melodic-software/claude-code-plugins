# Telemetry comment upsert (per-instance singleton, race-converging)

How this lane maintains its one sentinel-identified status comment **for this lane instance**.
`SKILL.md`'s "Telemetry and durable loop state" owns where the comment lives and what goes in it;
[`../../../reference/lane-telemetry-upsert.md`](../../../reference/lane-telemetry-upsert.md) owns the
script's contract: its arguments, what it writes, its checks and its exit codes.

**Resolve the lane instance first.** The marker names the *writer*, not the lane type, per the
convention's lane-instance identity rule. Resolution order matches `SKILL.md`'s invocation surface
(cited from [invocation-argv.md](invocation-argv.md)): a supplied `--instance` token wins, else
persisted `lane_instance` from the durable state block, else `${user_config.lane_instance}`. Pass
the resolved value through; the script owns everything after that, including the stored random-id
fallback for an unset key and the validation that rejects a non-conforming or hostname-shaped id
(exit 18).

## Invocation

Run the script at the absolute path `SKILL.md`'s "Telemetry and durable loop state" gives for it:

```bash
bash "<upsert-script>" \
  --lane work-loop --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" --body-file "$BODY_FILE" --body-dir "<plugin-data>" \
  --app-slug '${user_config.lane_app_slug}'
```

`--app-slug` is always passed as `${user_config.lane_app_slug}`; a launch prompt that names a slug
overrides it. Keep the single quotes: an unset key reaches the script as an empty value or a
surviving literal placeholder, which it treats as absent.

## Instance-collision check (cycle start, before any write)

Run [lane-instance-collision-check.md](lane-instance-collision-check.md) after re-reading the state
block.
