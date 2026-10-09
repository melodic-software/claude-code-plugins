# The conventions file

Read before `apply` writes or `check` grades a conventions file. It holds the format, the
fact-versus-target rule, the provenance markers, the current plugin defaults and the personal
pointer line.

## Contents

- [Location](#location)
- [Format](#format)
- [Facts, rules and targets](#facts-rules-and-targets)
- [Provenance markers](#provenance-markers)
- [Sections and their defaults](#sections-and-their-defaults)
- [Example](#example)
- [User level](#user-level)

## Location

- Repository: `<convention home>/developer-experience.md` when a convention home is bound,
  otherwise `docs/conventions/developer-experience.md`, or the path the user picks. Never under
  `.claude/`; a file found there is an old location that `apply` migrates.
- A path is repo-relative: segments of `[A-Za-z0-9._-]+` joined by `/`, no `.` or `..` segment,
  no whitespace, no backslash, no leading `/` or `~`. Reject anything else; never guess.
- The `AGENTS.md` line names the path, so moving the file means rewriting that line through the
  helper (`<skill-dir>/scripts/pointer-line.sh apply --path <new path>`).
- User level: `~/.config/developer-experience/developer-experience.md`.

## Format

```text
---
written_against: developer-experience@<plugin version>
---
# Developer tooling conventions

## <Section name>
<!-- developer-experience: source=chosen|default -->
<current facts or team rules>

## Not yet
<targets: the only place one may appear>
```

- `written_against` is the plugin version of the last `apply` that wrote this file. It changes
  only when `apply` writes the file.
- Every section except `## Not yet` has the provenance marker on the line after its heading.
- `apply` keeps sections it does not define and prose it does not recognize, verbatim and in
  place.

## Facts, rules and targets

Each sentence outside `## Not yet` is one of two things:

- **A fact**: what is true of the repository now, checkable by reading it. "`deploy` asks for
  confirmation on the terminal and has no flag to skip it."
- **A team rule**: what new or changed work follows, phrased so it claims nothing about today.
  "New and changed commands accept `--yes` to skip confirmation."

A **target** is a change the team wants that is not true yet. It goes under `## Not yet`, never
elsewhere: "`deploy` gains a `--yes` flag." Written as fact ("Commands accept `--yes`"), it sends
the next agent into a prompt that never returns.

Facts come from reading the repository, never from running a team command to see what it does.
A fact you could not confirm is asked about or left out, never written as found.

## Provenance markers

`<!-- developer-experience: source=default -->`: the body is the current plugin default below,
word for word. `check` compares it with the default of the running plugin version. When the body
differs and `written_against` is another version, `check` cannot tell an older default from a team
edit: it reports "changed default or team edit: confirm", and `apply` rewrites the body only after
the user names that change.

`<!-- developer-experience: source=chosen -->`: the team wrote or confirmed the body, or it holds
facts read from this repository. `apply` never rewrites it; `check` reports a changed plugin
default beside it as INFO.

A team edit to a `default` section makes it `chosen`: `apply` sets the marker when it writes an
edit the user asked for. A `default` body found edited by hand, while `written_against` equals the
running version, is reported by `check` as a marker to fix; `apply` leaves the body and the marker
as found until the user names that fix.

## Sections and their defaults

The sections this plugin version defines, in order. A file that lacks one gets it at the next
`apply`, with its default when it has one.

| Section | Holds | Plugin default (`source=default`) |
|---|---|---|
| `Tools` | each command and script: how it is run, what it does, whether it reads from the terminal or waits for input, any non-interactive flag it really has | none; always `chosen` |
| `Shared helpers` | helpers new tools reuse (a process runner, logging, argument parsing), with their paths | none; always `chosen` |
| `CLI contract` | the contract new and changed commands follow | New and changed commands follow the contract of /developer-experience:build-cli. Existing commands are described under Tools as they are now. |
| `Secrets` | how tools receive secrets | New and changed tools read secrets from environment variables, stdin or a file the caller names, never from a flag value. |
| `Platforms` | the platforms the project declares, and the rule for new tools | New tools target the platforms listed in this section; with none listed, Windows, macOS and Linux. |

## Example

A stack-neutral file for a repository with two commands, one of them interactive:

```markdown
---
written_against: developer-experience@<plugin version>
---
# Developer tooling conventions

## Tools
<!-- developer-experience: source=chosen -->
- `tools/deploy <env>`: deploys a build. Asks for confirmation on the terminal; no flag skips it.
- `tools/report`: prints a summary of open work. Takes no input; `--json` prints JSON.

## Shared helpers
<!-- developer-experience: source=chosen -->
- `tools/lib/run`: runs a child process and returns its exit code and output. New tools call it.

## CLI contract
<!-- developer-experience: source=default -->
New and changed commands follow the contract of /developer-experience:build-cli. Existing commands are described under Tools as they are now.

## Secrets
<!-- developer-experience: source=default -->
New and changed tools read secrets from environment variables, stdin or a file the caller names, never from a flag value.

## Platforms
<!-- developer-experience: source=chosen -->
The project declares Linux and Windows. New tools target both.

## Not yet
- `tools/deploy` gains a `--yes` flag.
```

## User level

Same format; it holds only what the user states, nothing inferred from a repository. The pointer
line `apply --user` adds to a personal instructions file, after the user's yes:

```text
- Before tooling work, also read `~/.config/developer-experience/developer-experience.md`, my personal developer tooling conventions.
```
