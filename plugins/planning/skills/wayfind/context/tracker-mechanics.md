# Tracker mechanics: the `/work-items:track` actions

`/planning:wayfind` operates the map through the `work-items` plugin's `/work-items:track` actions,
invoked via the Skill tool. The bound tracker adapter owns every provider command, so wayfind names
operations, never a tracker's commands
([ADR 0060](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0060-abstract-provider-details-in-skills-behind-consumer-conventions-and-adapters.md)).
Item references below are the qualified IDs those actions return (`<provider>:<owner>/<repo>#<n>`
on GitHub). Texts (a map body, a resolution, a comment) go in files written with the Write tool and
are passed by path, never typed into a command.

**Without the `work-items` plugin**, wayfind cannot read or write the tracker. Say so and stop; never
improvise provider commands. Where the consuming project routes tracker writes through a bot
identity or wrapper, the adapter's identity policy applies it; the claim always runs on the session
identity.

The tracker must support sub-items and blocked-by edges. When an action reports the provider cannot
(exit `6` from the seam, for example `list --parent` on a read-only Jira binding), stop and report
that this tracker cannot hold a decision map.

## Resolve the container label (once per session, before any map read or write)

The map marker is the **container label** the work-item tracker seam defines, the same
`config.container_label` binding key, same shipped default (`work-items` CONTRACT.md,
"Containers and state"). Resolving it here instead of hardcoding `work-map` keeps wayfind
maps and decompose containers on ONE marker: a repo that remaps the label would otherwise
strand wayfind maps on the old string, where the seam's frontier exclusion no longer
matches them and `/work-items:work-loop` would surface a map as a claimable item.

```shell
# Same key + same type rule as the seam's lib/binding.sh: absent/empty → shipped default;
# a PRESENT non-string value is a configuration error, never a silent fallback.
ROOT=$(git rev-parse --show-toplevel)
t=$(jq -r '.config.container_label | type' "$ROOT/.work-item-tracker.json" 2>/dev/null || echo null)
case "$t" in
  string) CONTAINER_LABEL=$(jq -r '.config.container_label' "$ROOT/.work-item-tracker.json" 2>/dev/null) ;;
  null)   CONTAINER_LABEL= ;;   # no binding, no key, or jq missing
  *)      echo "ERROR: config.container_label must be a string (got $t). Fix .work-item-tracker.json" >&2
          # Real stop — works sourced or standalone; never proceed with a coerced label.
          return 1 2>/dev/null || exit 1
          ;;
esac
CONTAINER_LABEL=${CONTAINER_LABEL:-work-map}
# The label is copied into single-quoted action arguments, so refuse a quote or control character.
case "$CONTAINER_LABEL" in
  *"'"* | *[[:cntrl:]]*) echo "ERROR: config.container_label holds a quote or control character" >&2
                         return 1 2>/dev/null || exit 1 ;;
esac
```

`<container-label>` below is that value; prose that says `work-map` means the shipped default.
Wayfind reads the binding file directly, so the type check above repeats the seam's rule on this
path rather than assuming the seam already ran. On the ERROR branch, stop and report instead of
creating anything.

## Find open maps

`/work-items:track list --label '<container-label>' --state open`. Name each map by title, ID as a
suffix.

## Check labels (first use in a repo)

`/planning:wayfind` uses its own taxonomy: the container label (default `work-map`), `wayfind: research|interview|design|prototype|task`
(axis labels follow the colon-space grammar so label-as-code owners with a `prefix: value` convention
can declare them verbatim), `needs-human`. At chart-mode entry, **verify** the taxonomy is present,
because creating an item with an unknown label fails:

`/work-items:track labels '<container-label>' 'wayfind: research' 'wayfind: interview' 'wayfind: design' 'wayfind: prototype' 'wayfind: task' needs-human`

It prints one `MISSING: <name>` line per absent label. Read the consuming repository's instructions
and configuration for label ownership. If they declare a label-as-code source of truth, treat that
declared system as the writer, report the exact missing set to its owner, and stop. If no
ownership policy is declared, report the missing set and ask the user how labels are provisioned.
The plugin never assumes an organization or provisioning repository and never creates labels ad
hoc.

