# babysit-loop telemetry upsert on GitHub

This file serves the babysit-loop
[telemetry-upsert spoke](../../../../skills/babysit-loop/reference/telemetry-upsert.md): it holds
the script that maintains the lane's status comment on a GitHub issue. The spoke owns the
instance-id rule, the `$BODY_FILE` contract, the three checks, the race reconcile and the
collision check. The [GitHub provider reference](../README.md) indexes the other operations.

## Upsert script

Substitute the resolved instance id for `<lane-instance>`, and set `$REPO` (`owner/repo`),
`$ISSUE` (the telemetry issue number) and `$BODY_FILE`.

```bash
INSTANCE="<lane-instance>"   # ${user_config.lane_instance}, else `hostname` sanitized
[ -n "$INSTANCE" ] || INSTANCE="$(hostname | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
# ^[a-z0-9][a-z0-9-]{0,31}$ — empty, a leading hyphen, any other character, or
# over 32 chars is REJECTED, never trimmed into something that looks valid.
case "$INSTANCE" in
"" | -* | *[!a-z0-9-]*)
  echo "telemetry: lane_instance '$INSTANCE' is not ^[a-z0-9][a-z0-9-]{0,31}\$; refusing to build a marker" >&2
  exit 1
  ;;
esac
[ "${#INSTANCE}" -le 32 ] || {
  echo "telemetry: lane_instance '$INSTANCE' exceeds 32 characters; refusing to build a marker" >&2
  exit 1
}
MARKER="source-control:babysit-loop@$INSTANCE"
SENT="<!-- harness-ops:lane-telemetry marker=$MARKER -->"   # $BODY_FILE MUST open with this line
LOOKUP() { gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" \
  --jq ".[] | select(.body | startswith(\"$SENT\")) | .id"; }
SENTINEL_OK() { # $1 = text; true iff line 1 is exactly $SENT and >=16 payload bytes follow
  [ "$(printf '%s' "$1" | head -c ${#SENT})" = "$SENT" ] &&
    [ "$(printf '%s' "$1" | tail -n +2 | wc -c | tr -d ' ')" -ge 16 ]
}
VERIFY() { # $1 = comment id; re-read what LANDED, whatever form the write took
  BACK="$(gh api "repos/$REPO/issues/comments/$1" --jq '.body' 2>/dev/null | tr -d '\r')" &&
    SENTINEL_OK "$BACK"
}
if [ ! -s "$BODY_FILE" ] || [ "$(head -c 1 "$BODY_FILE")" = "@" ]; then
  echo "telemetry: body is empty or a literal @path - nothing written; fix the body composition, do not re-run blind" >&2
elif ! SENTINEL_OK "$(cat "$BODY_FILE")"; then
  echo "telemetry: body is not sentinel-prefixed or carries no payload - nothing written; fix the body composition, do not re-run blind" >&2
elif ! LIST=$(LOOKUP); then
  echo "telemetry: comment lookup failed; skipping upsert this cycle (fail closed)" >&2
else
  if [ -z "$LIST" ]; then
    gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" >/dev/null || true
    LIST=$(LOOKUP) || LIST=""   # re-list; a failure here converges next cycle
  fi
  CANON=$(printf '%s\n' "$LIST" | sort -n | head -n1)
  if [ -z "$CANON" ]; then
    echo "telemetry: no comment available to write to (a create may have landed but was not re-found) - treat the lane as UNREPORTED and carry that forward to the next cycle" >&2
  elif ! gh api -X PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE" >/dev/null; then
    echo "telemetry: the PATCH of comment $CANON failed - treat the lane as UNREPORTED and carry that forward to the next cycle; the comment holds an earlier body, not this cycle's write" >&2
  elif ! VERIFY "$CANON"; then
    echo "telemetry: comment $CANON does NOT carry a well-formed telemetry body after the write - treat the lane as UNREPORTED and carry that forward to the next cycle; do not trust the timestamp" >&2
  else
    for DUP in $(printf '%s\n' "$LIST" | sort -n | tail -n +2); do
      gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
        -f body="Superseded duplicate - canonical telemetry comment: $CANON" || true
    done
  fi
fi
```

`gh api -f body=@FILE` transmits the literal path as the body, so the script only ever uses
`-F body=@`, which reads the file. The read-back (`VERIFY`) is the check that would catch the
`-f` form.
