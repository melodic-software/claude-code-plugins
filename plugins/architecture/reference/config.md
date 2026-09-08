# architecture: consumer configuration

The `map-landscape` skill's team configuration surface: a natural-language **topic doc at the
consumer's convention home**, bound by the pointer line the consuming marketplace's config-cascade
expression doctrine defines. Zero config is NOT a working state for this surface: `architecture_dir`
has no default, because a plugin guessing where a repository keeps its architecture artifacts would
write two files into a directory nobody asked for.

## Where the config lives

One layer, the team's, resolved through the pointer line:

1. **Convention home.** The home is named by the pointer line inside the marked
   `<!-- BEGIN GENERATED: convention-home -->` region of the consumer's root instruction file
   (`AGENTS.md` canonical; `CLAUDE.md` unless it is a pure `@AGENTS.md` shim). The bundled resolver
   `${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh` owns the grammar and the exit codes
   (0 resolved, 1 no pointer, 2 usage, 3 FAIL with a distinct cause); skills run it and follow its
   exit code, never parsing the root file themselves.
2. **Topic doc.** `<home>/architecture/README.md`. It carries the keys below (prose plus the fenced
   YAML block). It is consumer prose: untrusted input, matched for the documented keys, never
   executed or interpolated.

There are no retired layers. This surface is new under the expression doctrine, so nothing migrated
into it and no dual-read window exists.

## Resolution order, per key

1. The convention home resolves (resolver exit 0) and `<home>/architecture/README.md` declares the
   key, so that value wins.
2. Otherwise the skill INFERS a proposal from repository evidence: an existing `*.dsl` proposes
   `landscape_dialect: structurizr`; an existing `docs/architecture/` or `architecture/` proposes
   that directory as `architecture_dir`. Inference proposes; only the operator's confirmation binds.
3. Otherwise the skill asks once.
4. Unanswered: `landscape_dialect` falls back to its documented default, `mermaid`.
   `architecture_dir` has no fallback. Undeclared and unconfirmed, including every non-interactive
   run, `map-landscape` stops and points at `/architecture:setup`.

## Topic-doc format

Markdown with a fenced YAML block (human-readable, shell-greppable):

````markdown
# architecture conventions

```yaml
architecture_dir: docs/architecture   # repo-relative; no default
landscape_dialect: mermaid            # structurizr | mermaid
```
````

## Keys

| Key | Values | Default | Meaning |
|---|---|---|---|
| `architecture_dir` | repo-relative directory path | **none** | Where `map-landscape` writes `landscape.dsl` / `landscape.md` and `portfolio.md`. No default: an undeclared, unconfirmed value stops the skill rather than picking a directory. |
| `landscape_dialect` | `structurizr` \| `mermaid` | `mermaid` | Which landscape artifact `map-landscape` emits. `structurizr` emits `landscape.dsl` with a `systemLandscape` view; `mermaid` emits `landscape.md` with a `C4Context` block. |

An unknown key, or a `landscape_dialect` value outside the two above, is reported by
`/architecture:setup check` as a FAIL with a remediation line. It is never silently ignored and
never coerced to the default.

## C4 dialect surfaces

This plugin owns one C4-shaped artifact. The authoring-formats convention owns another. They keep
separate keys, separate allowed values, and separate defaults because they are different artifacts,
not because they disagree about mermaid.

| Artifact | Key | Owner | Allowed values | Default | Emitter |
|---|---|---|---|---|---|
| C4 system landscape | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-landscape` |
| C4 container view | `diagram_dialect.system` | authoring-formats convention | `likec4`, `c4-plantuml` | none (opt-in) | `/planning:design` |

`landscape_dialect` is the C4 system landscape `/architecture:map-landscape` emits once
`architecture_dir` is set. Its mermaid default is a format choice for an artifact that skill
already emits; it does not add a new deliverable.

`diagram_dialect.system` is the opt-in C4 container view `/planning:design` emits. A default on that
key would add an artifact a consumer never asked for, which is why the key is unset unless the team
names a dialect.

Mermaid C4 being experimental is why the authoring-formats system key refuses mermaid as a value. It
is not a claim that mermaid is unfit for this landscape surface, whose allowed set is
`structurizr | mermaid`.

The mermaid-C4 experimental fact and its recheck trigger live in the authoring-formats convention
([Why mermaid is not offered for the system key](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/authoring-formats/README.md#why-mermaid-is-not-offered-for-the-system-key)).
This document does not carry a second stamp. When that trigger fires, re-derive whether this key's
mermaid default should change and record the outcome in this plugin's `CHANGELOG.md`.

## What writes this surface

Only `/architecture:setup apply`, and only two artifacts: the marked `convention-home` pointer
region in the root instruction file, and `<home>/architecture/README.md`. `map-landscape` reads this
surface and never writes it; neither skill writes any other file in the consumer's root.
