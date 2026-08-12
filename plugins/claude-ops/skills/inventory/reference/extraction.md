# How the binary read works

Background for maintaining `scripts/inventory.py`. Read this before changing the extraction or when
a run reports a layout error. The skill body carries what a caller needs; this carries what an
editor needs.

## Why the binary is read at all

Claude Code's documentation does not publish its built-in slash commands. `docs/en/slash-commands`
now serves the skills page — the two URLs return byte-identical markdown, because commands were
merged into skills — so no upstream page enumerates `/clear`, `/rewind`, `/artifacts`, or the rest.
Plugin components are on disk and need no such measure; the binary read exists only for the built-in
and bundled surfaces, which have no other complete source.

Verify that premise rather than trusting this paragraph:

```bash
curl -sSL -o /tmp/slash.md https://code.claude.com/docs/en/slash-commands.md
curl -sSL -o /tmp/skills.md https://code.claude.com/docs/en/skills.md
cmp /tmp/slash.md /tmp/skills.md && echo "still identical - binary read still required"
```

If those files ever differ and the slash-commands page grows a command table, prefer the
documentation and reduce the binary read to a cross-check.

## Shape of the artifact

The shipped executable is a Bun standalone build: a native container with the JavaScript bundle
appended. On the build observed while writing this (2.1.228, Windows, PE32+), the layout was:

| Property | Value |
|---|---|
| Container | PE32+ x86-64, 12 sections |
| Payload section | `.bun`, ~212 MB, ~71% of the file |
| CLI bundle | ~25 MB of minified JS, header `// @bun @bytecode @bun-cjs` |
| Trailer | `\n---- Bun! ----\n` at EOF |

None of those specifics are load-bearing in the script, and that is deliberate. Parsing the PE
section table would work on Windows and then need a Mach-O load-command reader for macOS and an ELF
section reader for Linux — three parsers to maintain against a packer that may rename its section
anyway. The script instead treats the file as bytes and finds the bundle by content.

## The three extraction decisions

### 1. Anchor on an export name, not the chunk header

The obvious anchor is the `// @bun` header. It fails: the header appears in several small helper
chunks, and the *first* occurrence is a few hundred bytes of the wrong one. The first draft of this
script returned a 454-byte "bundle" and zero commands.

The script anchors on `registerBundledSkill` — a string that occurs only in the CLI bundle — expands
to the surrounding printable run, and takes the largest candidate, rejecting anything under 1 MB.
Chunk headers remain as fallbacks in `BUNDLE_MARKERS` for a build that renames the export.

### 2. Discover registrar names, never hardcode them

Minified identifiers are regenerated on every build. The bundled-skill registrar is `xu` in 2.1.228
and will be something else next release, so `re.findall(r'xu\(\{', src)` dates the script to a
single version.

The bundle's module export maps keep the original names:

```js
pt(QCd,{ ... registerBundledSkill:()=>xu, getBundledSkills:()=>dFo, ... })
```

`discover_registrar(src, "registerBundledSkill")` reads the minified name out of that map at
runtime. The readable half is what upstream maintains; the minified half is what changes.

### 3. Resolve enclosing objects by brace depth, not by a text window

Minified object literals sit flush against one another:

```js
...,IWp=N7b});var $7b,DWp;var MWp=E(()=>{QH();$7b={type:"local-jsx",name:"artifacts",...
```

A fixed ±N-character window around `type:"local-jsx"` spans the neighbouring command and mixes its
`description` in. `build_brace_map` tokenizes the whole bundle once — tracking string, template,
regex, and comment states so a `{` inside a string is not counted — and records every matched pair.
Each command's fields are then read from its own literal.

This is the single most important correctness property in the script. Two earlier regex-only passes
over this bundle produced lists that were wrong in different ways: one missed `/artifacts` entirely,
the other invented `/alias` and `/todos` as commands.

## The three registration paths

| Path | Shape | Yields |
|---|---|---|
| Command objects | `{type:"local"\|"local-jsx"\|"prompt", name, description, aliases, isEnabled, isHidden}` | Built-in CLI commands |
| `registerBundledSkill` | `xu({name, aliases, menuDescription, isEnabled, requires})` | Bundled skills |
| Cloud registrar | a thin wrapper registering remote-backed commands | `ultraplan`, `ultrareview`, `teleport`, `remote-control`, `schedule`, `autofix-pr` |

Names arrive two ways in the second path. Some are literals; others are hoisted constants
(`xu({name:gme,...})` where `gme="code-review"`), which is why `build_const_map` exists — a
literal-only scan silently drops roughly a third of the bundled skills, including `code-review`,
`simplify`, and the artifact family.

## Known non-commands

Strings that match a naive `name:"…"` search but are not slash commands. Each was verified by
reading its surrounding code:

| String | What it actually is |
|---|---|
| `alias` | A sandboxed-shell builtin, beside `nohup`, `srun`, `timeout`, `sleep` |
| `todos` | A session-cleanup hook name |
| `mcp__` | An MCP tool-name prefix |
| `stub` | A disabled placeholder (`isEnabled:()=>!1`) |
| `workflow-launch-exec` | Internal handoff for server-launched workflows |

The `type:` requirement plus brace-depth resolution excludes all of these. `INTERNAL_NAMES` marks
the remainder that are real registrations but never user-typed.

## When a build changes

Work the integrity block, not the symptom. `--self-check` names which check failed, and each maps to
one edit:

| Verdict | Cause | Fix |
|---|---|---|
| `broken`: canary commands absent | Bundle found but parsing yields little | Confirm the bundle size looks right; if so the object shape changed — re-derive from a known command |
| `broken`: registrar lookup failed | Export renamed upstream | Update the name passed to `discover_registrar` |
| `broken`: no bundle found | Packer layout changed | Add the new anchor to `BUNDLE_MARKERS` |
| `degraded`: unrecognised registrar export | A new registration path may exist | Inspect it; add to `KNOWN_REGISTRAR_EXPORTS` if it funnels into the known registrar, otherwise extract it |
| `degraded`: computed names unresolved | Registration built its name dynamically | Usually acceptable — report as a floor. Extend `build_const_map` only if the count grows |

After revalidating, bump `VALIDATED_AGAINST`. Leaving it stale is not a bug: every report then says
its counts are believed rather than verified, which is the honest state until someone checks.

## Cost

Reading the executable dominates. On the observed build: ~2.7 s wall clock, ~300 MB read once,
~25 MB tokenized into ~190,000 brace pairs. The file is opened read-only and never executed.
