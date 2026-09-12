# How the binary read works

Background for maintaining `scripts/inventory.py`. Read this before changing the extraction or when
a run reports a layout error. The skill body carries what a caller needs; this carries what an
editor needs.

## Why the binary is read at all

Claude Code's documentation does not publish its built-in slash commands. `docs/en/slash-commands`
now serves the skills page: the two URLs return byte-identical markdown, because commands were
merged into skills, so no upstream page enumerates `/clear`, `/rewind`, `/artifacts`, or the rest.
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
appended. Two layouts have been observed:

| Layout | Observed on | Readable source |
|---|---|---|
| Single run | 2.1.228 (PE32+, Windows) | one ~25 MB printable run under a `// @bun @bytecode @bun-cjs` header |
| Fragmented bytecode | 2.1.263 (ELF, Linux) | ~3,200 printable runs from 256 bytes to several MB, scattered through ~214 MB after the first `// @bun` marker |

In the fragmented layout the registrations sit in small runs (the `doctor` registration in about
1.3 KB), the hoisted name constants sit megabytes ahead of the calls that use them, and the export
map is an ESM export list rather than a CJS getter. None of the container specifics are
load-bearing in the script, and that is deliberate: parsing the PE section table would work on
Windows and then need a Mach-O load-command reader for macOS and an ELF section reader for Linux.
The script treats the file as bytes and finds the source by content.

## The extraction decisions

### 1. Region rule: every printable run above a floor, from the first marker to end of file

The previous rule took the single largest printable run around an anchor. On a fragmented build
that run holds commands and nothing else, so the bundled-skill lane returned empty while the
command lane looked healthy.

The rule now, stated exactly: from the first `BUNDLE_MARKERS` occurrence to end of file, every
printable run of at least `MIN_RUN_BYTES` (256) bytes, found with one `RUN_RE` pass, joined with
newlines. `sources.binary` records `runs`, `joined_bytes`, `region_rule`, `runs_below_floor`, and
`elapsed_seconds`. `runs_below_floor` counts registration tokens (`({name:`) that sit in runs
shorter than the floor: a registration below the floor is counted, never silently lost. The floor
is what keeps the pass cheap; measured on 2.1.263, 256 bytes recovers every named surface in about
4 seconds, while a 64 KiB floor recovers 13 of 33 names and a 1-byte floor takes a minute.

A build with no marker at all falls back to the largest run around an anchor, which is what the
single-run layout needed.

### 2. Discover the registrar by three routes, never hardcode it

Minified identifiers are regenerated on every build (`xu` in 2.1.228, `eo` in 2.1.263). The
readable half of an export is what upstream maintains, so `discover_registrar_route` tries, in
order:

| Route | Shape | Recorded as |
|---|---|---|
| CJS getter | `registerBundledSkill:()=>xu` | `export-map` |
| ESM export list | `eo as registerBundledSkill` | `esm-export` |
| Canary | the callee immediately before `({name:"doctor",aliases:["checkup"]` | `canary` |

`bundled_skill_notes.registrar_route` says which one resolved. With none, the bundled lane is broken
with the existing error text.

### 3. Resolve computed names by locality, never by a single global value

Names arrive three ways. Literals (`name:"doctor"`); hoisted constants (`name:kYe` where
`kYe="simplify"` is bound elsewhere); and runtime names (a template literal such as
`` name:`artifact-${e}` ``, or a loop `for(let{kind:e,...}of ls)eo({name:e,...})`), which are one
call registering a family and are recorded as a `dynamic_roster` note, not as one unresolved
identifier.

For a hoisted constant, the locality rule is: the binding is the nearest `ident="kebab-case"`
before the registration, and a farther binding never wins over a nearer one. In 2.1.263 the same
identifier `oO` is bound to `"ehrpd"` in an unrelated module and to `"artifact-design"` closer in;
nearest-preceding picks the real one. A single-character identifier is a function-local name reused
everywhere, so it is trusted only when that nearest binding lies within
`SHORT_IDENT_LOCALITY_BYTES`; the design canvas registration (`var r="design"` a few KB ahead of
`eo({name:r,...})`) resolves, while a loop variable whose only binding is megabytes away does not.
No preceding binding is unresolved, never guessed.

Bundle markers are not module boundaries in the fragmented layout: the real bindings sit about 170
marker occurrences ahead of their registrations, so a marker-scoped rule finds nothing. Locality is
measured in bytes.

### 4. Resolve enclosing objects by brace depth, not by a text window

Minified object literals sit flush against one another:

```js
...,IWp=N7b});var $7b,DWp;var MWp=E(()=>{QH();$7b={type:"local-jsx",name:"artifacts",...
```

