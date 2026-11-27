# select: which cases a change runs

`select` names the eval cases a branch's change affects and what running them costs, before any
run. It makes no model call. The change classes below are what it applies: a removed or changed
instruction word is a cut that runs the affected cases, and so is a meaning-flipping word
(`MEANING_FLIP_WORDS` in `scripts/select_mapping.py`) inserted into an existing line; other added
text runs nothing, and a case,
grader, prompt, fixture or scaffold change runs its own case and the cases that call it. Where the
repository records its own eval run policy, that policy decides what each line obliges.

An edit inside a SKILL.md `## Next`, `## Related` or `## See also` section runs nothing: those
sections name other skills for the person and change no tool call. Neither does renaming a routing
heading (Boundaries, Scope boundary, Siblings, Routing, Handoff, Composition, Integration, Workflow
position, What this skill does not do) to another of those names or to Next or Related.

A decided-term swap or a comment-line deletion runs nothing anywhere: a hunk, frontmatter value,
eval case file or renamed path whose only difference swaps a term for the word the repository
glossary's "Rejected terms" table decided (`docs/glossary.md`, else `GLOSSARY.md`), or that word's
last word (`--lane` to `--area` for `focus area`), singular or plural, leaving old and new
byte-identical once each swap is replaced, or deletes lines a comment fills in a code, YAML or
shell file (`#` in YAML, shell, Python, TOML and PowerShell; `//` and `/* */` in JS, TS, JSONC,
Go and C#; `#` or `;` opening a line of `.editorconfig`, where a later `#` is part of the value;
with no code before or after it; never markdown, whose HTML
comments a model can read, nor a line inside a shell heredoc or multi-line quoted string (`$'...'` included; a shell file whose quoting does not read cleanly gets no exemption), PowerShell here-string, YAML
block scalar, or triple-quoted or backtick string). Decided terms come from the glossary at the merge base; a
directive comment (`//go:build`, `/// <reference`, `# shellcheck`, `# coding:` and the like), a
comment in a cgo file, a `/*` opener deleted without its `*/` and a PowerShell `#>` closer are
never deletable comments; a swap in a skill's `name` or a skill or agent rename always runs; a script gets no swap exemption; a change with no hunks is never exempt; a
plugin-wide file is always listed. A comment deletion under `evals/` runs its case, since the
model running the case may read it, except in an `.editorconfig` (editor settings, which cannot
change what the agent does) and unless the agent under test cannot see the file: the case's
`case.yaml` when no file of a case reaching it names its case folder, the evals folder or a folder
above, and no script under the evals folder that names `case.yaml` holds the deleted comment's text
or a quoted pattern matching it; or a `.sh` or `.bash` script a case's scaffold runs (`bash`, `sh`, `source` or `.`
with the script's path, optionally after `(cd <dir> &&`, or its `context.scaffold_script`) that no file of a case reaching it names,
or names any folder holding it (the evals folder and those above included) or a glob or unresolved path that could match it, in any other form, and that never reads its own source (`$0`, `BASH_SOURCE`
outside `$(dirname ...)` and outside an `awk`, `sed`, `grep` or `jq` program in single quotes, or its own name). Only these
forms are set aside: the body of a `cat` or `tee` heredoc with a quoted delimiter, a top-level `plugins: [...]` entry
of `case.yaml` or `prompt.md` naming the suite's own plugin, a double-quoted path whose literal ending after its
last expansion (`.txt` in `"$dir/$1.txt"`) neither the script's name nor a folder holding it below that path ends
with, a line that only binds a variable to the script's exact path (never exported or expanded with an operator,
in a file with no `eval`), a `(cd <dir> && bash <script> <args>)` run whose `<dir>` names nothing in or above the
suite, and an `echo`, `printf` or `${1:?message}` message that only prints the name. A file that pipes into a shell,
runs a string (`eval`, `bash -c`, `trap`, `alias`) or sources a stream (`/dev/stdin`, `<(...)`, a here-string) gets neither the heredoc nor the single-quote
reading. A case file that `cd`s or `pushd`es into the suite, or finds its own folder any other way than `$(dirname ...)` (`${0%/*}`,
`realpath "$0"`, `__file__`), makes the script visible, and a case script naming `case.yaml` makes `case.yaml`
visible. A literal heredoc's body counts as code once any case shell file names the file it writes on a line other than its opener, an output redirection into it, or a plain `git add`, `rm`, `commit`, `diff`, `status` or `ls-files` whose only `-c` is `core.hooksPath=/dev/null` or `user.*` (running, sourcing, reading, renaming, linking or making it executable); a heredoc with an unquoted delimiter writes a file that check covers too, and its text counts as code once anything a heredoc writes runs. Every body counts as code when a case file builds a name (a glob, `${!name}`, an expansion joined to text), a case script in another language (`.py`, `.js`, ...) names a written file, a case file runs a tool that executes files it finds (`make`, `cmake`, `npm`, `python`, `find`), names `.git` or a `hooks` folder, points git's `hooksPath` anywhere but `/dev/null`, writes a heredoc to a name that is not literal, or redefines `cat`, `tee`, `PATH`, `BASH_ENV` or a sourced file; a file that sources anything gets no heredoc reading. A copy whose source is a
helper's positional argument (`cp "$dir/$src"` with `src="$1"`) exposes nothing when `$dir` is set once on a line of its own, each `src` assignment is a plain positional one with no read before it, no `set` (quoted or escaped included) rebinds the arguments, and every call site of the helper, in any text file under `plugins/`,
passes only literal arguments and none names the script or a folder holding it. A trailing comment (a `#` comment
after code, the code left byte for byte) counts as a comment deletion in a shell file and in a `case.yaml`, there
only when the file parses the same without it; a `case.yaml` edit that drops one is never a description-only edit.
A `plugins/*/skills/*/evals/` file is not in the plugin's eval directory, so the agent can read it with the skill
and its comments get no hidden exemption. A heredoc or quoted-string line stays content. A swap under `evals/`
stays exempt. A hunk with any other change keeps the rules above.

