# Telemetry comment upsert (singleton, race-converging)

The exact upsert this lane runs at cycle-shape step 6 to maintain its ONE sentinel-identified status
comment. `SKILL.md`'s "Telemetry and durable loop state" owns where the comment lives and what goes
in it; this file owns how the singleton is maintained and how a creation race converges.

The upsert is inlined in this plugin rather than invoked from `claude-ops` because an installed
plugin cannot invoke a sibling plugin's scripts.

```bash
MARKER="source-control:babysit-loop"
SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"   # $BODY_FILE MUST open with this line
LOOKUP() { gh api --paginate "repos/$REPO/issues/$ISSUE/comments" \
  --jq ".[] | select(.body | startswith(\"$SENT\")) | .id"; }
SENTINEL_OK() { # $1 = text; true iff it opens with $SENT and carries a payload under it
  [ "$(printf '%s' "$1" | head -c ${#SENT})" = "$SENT" ] &&
    [ "$(printf '%s' "$1" | wc -c | tr -d ' ')" -ge $((${#SENT} + 17)) ]
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
    gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" >/dev/null
    LIST=$(LOOKUP) || LIST=""   # re-list; a failure here converges next cycle
  fi
  CANON=$(printf '%s\n' "$LIST" | sort -n | head -n1)
  if [ -n "$CANON" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE"
    VERIFY "$CANON" ||
      echo "telemetry: comment $CANON does NOT carry a well-formed telemetry body after the write - treat the lane as UNREPORTED and record it in durable state; do not trust the timestamp" >&2
    for DUP in $(printf '%s\n' "$LIST" | sort -n | tail -n +2); do
      gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
        -f body="Superseded duplicate - canonical telemetry comment: $CANON" || true
    done
  else
    echo "telemetry: the write left no sentinel-prefixed comment to verify - treat the lane as UNREPORTED and record it in durable state; the next cycle retries the create" >&2
  fi
fi
```

**`$BODY_FILE` contract.** The file's FIRST line must be exactly `$SENT`, with the cycle's telemetry
below it. The lookup matches on that prefix, so a body composed without it is not merely rejected here
— it would never be found again, and the next cycle would post a second comment. Compose the sentinel
into the file; do not rely on anything downstream to add it.

**Body gate and post-write verification (encoded above, #943).** Two halves, because they catch
different failures. The **pre-write** assertions run before any API call and reject a `$BODY_FILE`
that is empty, opens with a literal `@`, is not sentinel-prefixed, or carries under 16 bytes of
payload — the mechanical form of the `@path`-as-body rule owned by the `claude-ops` lanes skill
("Never pass a body as an `@path` string"). The **post-write** `VERIFY` re-reads what actually landed,
which is what catches the failure the pre-write half structurally cannot: a correctly composed file
sent through a body-value flag (`-f body=@"$BODY_FILE"`) rather than `-F body=@`, where `gh` transmits
the literal path and the file itself was never at fault.
On the first-ever upsert the same cycle's PATCH is what verifies the create, so a POST that lands
degraded carries no sentinel, the re-lookup finds nothing, and there is no comment to re-read. That
path reports UNREPORTED as well rather than passing silently, and the next cycle retries the create.

A degraded body that lands still moves the comment's timestamp, so any check keying on `updatedAt`
reads the lane as **fresh** while it carries nothing. Refusing, or reporting the write UNREPORTED,
is what keeps that from passing silently. Not replicated from the wrapper: the 64 KiB cap and the
body-file containment checks.

**Creation race reconcile (encoded above).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges every cycle
duplicates are visible: the LOWEST comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone so it never matches a lookup again — this
covers a racer that died between its POST and its own re-list, because the NEXT session's
ordinary upsert performs the same reconcile. A crashed racer's unmerged counters are an
accepted loss (durable state re-derives over a cycle); nothing is deleted.
