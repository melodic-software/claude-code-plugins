# docs-hygiene configuration surface

## Contents

- [Where the file lives](#where-the-file-lives)
- [How layers merge](#how-layers-merge)
- [The `file_names` keys](#the-file_names-keys)
- [Tiers and forms](#tiers-and-forms)
- [Generated files](#generated-files)
- [What this surface does not cover](#what-this-surface-does-not-cover)
- [Reading it from a script](#reading-it-from-a-script)

Owner document for `.claude/docs-hygiene.json`, the consumer configuration the
file-name skills read. `/docs-hygiene:setup` writes and verifies it; nothing
else in the plugin writes it.

The audit, realign, and gate-emitter skills resolve every repository-specific
value from here, so the same skills run against a documentation tree whose
casing rule, scope roots, frozen trees, and generated records are nothing like
this marketplace's.

## Where the file lives

Three layers, discovered independently and applied over the plugin's bundled
defaults:

| Layer | Path | Git |
|---|---|---|
| User-global | `~/.claude/docs-hygiene.json` | the operator's machine |
| Team | `<repo>/.claude/docs-hygiene.json` | committed, team-shared |
| Personal overlay | `<repo>/.claude/docs-hygiene.local.json` | gitignored |

All three absent is a valid state: every key has a bundled default, and the
defaults are this marketplace's own values. The recommended gitignore line for
the overlay is `.claude/**/*.local.*`; `/docs-hygiene:setup check` reports a
missing one and never edits a consumer's `.gitignore`.

Every layer declares `"schema": 1`. A layer that omits it, or names a schema
this version does not implement, stops the run rather than being skipped: a
silently ignored layer is a configuration the operator believes is in effect
and is not.

`_comment` is a free-text annotation at any level. It is never parsed, and it
survives every merge `setup apply` performs.

## How layers merge

Per key of `file_names`, in one of three classes.

| Class | Keys | Rule |
|---|---|---|
| Nearest wins | `rule`, `regex`, `redirect_map` | the latest layer that declares the key supplies it whole |
| Additive | `roots`, `exempt_basenames`, `exempt_paths`, `exempt_extensions`, `tiers`, `sweep_exclude`, `sweep_exclude_sites` | later layers append entries earlier layers did not carry; nothing is removed |
| Team only | `generated` | a personal layer that declares it is reported inert and ignored |

The additive and team-only classes are the policy floor. Each of those keys
decides what the realign skill does to a tree: which files are frozen, which
references are rewritten in which form, and which shell command runs after a
move. A personal layer that could replace one would weaken a team decision from
a single machine, so a personal layer may only add. A contributor adding a scope
root or an exemption of their own weakens nothing, which is why adding stays
open.

`/docs-hygiene:setup check` prints the contributing layer for every key and
names any declaration it ignored.

## The `file_names` keys

| Key | Type | Default | What it decides |
|---|---|---|---|
| `roots` | array of strings | `["docs"]` | the trees the audit inventories; git pathspecs, relative to the repository root |
| `rule` | string | `"lower-kebab"` | the transform that proposes a new name. `lower-kebab` lowercases the basename, turns underscores and spaces into single hyphens, and collapses runs |
| `regex` | string | `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$` | the extended regular expression a basename must match to be legal. It is also inlined into an emitted gate, so it may not carry a single quote |
| `exempt_basenames` | array of strings | `["README.md", "CHANGELOG.md", "INDEX.md"]` | basenames that are never renamed, anywhere under a root |
| `exempt_paths` | array of strings | `["docs/topics/**"]` | pathspecs that are never renamed |
| `exempt_extensions` | array of strings | `["py", "sh", "mjs", "js", "ps1"]` | extensions whose casing belongs to their language, never to this rule |
| `tiers` | array of objects | see below | how a reference is rewritten, by where it lives |
| `sweep_exclude` | array of strings | `[".work/**", "docs/topics/**", ...]` | pathspecs the reference sweep never reads and never edits |
| `sweep_exclude_sites` | array of strings | `[]` | `path:literal` pairs the sweep never edits, for a site whose text matches by accident |
| `generated` | array of objects | the landscape record | files that are produced by a command rather than edited |
| `redirect_map` | string or null | `null` | reserved for a site generator's old-to-new map; no version writes one yet |

A `sweep_exclude_sites` entry is the reproducible form of a hand decision. The
sweep would otherwise rewrite a line whose text happens to match an old name
without naming the file, and excluding the whole file by path would hide its
real references too.

## Tiers and forms

A tier says which reference forms may be rewritten inside a set of paths:

```json
{ "name": "historical", "paths": ["docs/adr/**"], "forms": "links-and-paths" }
```

| Form | Rewrites |
|---|---|
| `all` | every form: markdown links, backtick paths, absolute URLs, table cells, and bare stems |
| `links-and-paths` | markdown links and backtick paths only; narrative prose is left as written |
| `none` | nothing; sites are reported and never edited |

A file belongs to the declared tier whose matching pathspec has the most path
segments, ties going to the earlier entry. A file no tier claims belongs to the
implicit `current` tier, whose form is `all`, so a tree that declares no tier
at all still gets every reference repointed.

The bundled tiers freeze two things this marketplace treats as a record rather
than a surface: decision records, specifications, and upstream notes keep their
narrative and get working links, and released changelog entries are not touched
at all.

## Generated files

```json
{
  "path": "docs/architecture/landscape.json",
  "regenerate": "bash tools/build-landscape.sh > docs/architecture/landscape.json",
  "churn": ["generated_on"]
}
```

A listed path is never edited by the reference sweep. After a move that touches
it, the realign runs `regenerate` from the repository root, and stops if the
command's first real argument resolves to nothing. Blind text substitution on a
generated record is how a stale sample survives a rename while every other
reference moves.

`churn` names the fields the regenerator restamps on every run (a timestamp, a
commit id). They are informational: a reviewer comparing two runs knows which
differences are the clock rather than the change.

## What this surface does not cover

- Plugin `userConfig` options. This plugin declares none, and a layer that names
  one is an inert unknown key.
- The audit's findings artifact, whose home resolves through the topic-docs
  binding at `plugins/docs-hygiene/reference/topic-docs.md`.
- Version bumping for a renamed file's consumers. A repository whose plugins,
  packages, or modules are versioned bumps them itself after a realign run;
  no version of these skills writes a manifest.
- CI wiring for an emitted gate. The emitter writes the checker and its test;
  the workflow step, the registry row, and the decision record stay the
  consumer's.

## Reading it from a script

```bash
plugins/docs-hygiene/scripts/resolve-config.sh resolve --root <repo>
plugins/docs-hygiene/scripts/resolve-config.sh layers --root <repo>
```

`resolve` prints the merged document; `layers` prints one `key<TAB>layers` line
per key plus an `!inert:<key>` line for every ignored declaration. Both take
`--root`, which is the repository the team and overlay layers are read from, so
a second worktree or a fixture is addressed explicitly rather than inherited
from the environment.