A fixed window around `type:"local-jsx"` spans the neighbouring command and mixes its `description`
in. `build_brace_map` tokenizes the whole joined source once, tracking string, template, regex, and
comment states so a `{` inside a string is not counted, and records every matched pair. Each
command's and each registration's fields are then read from its own literal. A regex-only pass over
this bundle goes wrong in one of two ways: it misses `/artifacts` entirely, or it invents `/alias`
and `/todos` as commands.

A call to the registrar identifier whose object carries no `name:` is another module's function
sharing the minified name, not a registration; it is counted in `same_identifier_calls_skipped` and
never inflates the resolved-versus-seen gap.

### 5. Keep both registrations when two share a name

2.1.263 registers `design` twice: the canvas skill (from `registerDesignCanvasSkill`, model-invocable,
gated on the artifact capability) and the claude.ai/design hub (model-disabled). A name-keyed map
would keep whichever the bundle placed last, and a consumer deciding model invocability would read
the wrong one. Two distinct registrations sharing a name are both kept as a list under
`bundled_skills.<name>`, each carrying `collision: true`, and `bundled_skill_notes.collisions` names
them. The same registration seen twice is not a collision. Read through `registrations_of(entry)`
so neither shape is a special case.

### 6. Read the invocation-control fields

Each registration records `user_invocable`, `disable_model_invocation`, `terminal_oriented`, and
`survives_kill_switch` when the object carries them (`!0` true, `!1` false). A function-valued
field, the `verify` registration's `disableModelInvocation:()=>...`, reads as true with the key
listed under `flag_driven`, matching the binary's own serializer. On 2.1.263 `doctor` reads
model-disabled and terminal-oriented and is the one registration that survives the bundled kill
switch; `simplify` and `run` carry no invocation-control field and are model-invocable.

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

## Integrity, per lane

`check_integrity` returns `lanes` (`builtin_commands`, `bundled_skills`, `plugin_backed`), each with
its own `status`, `problems`, and `advisories`. One rule for one state: the top-level `status` is
the worst lane. `broken` at the top level means every lane is broken or the binary is unreadable; a
run with at least one healthy lane is at most `degraded`, with each broken lane's problems restated
as top-level advisories prefixed by the lane name. The exit mapping is unchanged (`ok` 0, `broken`
1, `degraded` 3); what changed is that a single broken lane no longer voids the healthy lanes'
counts.

| Lane | Breaks on | Degrades on |
|---|---|---|
| `builtin_commands` | a canary command absent; command yield under `MIN_COMMAND_YIELD` | nothing lane-specific |
| `bundled_skills` | no bundled skill resolved | an unknown registrar-shaped export (either export shape); computed names unresolved; a dynamic roster; registration literals in runs below the floor |
| `plugin_backed` | a `PLUGIN_BACKED_CANARY` name absent | nothing lane-specific |

The CLI-version advisory is top-level, not a lane's.

## When a build changes

Work the integrity block, not the symptom. `--self-check` prints each lane's status and names which
check failed, and each maps to one edit:

| Verdict | Cause | Fix |
|---|---|---|
| `builtin_commands` broken: canary commands absent | Source found but parsing yields little | Confirm `joined_bytes` looks right; if so the object shape changed, so re-derive from a known command |
| `bundled_skills` broken: registrar lookup failed | All three routes missed | Read the export shape around `registerBundledSkill` and add a fourth route |
| `plugin_backed` broken: canary absent | The `pluginName` field moved | Re-derive `extract_plugin_backed` from `security-review` |
| broken: joined region under 1 MB | Packer layout changed | Add the new marker to `BUNDLE_MARKERS`, or lower the floor after measuring it |
| `bundled_skills` degraded: unrecognised registrar export | A new registration path may exist | Inspect it; add to `KNOWN_REGISTRAR_EXPORTS` if it funnels into the known registrar, otherwise extract it |
| `bundled_skills` degraded: computed names unresolved | A binding shape the locality rule does not see | Report as a floor; extend `_KEBAB_BINDING_RE` only if the count grows |
| `bundled_skills` degraded: dynamic roster | A family registered in a loop or template | Acceptable; the names are enumerable only by running the binary |

After revalidating, bump `VALIDATED_AGAINST`. Leaving it stale is not a bug: every report then says
its counts are believed rather than verified, which is the honest state until someone checks.

## Cost

Reading and scanning the executable dominates. On 2.1.263 in a Linux container: about 214 MB read
once, the region pass about 4 seconds, the brace map over the 37 MB joined source about 5 seconds,
name resolution about 2 seconds, roughly 14 seconds wall clock in all. The file is opened read-only
and never executed.
