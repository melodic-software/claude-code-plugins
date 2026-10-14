# CI-parity gates

Read when an affected ecosystem resolves a non-empty `gates` array, or the project documents CI-parity checks in its own conventions. Gates cover the checks plain build, test and lint miss: lockfile drift, generated-artifact freshness, schema regeneration. After an affected ecosystem's build, test and lint, run each gate in its resolved `gates` array by these rules.

- **Fire condition.** `trigger-globs` narrows a change-driven run. Under auto-detection, run the gate only when at least one changed file matches, matched against the **full** changed-files set (a gate's trigger files need not classify into the ecosystem's own `globs`). With `trigger-globs` omitted, run whenever the ecosystem runs.
- **Explicit scope overrides the narrowing.** When `$ARGUMENTS` names a scope (`/toolchain:check all` or `/toolchain:check <ecosystem>`), every gate of a selected ecosystem fires regardless of `trigger-globs`. Otherwise `check all` on a clean tree would pass a committed-but-untidy `go.mod`. This is also the only way to force a gate without a matching change.
- **Reachability.** A gate is subordinate to its ecosystem's run: `trigger-globs` narrows within a run and never selects an ecosystem. Under auto-targeting the ecosystem must first be affected by its own `globs`; a gate whose `trigger-globs` alone match is reached through `/toolchain:check <ecosystem>` or `/toolchain:check all`. To make a cross-ecosystem trigger select its ecosystem, add the pattern to that ecosystem's own `globs`.
- **Independent of the short-circuit.** A fired gate runs even when this ecosystem's build, test or lint already failed and stopped, and an opt-in-unmet lint skip does not suppress it.
- **Run** `gate.cmd` (an opaque shell string; substitute `<files>`, the resolved anchor and the other placeholders) with absolute paths. The resolved `run-from` (default `"ecosystem"`) sets where:
  - `"ecosystem"` runs from the same location the ecosystem's own commands use: once per resolved `<project-dir>` for a `project-discovery` ecosystem, from the `anchor`'s directory for an `anchor` ecosystem, and from `$REPO_ROOT` only when neither is defined. The bundled `go.yaml` `go-mod-tidy-drift` gate needs this, since `go mod tidy -diff` is per module. `<files>` expands to that project's scoped changed files.
  - `"repo-root"` runs once from `$REPO_ROOT` (for a repo-wide gate such as protobuf generation declared under a `project-discovery` ecosystem; declare `run-from: repo-root` on that gate instead of moving it to an ecosystem without `project-discovery`). `<files>` expands to the ecosystem's full changed-files set. `<project-dir>` is undefined there: a gate `cmd` that uses it while declaring `run-from: repo-root` is a configuration error, reported as `FAIL` naming the gate and the placeholder. Such a gate is per-project by construction and belongs on the `"ecosystem"` default.
  - The fire condition stays repo-wide whatever `run-from` says.
- **Tool presence.** A gate tool missing from `PATH` reports `skip (tool missing: <tool>)` with the ecosystem's `install-hint`, never `FAIL`.
- **Version floor.** A tool present but too old for the gate reports `skip (unsupported: <tool and missing capability>)` with the `install-hint`. The `go.yaml` gate needs Go 1.23+ for `go mod tidy -diff`. Skip only when the mismatch is **positively established**: the tool names its own minimum in the error, or a documented minimum (the gate's `remediation`, the ecosystem's `notes`, or `context/<ecosystem>.md`) is above the version the tool reports when queried directly (e.g. `go version`). A rejection with no established floor is `FAIL` with the rejection text shown, since a typo in `gate.cmd` is rejected the same way. Every other non-zero exit is `FAIL`.
- **Outcome.** Report `pass` or `FAIL` by gate name; on `FAIL`, surface `gate.remediation`. A fired gate that fails counts toward the run's `FAIL` verdict. A gate that runs more than once (`"ecosystem"` scope under `project-discovery`) reports **one** line per gate name: `FAIL` if any invocation failed, `pass` only if every one passed, with each failing invocation's output shown below the table labeled by its execution root.

Gates resolve through the ladder like every other key: a bundled default may ship one, and a consumer declares its own in `.claude/ecosystems/<ecosystem>.yaml` (e.g. the `nuget-lockfile-drift` shape in the contract's examples,
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/ecosystem-commands/examples/dotnet.yaml>).

**Convention-documented gates still run.** When the project documents extra local checks in its `CLAUDE.md`, `.claude/rules/` or a commands reference instead of a `gates` array, run those too by the same rules: fire on their stated trigger files, run after build, test and lint independent of the short-circuit, report by name with the project's own remediation, and count a failure toward the verdict. Declaring them in `.claude/ecosystems/<ecosystem>.yaml` is preferred, not required.

A multi-root failure reports like this; only the roots that failed are listed, and a `run-from: repo-root` gate never produces the breakdown:

```text
Gates: go-mod-tidy-drift — FAIL (run go mod tidy and commit the updated go.mod/go.sum)
  [services/auth] go: updates to go.sum needed, disabled by -mod=readonly
  [services/billing] go.mod: missing go.sum entry for module golang.org/x/text v0.14.0
```
