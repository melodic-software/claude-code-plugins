# Lane: shell-tooling

Bash and PowerShell scripts. **Agent-hook and git-hook script directories are HARD-EXCLUDED for mutation.** Those directories are recursive infrastructure: a tidying that breaks a hook silently degrades every future session.

## Scope

The repository's tracked Bash and PowerShell scripts, minus the exclusions below. The lane ships no directory globs: read the consuming project's tooling layout from its files, or set it with a project lane at `.claude/tidy-lanes/shell-tooling.md`. A project `Scope` block **replaces** this scope (see [Merge semantics](#merge-semantics)); it does not have to restate the sections it keeps.

## Merge semantics

This lane is layered per the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/contracts/config-cascade/README.md) ("Merge semantics"). A project lane at `.claude/tidy-lanes/shell-tooling.md` is **not** meant to replace this file wholesale. It merges with the bundled lane **per section**, so bundled improvements to sections the project does not touch keep reaching the repo. This is the declaration a project lane adopts (by reference or by restating it); it is the recommended shape for this lane:

- **`Scope`**: **per-section override.** A project `Scope` block replaces the bundled scope entirely; retargeting tooling layout is the whole reason a project writes a lane. A project lane that omits `Scope` keeps the bundled scope.
- **`Watch-for patterns`**: **additive (concatenate).** A project's watch-for entries are **appended** to the bundled section, so the bundled pointer below is never frozen out.
- **`Lane-specific extra exclusions`**: **additive (concatenate).** A project's extra exclusions are appended to the bundled ones rather than replacing them; dropping the bundled hook-directory HARD exclusions is not something this lane's semantics offer, because they are the safety mechanism it exists around. Those specific directories are also on the plugin's global HARD list (`reference/exclusions.md`), which no lane layer resolves at all, so they hold even for a project lane that declares nothing.
- **Every other section**, named here or not (`Verification commands`, `Conventional Commits type`, `Preferred research sources`, and anything a later version adds), gets a **per-section override**, same as `Scope`: a section the project supplies replaces the bundled one; a section it omits keeps the bundled value. The prose above the first `##` heading is bundled-only.

When a project lane at `.claude/tidy-lanes/shell-tooling.md` includes a `## Merge semantics` section, `/code-tidying:tidy` reads **both** that project lane and this bundled lane and merges them per **the project lane's** declaration, which is why adopting the shape above (`Merge semantics: per the bundled lane's declaration`) is what puts these rules in force. A project lane without that section resolves project-only, and none of the above applies to it.

## Watch-for patterns

The tidyings in `reference/tidyings.md` that apply to the scoped scripts. Read the language-specific idioms to watch for from the consuming project's own rules and lint configuration; a project lane lists the ones it wants hunted.

## Lane-specific extra exclusions

Beyond the global HARD/SOFT lists:

- **Agent-hook directories (`.claude/hooks/**`) are HARD-EXCLUDED for mutation.** Read-only investigation OK (to understand patterns); editing is deferred
- **Git-hook manager config and script dirs (`lefthook.yml`, `.lefthook/**`, `.husky/**`, `.pre-commit-config.yaml`) are HARD-EXCLUDED for mutation.** They control the entire local hook chain. Read-only investigation OK
- **Bootstrap/install scripts**: SOFT-EXCLUDED for behavioral changes. Reading-order / comment cleanup OK; logic changes defer
- **CI-invoked test runners**: SOFT-EXCLUDED. Behavioral changes to a script CI invokes need a CI run to validate. Beck #5 / #15 tidyings OK; argument-parsing changes defer
- **Test scripts**: SOFT-EXCLUDED. They pin the behavior a tidying must keep, so a tidying in the same PR weakens the check that proves it structure-only

## Verification commands

The consuming project's own lint, format-check and test commands for the changed scripts, read from its ecosystem record (`.claude/ecosystems/<ecosystem>.yaml`), its project instructions, or its CI config. When none names a command for a changed script's language, report that check as unresolved and skip it; the lane ships no command to run in its place.

## Conventional Commits type

`chore:`. Tooling improvements aren't features (`feat:`), aren't behavioral fixes to product code (`fix:`), and aren't strictly refactor in the compiled-code sense. Example titles:

- `chore(tools): apply lint drift across tooling scripts`
- `chore(tools): add guard clauses to tooling scripts`

## Preferred research sources

The consuming project's own rules for the scoped scripts' languages, then the official documentation of the shells and tools the project itself uses.
