# Telemetry comment upsert (per-instance singleton, race-converging)

The exact upsert this lane runs at cycle-shape step 6 to maintain its ONE sentinel-identified status
comment **for this lane instance**. `SKILL.md`'s "Telemetry and durable loop state" owns where the
comment lives and what goes in it; this file owns how the singleton is maintained and how a creation
race converges.

The upsert is inlined in this plugin rather than invoked from `claude-ops` because an installed
plugin cannot invoke a sibling plugin's scripts.

Per the convention's lane-instance identity rule, the marker names the **writer**, not the lane type
(#1295): a marker naming only the lane makes two concurrent instances resolve one comment and
clobber each other's durable state. The id is `${user_config.lane_instance}`; a surviving literal
`${user_config.…}` placeholder means the key is unset, so fall back to the sanitized lowercased
hostname (headless-config floor: log the assumption). It is operator-supplied text about to be
interpolated into a shell string and a `jq` program, so it is validated and **rejected**, never
sanitized-and-continued. Substitute the resolved value for `<lane-instance>`; the check runs before
`MARKER` is built. The hostname fallback is a *default*, not a sanitizer — it passes through the
same gate, so a hostname that cannot produce a conforming id stops the lane rather than yielding a
marker nobody chose:

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
SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"   # first line of $BODY_FILE
LOOKUP() { gh api --paginate "repos/$REPO/issues/$ISSUE/comments" \
  --jq ".[] | select(.body | startswith(\"$SENT\")) | .id"; }
if ! LIST=$(LOOKUP); then
  echo "telemetry: comment lookup failed; skipping upsert this cycle (fail closed)" >&2
else
  if [ -z "$LIST" ]; then
    gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" >/dev/null
    LIST=$(LOOKUP) || LIST=""   # re-list; a failure here converges next cycle
  fi
  CANON=$(printf '%s\n' "$LIST" | sort -n | head -n1)
  if [ -n "$CANON" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE"
    for DUP in $(printf '%s\n' "$LIST" | sort -n | tail -n +2); do
      gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
        -f body="Superseded duplicate - canonical telemetry comment: $CANON" || true
    done
  fi
fi
```

**Creation race reconcile (encoded above).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges every cycle
duplicates are visible: the LOWEST comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone so it never matches a lookup again — this
covers a racer that died between its POST and its own re-list, because the NEXT session's
ordinary upsert performs the same reconcile. A crashed racer's unmerged counters are an
accepted loss (durable state re-derives over a cycle); nothing is deleted. The reconcile converges
duplicates **within one instance's own sentinel set** — a sibling instance's comment carries a
different marker and never enters `$LIST`, so it is neither made canonical nor tombstoned.
