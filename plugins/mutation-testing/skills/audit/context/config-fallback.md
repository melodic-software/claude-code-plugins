# Config and fallback

How [`../SKILL.md`](../SKILL.md) Phase 0 resolves the config, what it falls back to when no layer
supplies one, and what it does when the configured tool is missing. Under `--exercised`, these run
in the order SKILL.md "The exercised scope" gives.

## Config

Read every layer the setup skill's
[config merge model](../../setup/SKILL.md#the-config-merge-model) names, in its order, and merge
them as it says: a later layer overrides a scalar and unions a list. The user layer is the two
`userConfig` values SKILL.md "Variables" renders, `operators` and `max_mutants` (read as
`max-mutants`); an invalid one is named with its value and dropped, as the merge model says. A layer that cannot be read is reported unreadable and skipped. The scope
report's `Config:` line names the layer that supplied each value, `userConfig` for the user layer
([`../templates/report.md`](../templates/report.md)). A key no layer sets takes its default below,
marked `fallback` on that line.

## No config at any layer

That is no team or local file and no `userConfig` value. Fall back, never refuse. The defaults are
`tool: manual` (the single-operator protocol, SKILL.md
Phase 2); `diff-target` from `git symbolic-ref --short refs/remotes/origin/HEAD`, never a hardcoded
branch, and when that does not resolve, ask the user for it (an unattended run stops, naming
`git remote set-head origin --auto`); `mutate` set to the changed source files minus test code, or
under `--exercised` every source file minus test code, so the mapping can reach unchanged code; no
`max-mutants`, so the effort cap applies (SKILL.md "Effort, the mutant cap of last resort"). Test
code is what `/testing:audit --file` claims when the `testing` plugin is installed; otherwise list
the files you take as tests and have the user confirm them with the test command. The `Config:`
line reads `no config: fallback defaults` and lists each default.

**The test command is never guessed.** Ask the user for it, or have them confirm one you propose,
and state it to the user before the baseline run; the report's `Config:` line carries it. It serves
as `test-command` for this run, so `--exercised` holds it to the same `{tests}` rule. The baseline
runs exactly the confirmed command, with `{tests}` filled by the test paths the user confirmed with
it, never left empty. Never run a whole-tree test command no one confirmed: in a .NET repository a
bare `dotnet test` can run test projects that reset or write shared environments. An unattended run
with no test command stops and asks for one.

## Tool unavailable

Name the install command as `/mutation-testing:setup check` does, and offer to continue with
`tool: manual` this run. Install nothing yourself. Refuse only when the user declines both. A switch
to `manual` with no configured `test-command` takes its test command under the never-guessed rule
above. An unattended run keeps the configured tool and stops with the install command and the
`tool: manual` offer.
