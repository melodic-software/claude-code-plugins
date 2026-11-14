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
that this tracker cannot hold a map.

Every link written into a map body, item body or comment is an absolute URL (an item's web URL,
not a qualified ID or a bare `#<n>`).

`<prefix>` and `<human-gated>` below are the labels SKILL.md "Pre-computed context" resolved from
the tracker binding.

## Find open maps

`/work-items:track list --label '<prefix> map' --state open`. Name each map by title, ID as a
suffix.

## Check labels (first use in a repo)

`/planning:wayfind` uses its own taxonomy: `<prefix> map`, `<prefix> research|interview|design|prototype|task`
(axis labels follow the colon-space grammar so label-as-code owners with a `prefix: value` convention
can declare them verbatim), `<human-gated>`. At chart-mode entry, **verify** the taxonomy is present,
because creating an item with an unknown label fails:

`/work-items:track labels '<prefix> map' '<prefix> research' '<prefix> interview' '<prefix> design' '<prefix> prototype' '<prefix> task' '<human-gated>'`

It prints one `MISSING: <name>` line per absent label. Read the consuming repository's instructions
and configuration for label ownership. If they declare a label-as-code source of truth, treat that
declared system as the writer, report the exact missing set to its owner, and stop. If no
ownership policy is declared, report the missing set and ask the user how labels are provisioned.
The plugin never assumes an organization or provisioning repository and never creates labels ad
hoc.

## Create / extend the map

`/work-items:track add --label '<prefix> map' --body-file <map-body.md> "Map: <effort>"`
(the `<prefix> map` label is what keeps the map out of triage and claimable work; a map never
carries the work-items container label, which marks a spec container), adding
`--label` for any repo program labels. Body per [`map-anatomy.md`](map-anatomy.md). Extending an
existing map edits its body: read it with `/work-items:track view <map-id>`, change the section, and
write the whole body back with `/work-items:track edit <map-id> --body-file <path>`.

A map is never assigned and never carries a claim label: it is a container, not a work item.

## Create a typed decision item (a child of the map)

`/work-items:track add --parent <map-id> --label '<prefix> <research|interview|design|prototype|task>' --body-file <item-body.md> "<topic>"`

The body holds the question and the criteria an answer must meet, and for a `prototype` item
whether it is logic or UI, laid out as [`map-anatomy.md`](map-anatomy.md) "Prototype item body"; it never states the type, which the label carries. Materialize the mode at creation:
add `--label '<human-gated>'` only when the item needs the user's intent or vision, whatever its type
(SKILL.md "Readiness"). Create every item first, with no reference to another item in its body.

## Wire edges and cross-references (second pass, real ids only)

Once every item of the pass exists, wire each edge with
`/work-items:track edit <item-id> --blocked-by <blocker-id>` and add any cross-reference to an
item body by editing it with the other item's absolute URL. Never write a placeholder number: a
guessed `#<n>` links to an unrelated issue.

Never invent edges to impose order. An edge means the blocker's resolution is a genuine
precondition for phrasing or answering the dependent decision.

## Compute the frontier

`frontier = open ∧ zero OPEN blockers ∧ unassigned` (in non-interactive sessions, also
`∧ NOT <human-gated>`):

Read the map body with `/work-items:track view <map-id>` and list every child with
`/work-items:track list --parent <map-id>`; open a child's body with `view` only when the step at
hand needs it. Keep the items that are open, have no assignee, and have
`blocked_by_count - blocked_by_wont_do_count == 0`, ordered by creation (ascending item number);
in a non-interactive session also drop items labeled `<human-gated>`. Derive it here rather than with `/work-items:track
frontier`, whose count keeps a blocker closed as not planned blocking: a wayfind blocker closed as
moot or out of scope no longer gates its dependent, so the dependent rejoins the frontier. The same
listing, closed items included, serves the map hygiene checks.

## Claim a frontier item (the `work-items` claim model, one model across both)

Before claiming a `<human-gated>` item, count the map's open children that carry `<human-gated>`, do
not carry `<prefix> research`, and are assigned to the session identity (the person the claim
would assign), from the same listing; other assignees' items do not count. At `wayfind_hitl_concurrency` or more, do not claim it.
Two sessions can both pass that count before either claims, so once a `<human-gated>` claim
succeeds, list the children again and recount. Over the limit, rank the counted claims by claim
order: read each one's active lease comment id (a counted item with no lease comment yet ranks
last), and the `wayfind_hitl_concurrency` earliest ids keep the slots. When yours is not among
them, back off: `release` the lease with the `lease_comment_id` the claim returned (on exit `6`
the lease waits out its TTL), clear your assignee, and pick again from the frontier (no other
`<human-gated>` item while the slots stay full). This holds because a claimant recounts only after
posting its own lease, so the later of two claimants always sees the earlier lease and is the one
that backs off; an earlier claim never needs to recheck.

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

## Graduate a research item

After `/discovery:research` returns for a research item:

1. Copy the findings file and its sidecars into the item's folder on the map's dossier branch,
   creating the branch on first use and linking it from the map's Notes (SKILL.md "Shared files").
2. Commit and push with the push sequence in SKILL.md "Shared files".
3. Post the resolution comment in the research shape ([`map-anatomy.md`](map-anatomy.md)
   "Resolution comments"), linking the findings file on the branch.
4. Add the Decisions-so-far pointer and close the item, steps 2 and 3 of "In scope" above.

## Close the map (frontier empty ∧ all items closed ∧ Not-yet-specified empty)

`/work-items:track done <map-id> --summary "Destination coherent, handed to </planning:prd | /planning:plan | /work-items:decompose | /work-items:work | a decision record | the closing summary>."`
