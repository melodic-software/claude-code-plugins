# Decision lenses for Claude Code changelog items

The unit of a `diff` or `apply` is a decision about one of our components, not a
changelog item. Items are transient. A `skip` item counts toward the read and
leaves no row.

## Lenses

| Lens | Required sentence | What it means |
|---|---|---|
| `correct` | the false claim and the true one | A component states something the changelog makes false, including a script or fixture that encodes the claim |
| `replace` | the overlap, and that the row is nominated | A native surface, or a harness behavior with no routable native command, overlaps a component. Outcome is keep and re-rationalize until a human writes the native-surfaces verdict. The ledger state is `nominated`, never `replaced` |
| `adopt` | the problem solved | The upstream change solves a problem a component works around or lacks. `defer pending probe` is an adopt whose evidence bar is not met yet: a doc page states it, or a live probe shows it |
| `note` | optional one line | Worth remembering, not worth a component edit |
| `skip` | none | No row. UI chrome, an internal change, or a feature this repo does not and will not use |

`correct`, `replace`, and `adopt` rows name the owner surface (a file or a skill). Group rows that share an owner. Do not emit one row per changelog bullet.

## Source precedence

The changelog is the newer statement of behavior. The docs page stays the authority for syntax and shape until a live probe. A `correct` row cites the changelog for the behavior, names the disagreement, and the pair is listed under docs lag in the working set. Docs lag is not a decision row. Hand it to `known-issues` when that skill is installed.

**Claim:** behavior follows the changelog on the read date; syntax follows the docs page until a probe. **Basis:** this repository's upstream-drift convention (fetch the raw changelog markdown; do not treat a stale docs snapshot as newer than the changelog). **As of:** 2026-09-28. **Recheck:** a Claude Code release note says the docs page overrides the changelog for behavior, or the changelog page stops being the release record.

## Fan-out

Per release, give items stable ids. Explore in clusters of about fifty items. Research one cluster at a time: curl the page the item names and ground every claim. Repo-side checks stay local. There is no Workflow script. Cost scales with item count, which is why the replay cap stops a `diff` before this fan-out.

## Working set

`diff` writes the decision rows to `<memory>/claude-code-changelog/<range>/` through `scripts/decision-rows.sh --write`. `<memory>` is `CLAUDE_PLUGIN_DATA` when that variable is set, otherwise `.work` under the repository. `apply` reads that directory and re-fetches only what a recheck trigger names.
