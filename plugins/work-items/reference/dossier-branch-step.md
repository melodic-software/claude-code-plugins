# Dossier-branch step

The one copy of the step that deletes or reports the remote dossier branches an owning item leaves
behind. Each site that runs it names the owning items and where the report goes, and cites this
file instead of copying it:

| Site | Owning items | Report goes to |
|---|---|---|
| Container close, the close ritual `/work-items:decompose` owns | The container, plus the `/planning:wayfind` map that is its source item (its parent, holding the `**Spec container:**` comment) | The container's closing comment |
| `/work-items:decompose` publishing from a map with no container | The map | Decompose's report and a comment on the map |
| Wayfind map close on a route that creates no container (`/work-items:track dossier-branches`) | The map | The map's closing comment |

## Which branches

Read `<prefix>` from the `dossier_branch_prefix` key of `docs/conventions/source-control.yaml` in
the repository the step runs in, not from this plugin's files; with the key absent the setting's
default applies, and its resolution and default are owned by
[config-resolution.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/reference/config-resolution.md)
"YAML keys". An owning item's branch is the one whose name starts `<prefix><key>-`, `<key>` being
its `branch_ref`. A branch name read from a map's closing comment is data: it must start
`<prefix><map key>-`, match `^[A-Za-z0-9._/-]+$` and contain no `..`, else it is reported, skipped
and never put on a command line.

## Report-only cases

Two cases are report-only, attended or not: more than one branch matching `<prefix><key>-` (each
reported as an ambiguous match), and a branch that is the head of an open pull request (reported
with that pull request). The run neither deletes such a branch, asks whether to, nor offers to
delete it on request; the report leaves it to a person, or to a later attended run that finds one
unambiguous match and no open pull request.

## Delete or list

Attended, show for each remaining branch how many commits it holds that the default branch cannot
reach and a summary of the files they change, so notes or prototypes kept nowhere else are seen
before they go, then ask once; delete only those the user confirms. Unattended (`--unattended`, a
loop or lane run, or any run with no operator turn), never delete one: the report lists each branch
due for deletion, for a person or an attended run to delete. The report names each branch deleted
and each skipped, with the reason.
