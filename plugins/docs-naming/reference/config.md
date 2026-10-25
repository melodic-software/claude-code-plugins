# docs-naming configuration surface

## Contents

- [Where the file lives](#where-the-file-lives)
- [How layers merge](#how-layers-merge)
- [The `file_names` keys](#the-file_names-keys)
- [Tiers and forms](#tiers-and-forms)
- [Generated files](#generated-files)
- [What this surface does not cover](#what-this-surface-does-not-cover)
- [Reading it from a script](#reading-it-from-a-script)

Owner document for `docs/conventions/docs-naming.yaml`, the consumer configuration the
file-name skills read, validated by
[`schemas/docs-naming.schema.json`](../schemas/docs-naming.schema.json).
`/docs-naming:setup` writes and verifies it; nothing else in the plugin writes it.
The keys are top-level keys of the file. There is no `schema` or `file_names`
wrapper, and a `#` comment is the way to annotate a value.

The audit, realign, and gate-emitter skills resolve every repository-specific
value from here, so the same skills run against a documentation tree whose
casing rule, scope roots, frozen trees, and generated records are nothing like
this marketplace's.

## Where the file lives

Three layers, discovered independently and applied over the plugin's bundled
defaults:

| Layer | Path | Git |
|---|---|---|
| User-global | `docs-naming.json` under `~/.claude/` | the operator's machine |
| Team | `<home>/docs-naming.yaml` | committed, team-shared |
| Personal overlay | `<home>/docs-naming.local.yaml` | gitignored |

`<home>` is the repository's convention home: the directory the pointer line in
the marked region of `AGENTS.md` (else `CLAUDE.md`) names, `docs/conventions`
when there is none. The `layers` and `paths` actions of the resolver report which
layer supplied each key and which file each layer was read from. The user-global
layer stays a JSON document (`"schema": 1` and a `file_names` object), because
it is a machine-wide file outside any repository.

For one release a team or overlay layer whose YAML is absent is read from the
JSON file under `.claude/` it used to live in (`docs-naming.json` for the team,
`docs-naming.local.json` for the overlay; same `"schema": 1` document). The
resolver stays quiet on stderr, `paths` reports the state `deprecated`, and
`/docs-naming:setup check` shows a WARN row. The YAML wins whenever it exists, and the two are never
merged. `/docs-naming:setup apply` seeds the YAML from the old file on its first
write.

A layer whose file is absent under that name but present under the retired
`docs-hygiene` name (`.claude/docs-hygiene.json`, `.claude/docs-hygiene.local.json`,
`~/.claude/docs-hygiene.json`) is read from there, with a stderr warning from
`resolve` and a WARN row from `/docs-naming:setup check`. The new name wins when
both exist. Rename the file to retire the warning.

All three absent is a valid state: every key has a bundled default, and the
defaults are this marketplace's own values, except `generated`, which is empty. The recommended gitignore line for
the overlay is `.claude/**/*.local.*`; `/docs-naming:setup check` reports a
missing one and never edits a consumer's `.gitignore`.

A JSON layer (the user-global file and the pre-YAML locations) declares
`"schema": 1`. A layer that omits it, or names a schema this version does not
implement, stops the run rather than being skipped: a silently ignored layer is a
configuration the operator believes is in effect and is not. A YAML layer
carries no schema number, and one the YAML-subset parser rejects stops the run
the same way, with the file and line named.

The YAML is the repository's YAML subset (`lib/yaml-subset.awk`): block
mappings and sequences, plain and quoted scalars, and `#` comments. Flow
mappings, anchors and block scalars are rejected, so quote a value that holds a
colon followed by a space or starts with `*`. An empty list is written `key: []`, which stays a
declared empty list rather than an absent key. `setup apply` keeps the comment
block at the top of the file and drops comments between keys, because it
rewrites the file from the merged document. A JSON layer's `_comment` is a
free-text annotation that is never parsed.

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

**`tiers` needs one more rule than the rest of the additive class, because
appending is not monotonic for it.** Every other additive key is a list of
things to exempt or exclude, so a new entry can only narrow what a rename
touches. A tier entry carries a *verdict*, and a personal tier naming a deeper
path with a looser form would re-classify a file the team froze: an addition
that removes a protection.

The resolver therefore stamps each tier entry with a `_layer` field naming the
layer that contributed it, and the consumer holds the floor per file: an
authoritative tier (bundled or the tracked team layer) always beats a personal
one, whatever the pathspecs say, and specificity decides only among tiers of
equal authority. A personal tier still classifies any file no authoritative
tier claims, which is the adding the floor exists to allow. A tier carrying no
`_layer`, as a hand-written document would, is read as authoritative: the safe
reading of an unknown origin is the one that cannot silently loosen anything.

`/docs-naming:setup check` prints the contributing layer for every key and
names any declaration it ignored.

## The `file_names` keys

| Key | Type | Default | What it decides |
|---|---|---|---|
| `roots` | array of strings or root objects | `["docs"]` | the trees the audit inventories and the gate enforces; git glob pathspecs, relative to the repository root. A string claims every file under it; a [root object](#root-objects) can limit a root to some extensions and exempt paths inside it. A root with no tracked files inventories as `SCANNED 0` and is reported as empty, not clean. The team layer replaces the bundled default whole; a personal layer can only add roots |
| `rule` | string | `"lower-kebab"` | the transform that proposes a new name. `lower-kebab` lowercases the basename, turns underscores and spaces into single hyphens, and collapses runs |
| `regex` | string | `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$` | the extended regular expression a basename must match to be legal. It is also inlined into an emitted gate, so it may not carry a single quote |
| `exempt_basenames` | array of strings | `["README.md", "CHANGELOG.md", "INDEX.md"]` | basenames that are never renamed, anywhere under a root |
| `exempt_paths` | array of strings | `[]` | pathspecs that are never renamed |
| `exempt_extensions` | array of strings | `["py", "sh", "mjs", "js", "ps1"]` | extensions whose casing belongs to their language, never to this rule |
| `tiers` | array of objects | see below | how a reference is rewritten, by where it lives |
| `sweep_exclude` | array of strings | `[".work/**"]` | pathspecs the reference sweep never reads and never edits |
| `sweep_exclude_sites` | array of strings | `[]` | `path:literal` pairs the sweep never edits, for a site whose text matches by accident |
| `generated` | array of objects | `[]` | files that are produced by a command rather than edited; the team layer declares them, because a regenerate command is specific to its repository |
| `redirect_map` | string or null | `null` | reserved for a site generator's old-to-new map; no version writes one yet |

### Root objects

```yaml
roots:
  - path: "."
    extensions:
      - "md"
    exempt_paths:
      - "**/fixtures/**"
      - "**/vendor/**"
```

| Field | Default | What it decides |
|---|---|---|
| `path` | required | the tree, as a string root would name it; `.` is the whole repository |
| `extensions` | `[]`, every extension | the extensions the root claims, letters and digits only, matched in any case, so `md` claims `NOTES.MD` |
| `exempt_paths` | `[]` | git glob pathspecs, relative to the repository root, that this root never judges by basename |

A root's `exempt_paths` differs from the top-level key in one way: it covers a
path only when no other root claims that path without exempting it. With the
roots `docs` and the object above, `docs/x/fixtures/NOTES.md` is still judged,
because `docs` claims it and exempts nothing. Either way, an exempt path stays
in the case-collision check. Object entries merge like any additive entry: one
that differs from another in any field is a second root.

`scripts/root-scopes.jq` turns `roots` into the pathspecs each root claims;
the audit inventory and the gate emitter both read it.

A `sweep_exclude_sites` entry is the reproducible form of a hand decision. The
sweep would otherwise rewrite a line whose text happens to match an old name
without naming the file, and excluding the whole file by path would hide its
real references too.

## Tiers and forms

A tier says which reference forms may be rewritten inside a set of paths:

```yaml
tiers:
  - name: "historical"
    paths:
      - "docs/adr/**"
    forms: "links-and-paths"
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

```yaml
generated:
  - path: "docs/architecture/landscape.json"
    regenerate: "bash tools/build-landscape.sh > docs/architecture/landscape.json"
    churn:
      - "generated_on"
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
- The audit's findings artifact, whose home is defined in
  `plugins/docs-naming/context/file-name-findings.md`.
- Version bumping for a renamed file's consumers. A repository whose plugins,
  packages, or modules are versioned bumps them itself after a realign run;
  no version of these skills writes a manifest.
- CI wiring for an emitted gate. The emitter writes the checker and its test;
  the workflow step, the registry row, and the decision record stay the
  consumer's.

## Reading it from a script

```bash
plugins/docs-naming/scripts/resolve-config.sh resolve --root <repo>
plugins/docs-naming/scripts/resolve-config.sh layers --root <repo>
```

`resolve` prints the merged document; `layers` prints one `key<TAB>layers` line
per key plus an `!inert:<key>` line for every ignored declaration; `paths` prints
one `layer<TAB>path<TAB>state` line per layer, the state being `present`,
`absent`, `deprecated` (the pre-YAML location), `legacy` (the retired
`docs-hygiene` name) or a not-applicable reason. All three take
`--root`, which is the repository the team and overlay layers are read from, so
a second worktree or a fixture is addressed explicitly rather than inherited
from the environment. A `--root` that is the home directory (or an ancestor of
it) or is not a git working tree has no team or overlay layer: `paths` reports
both as not-applicable and only the user-global file is read.
