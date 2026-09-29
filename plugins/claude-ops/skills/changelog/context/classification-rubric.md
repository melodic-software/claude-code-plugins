# Classification rubric for CC changelog items

Every changelog item gets one action lens per owner surface it touches. A lens says what the repo should do about a component, not how important the item is. Surfaces to check are listed in `repo-surfaces.md`.

## Lenses

| Lens | Meaning | Row | Outcome |
|---|---|---|---|
| **correct** | A component states something now false. Covers scripts and fixtures that encode a claim, not only prose. | Decision row stating the false-versus-true pair | Fix the component |
| **replace** | A custom component where Claude Code now ships a native surface. Widened: a harness behavior that overlaps a component with no routable native surface also counts. | Decision row stating the problem the component solves | Nominate the native surface; with no routable native surface, keep the component and re-rationalize it |
| **adopt** | The item solves a problem a component works around or lacks. | Decision row stating the problem solved | Adopt, decline, or defer pending probe |
| **note** | Worth knowing, changes no component. | One line under the decision table | None |
| **skip** | Cosmetic, internal, or irrelevant to the repo. | None. Counts toward the read | None |

A skip item leaves no row and no line; only the count in the read summary shows it was seen.

### correct

- Grep finds the item's feature, field, event or flag in a component, and the item changes what is true about it
- A bug the component documents as a quirk is fixed upstream, or a deprecation or removal hits something the component uses
- A recheck trigger on a component fires

The row names the claim as the component states it (false) and as the item states it (true). A row without both halves is not a correct row.

### replace

- A component reimplements what a native command, skill, setting, hook event or frontmatter field now does
- A harness behavior now overlaps a component that no native surface can replace one-for-one. The outcome is keep, and the row re-rationalizes the component against the new behavior

The row names the problem the component solves, so the reader can judge whether the native surface solves the same one. A run never edits or removes the component: a replace candidate is nominated to `/claude-ops:audit-native-overlap`, which owns the decision. That gate compares skills and agents; a candidate on another owner surface (script, hook, rule, doc, setting) waits as `nominated` in the ledger until the gate can represent it.

### adopt

- A new frontmatter field, hook event, flag or setting removes a workaround the repo carries or supplies something it lacks
- A platform improvement makes a deferred feature tractable

The row names the problem solved. "We do not use it yet" is never a reason to skip; the problem the component works around is the test.

An adopt row may read **defer pending probe** when the item's behavior is not yet established. The evidence bar for leaving defer is one of:

- a documentation page states the behavior, or
- a live probe shows it

A changelog line alone does not meet the bar.

### note and skip

- Security fixes and model-specific changes are never skip. Check the repo's trust posture and model-routing docs; the result is correct, adopt or note
- A fix for a feature the repo does not use is skip, unless it unblocks something the repo declined for lack of that fix, which is adopt
- A deprecation of something the repo does not use is skip
- An experimental feature is note unless it solves a problem a component works around, which is adopt with defer pending probe
- Plugin-system changes are checked against `enabledPlugins` in settings.json

## Source precedence

The changelog is the newer statement of behavior. The documentation page stays the authority for syntax and shape until a live probe settles it.

A correct row that rests on a changelog line the docs do not yet state:

1. cites the newer source (the changelog entry)
2. names the disagreement with the docs page

The changelog-versus-docs pair also goes to the docs-lag section of the read. That section is handed to `/claude-ops:known-issues` when that skill is installed; a docs-lag entry is never a decision row.