A `description` or `when_to_use` edit runs nothing when the old and new text are equal after three
removals: each routing clause (a `Not for`, `Skip` or `prefer` clause that names a `plugin:skill`),
a skill token's change of form (`plugin:skill` against `/plugin:skill`; a token is a skill when it
has the slash or its plugin part names a repository plugin, so a different skill still counts),
and each decided-term swap. Any other wording change keeps the rule above.

## Run it

```bash
python3 "<skill-dir>/scripts/select-cases.py" <diff-base> [--json] [--repo <dir>]
```

`<skill-dir>` is the plugin-eval skill's directory.

`<diff-base>` is the branch's base, `origin/main` for a pull request. `--repo` names the checkout
when it is not the current directory. `--json` prints the same data as one object keyed by
plugin. Exit 0 on success, 2 when the repository or the diff base cannot be read.

## Read it

A diff that affects nothing prints `no affected cases`. Otherwise one block per affected plugin:

| Line | Meaning | What to do |
|---|---|---|
| `cases:` | Cases with at least one deterministic grader that this change must run | Pass the list as the run's case filter (an eval workflow with a `cases` input takes it as is) |
| `judged:` | Run-requiring cases whose graders are all judged | Run them where a judge grades them, and check that judge against labeled samples first |
| `run-after-merge:` | Triggering and no-fire cases of an additive-only `description` or `when_to_use` edit | Merge first, then run them on the default branch |
| `affected-no-run:` | Cases the change touches that the policy runs nothing for (added body text, scripts, samples) | Nothing; they are listed so the author sees them |
| `no-run-exempt:` | Skills whose `description` or `when_to_use` edit is routing-only or a decided-term swap, then the reason; their triggering and no-fire cases are in `affected-no-run:` | Nothing |
| `uncovered:` | A changed skill or agent with no affected case | Add a case with `/evals:design` |
| `plugin-wide:` | Hooks, `.mcp.json`, `plugin.json` or settings changed | No automatic run; judge whether a case should run |
| `unmapped:` | A changed file no rule maps to a case | Judge it by hand |
| `unread-graders:` | A Skill or Agent grader whose `input_match` names no skill the shared rule can read | Rewrite the grader so it names its skill, or check it by hand |
| `compare-refused:` | Each changed path of the plugin that the repository's `.github/scripts/plugin-eval/select-plugins.mjs` refuses, with its reason; printed only where that script exists and Node runs it | Dispatch no compare run; merge first, then run the cases in a suite run on the default branch |
| `agent-runs:` | Each run-requiring case's runs times two arms, summed | State it with the case list before dispatch |

A triggering or no-fire case is one that leaves the choice of skill to the model (its prompt does
not open with a `/plugin:skill` command) and checks a Skill call, or one tagged `triggering`,
`no-trigger` or `no-fire`. A `description` edit cannot change a case that invokes the skill by
name, so those cases are not selected for one.

Which skill a case tests comes from the plugin's shared `case_skills.py` rule, the same rule
`/evals:validate` reads, so the two never disagree on a case.

## Before dispatch

State the `cases:` list and the `agent-runs:` count in the pull request, then start the run with
that list as its case filter. A list that exceeds one run's ceiling splits
across several dispatches; never drop a listed case to fit.