## Create / extend the map

`/work-items:track add --label '<container-label>' --body-file <map-body.md> "Map: <effort>"`, adding
`--label` for any repo program labels. Body per [`map-anatomy.md`](map-anatomy.md). Extending an
existing map edits its body: read it with `/work-items:track view <map-id>`, change the section, and
write the whole body back with `/work-items:track edit <map-id> --body-file <path>`.

A map is never assigned and never carries a claim label: it is a container, not a work item.

## Create a typed decision item (a child of the map)

`/work-items:track add --parent <map-id> --label 'wayfind: <research|interview|design|prototype|task>' --body-file <item-body.md> "<sharp question>"`

The body says what must be decided, the options if known, and for a `prototype` item whether it is
logic or UI. Materialize the mode at creation: add `--label needs-human` for `interview`, `design` and
`prototype` (the default); leave it off for `research` (autonomous-capable); decide per item for
`task`. Create a blocker before the items it gates and pass `--blocked-by <blocker-id>` on those
items.

## Wire a dependency edge (only where one decision genuinely gates another)

At creation, `--blocked-by` as above. Between existing items:
`/work-items:track edit <item-id> --blocked-by <blocker-id>`.

Never invent edges to impose order. An edge means the blocker's resolution is a genuine
precondition for phrasing or answering the dependent decision.

## Compute the frontier

`frontier = open ∧ zero OPEN blockers ∧ unassigned` (in non-interactive sessions, also
`∧ NOT needs-human`):

List every child with `/work-items:track list --parent <map-id>` and keep the items that are open,
have no assignee, and have `blocked_by_count - blocked_by_wont_do_count == 0`; in a non-interactive
session also drop items labeled `needs-human`. Derive it here rather than with `/work-items:track
frontier`, whose count keeps a blocker closed as not planned blocking: a wayfind blocker closed as
moot or out of scope no longer gates its dependent, so the dependent rejoins the frontier. The same
listing, closed items included, serves the map hygiene checks.

## Claim a frontier item (the `work-items` claim model, one model across both)

`/work-items:track start <item-id>`. It reclaims a stale lease first, then claims race-safely
(assignee plus a lease comment, with a back-off when another session claimed first) on the session
identity. When it reports that another session won, pick the next frontier item; never retry the
same one. A decision item carries no branch, so ignore the branch name `start` suggests.

Session-start reclaim: `/work-items:track audit` runs the seam's idempotent `reclaim` over every
assigned item in the repository, not only the map's, so it releases a stale hold of yours on a map
item along with any other stale lease; it also runs the audit's other read passes.

## Graduate + close a decision item

In-scope close-out is atomic: comment → Decisions-so-far → close. A wrongly scoped item
(on the tracker but not this effort) closes with one Out-of-scope line and no
Decisions-so-far pointer: see the Decisions-so-far / Out-of-scope sections in
[`map-anatomy.md`](map-anatomy.md).

- **In scope:**
  1. Resolution comment on the item, the decision's durable home:
     `/work-items:track edit <item-id> --comment-file <path>` with `Resolved: <decision>. Basis: <one line>`.
  2. Add the one-line pointer to the map's Decisions-so-far index (edit the map body as under
     "Create / extend the map").
  3. Close the item: `/work-items:track done <item-id> --summary "Resolved; see the resolution comment."`
     Closing removes it from the frontier; the claim is assignee plus lease, no label to clear.
- **Wrongly scoped:** the Out-of-scope line on the map first (no Decisions-so-far pointer), then,
  only after that map update succeeds, `/work-items:track done <item-id> --not-planned --summary "Out of scope for <map title>."`
- **Moot** (another resolution invalidated its premise), no line in either index:
  `/work-items:track done <item-id> --not-planned --summary "Moot: <link to the resolution comment>"`.

## Close the map (frontier empty ∧ all items closed)

`/work-items:track done <map-id> --summary "Destination coherent, handed to </planning:interview | /planning:prd | /planning:plan>."`
