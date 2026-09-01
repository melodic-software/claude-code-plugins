# Seam phrasing — presence-gated cross-plugin references

Owner doc for the shared phrasing convention every optional cross-plugin reference uses.
The design rule it implements lives in the plugin philosophy's design boundary: optional
collaboration is presence-gated with a documented fallback, and a bare unguarded
cross-plugin reference is a defect. This doc owns the *phrasing shape*; the philosophy owns
the *rule*.

## The shape

Every optional reference to another plugin's skill carries, at the reference site:

1. **The gate** — an explicit installed-ness condition on the invocation:
   "invoke `/other-plugin:skill` (if that plugin is installed)" or an equivalent
   "when the `<name>` plugin is installed" clause. The gate names the plugin, not the
   marketplace (marketplace-qualified IDs never appear in reusable content outside
   install-recipe sites, for which see the carve-out below).
2. **The fallback** — what the skill does instead, stated in the same sentence or the one
   adjacent: degrade to a bundled capability, record into the artifact at hand, or report
   the missing optional capability clearly. "Skip silently" is not a fallback.
3. **Ownership framing** — when the collaborator owns a concern (a glossary, a tracker
   seam, a stage skill), the reference says what it owns so the fallback's scope is
   evident. Descriptive ownership tables need no gate when every invocation site nearby is
   gated; the gate belongs where the invocation is instructed.

### Install-recipe carve-out

An install-recipe site — the lines a skill prints so an operator can install an optional
plugin themselves — is the one place a marketplace-qualified ID belongs, because the
commands do not resolve without it: the operator has to add the marketplace before
`claude plugin install <plugin>@<marketplace>` can run at all.

The carve-out is scoped to that recipe text and nothing else. Element 1 is unchanged for
gates: an installed-ness condition still names the plugin alone, because a gate asks whether
a capability is present, not where the operator would obtain it. A skill that prints a recipe
therefore carries both shapes, a bare-plugin gate and a marketplace-qualified recipe beneath
it. The recipe is printed for the operator to run, never executed for them; the plugin
philosophy's setup contract owns that rule and this carve-out does not relax it.

## What this convention is not

- Not for hard requires: a plugin genuinely broken without its collaborator declares the
  native manifest `dependencies` entry instead, and needs no gate phrasing.
- Not a tool-availability check: probing for a CLI or MCP tool at runtime is the
  prerequisites-and-failure-behavior rules' territory.

## Conformance

Fleet audits check dim-11-adjacent seam phrasing against this shape: gate present, fallback
stated, no marketplace qualification outside an install-recipe site. Existing adopters
(work-items' tracker seam, claude-ops' known-issues reference, session-flow's stage-skill
preference, planning's glossary hand-off) conform by carrying all three elements at each
instructed invocation.
