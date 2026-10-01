# How the binary read works

Background for maintaining `scripts/inventory.py`. Read this before changing the extraction or when
a run reports a layout error. The skill body carries what a caller needs; this carries what an
editor needs.

Contents: [Why the binary is read at all](#why-the-binary-is-read-at-all) ·
[Shape of the artifact](#shape-of-the-artifact) ·
[The extraction decisions](#the-extraction-decisions) ·
[Known non-commands](#known-non-commands) · [Integrity, per lane](#integrity-per-lane) ·
[Docs cross-check](#docs-cross-check) · [When a build changes](#when-a-build-changes) ·
[Cost](#cost)

## Why the binary is read at all

`docs/en/commands.md` carries an "All commands" table, but it is partial: on 2.1.284 the binary
registers 39 user-facing names the table does not list, and the table marks `/ultraplan` removed
while the build still registers it. `docs/en/slash-commands` serves the skills page byte for byte. Plugin
components are on disk and need no such measure; the binary read exists only for the built-in and
bundled surfaces, which have no other complete source. Verified 2026-09-29 against Claude Code
2.1.284 by a `--binary-only --docs` run and a `cmp` of the two pages; recheck when the
`undocumented` count in `docs_crosscheck.counts` reaches zero, at which point the page could
become the source and the binary read the cross-check.

## Shape of the artifact

The shipped executable is a Bun standalone build: a native container with the JavaScript bundle
appended. Two layouts have been observed:

| Layout | Observed on | Readable source |
|---|---|---|
| Single run | 2.1.228 (PE32+, Windows) | one ~25 MB printable run under a `// @bun @bytecode @bun-cjs` header |
| Fragmented bytecode | 2.1.263 (ELF, Linux) | ~3,200 printable runs from 256 bytes to several MB, scattered through ~214 MB after the first `// @bun` marker |
| Fragmented bytecode | 2.1.284 (ELF, Linux) | ~4,200 runs joining to ~45 MB, ~243 MB file; registrar `ps` by ESM export |

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
`elapsed_seconds`. `runs_below_floor` counts registration tokens (`({name:` followed directly by a
quote, backtick, or identifier) that sit in runs shorter than the floor: a registration below the
floor is counted, never silently lost. `({name: "` with a space is message prose from the bytecode
string table (2.1.284 carries two) and is not counted. The floor
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

The index holds only string bindings, so its nearest entry can sit behind a nearer binding it
cannot see. Every candidate, for commands, bundled skills, subagents and tools alike, must also be
the string constant the read sees under the module and scope rule that field resolution uses
(`_scoped_constant`); otherwise the name stays unresolved. In 2.1.286 the generic skill loader
builds `{type:"prompt",name:Vt,...}` with `Vt=$t?smt(e):e` in its own scope, and an unrelated
`Vt="string"` megabytes ahead used to surface as a built-in command `string`.

Two further shapes, both first seen in 2.1.284:

- **Descriptor member.** `let t=c;ps({name:t.name,description:t.description,...})` with
  `c={name:o,...}` and `o="slides"` (`registerSlidesSkill`). The identifier is followed through
  `a=b` aliases to its object literal by the same nearest-preceding rule; that object's `name` and
  description stand in for the registration's member reads.
- **Loop over a literal table.** ``for(let{kind:e,description:n}of Qi)ps({name:`artifact-${e}`,...})``
  with `Qi=[{kind:"report",...},...]`. When the table binding is an array of object literals, each
  row is expanded into its own skill and `bundled_skill_notes.rosters_resolved` records the table
  and row count. A loop over anything else stays a `dynamic_roster`.

`resolved` counts registration calls, not rows, so an expanded roster never masks an unresolved
call. A registrar call must stand alone: `productionRemoteToolsAnnounceDeps({` ends in `ps` and is
not a call to `ps`.

Built-in commands use the same constant rule for `name:EMr` (`commit-push-pr`, `limit-reset`,
`low-priority`, `claim-credit` in 2.1.284). A single-character `name:e` in a command literal is a
factory parameter and is never resolved.

Bundle markers are not module boundaries in the fragmented layout: the real bindings sit about 170
marker occurrences ahead of their registrations, so a marker-scoped rule finds nothing. Locality is
measured in bytes.

### 4. Resolve enclosing objects by brace depth, not by a text window

Minified object literals sit flush against one another:

```js
...,IWp=N7b});var $7b,DWp;var MWp=E(()=>{QH();$7b={type:"local-jsx",name:"artifacts",...
```

A fixed window around `type:"local-jsx"` spans the neighboring command and mixes its `description`
in. `build_brace_map` tokenizes the whole joined source once, tracking string, template, regex, and
comment states so a `{` inside a string is not counted, and records every matched pair. Each
command's and each registration's fields are then read from its own literal. A regex-only pass over
this bundle goes wrong in one of two ways: it misses `/artifacts` entirely, or it invents `/alias`
and `/todos` as commands.

A template substitution `${...}` is code, not text: it can hold regex literals, nested templates,
and object literals, so the main tokenizer walks it and the `}` that returns to the substitution's
depth resumes the template text. In 2.1.284 `` `prints ${to(fn.replace(/^(["'])(.*)\1$/,"$2"))}` ``
put quote characters inside a regex inside a substitution; skipping the substitution as quoted
text desynced the reader, swallowed 21 MB into one brace pair, and left 15 of 152 command literals
resolved with every canary missing.

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

From those, every command, bundled-skill, and bundled-workflow record carries `user_invocable` and
`model_invocable`, each a bool or null. The rules come from the 2.1.284 bundle:

| Surface | `user_invocable` | `model_invocable` |
|---|---|---|
| Built-in command | false only with `userInvocable:!1` | the Skill tool's filter: `type:"prompt"`, no `disableModelInvocation`, and `source:"builtin"`; `local`/`local-jsx` are false; a prompt command without `source:"builtin"` is null |
| Bundled skill | the registrar's `userInvocable ?? true` | the registrar's `disableModelInvocation ?? false`, negated |
| Bundled workflow | true: the workflow becomes a `type:"prompt"` command with no `userInvocable` | the command loader calls the registration's `disableModelInvocation` function, so it is null unless the registration passes a constant |

A function-valued field is null: the registrar installs it as a getter, so its value is decided per
session. The Skill tool also drops a name that a per-machine skill override turns off; that is
settings, not bundle, and is out of scope. `integrity.undetermined` lists every null.

### 7. Resolve descriptions and argument hints statically

`description` and `argument_hint` are read by `resolve_field`, which evaluates one field of an
object literal without running anything:

| Form | Example (2.1.284) | `_source` |
|---|---|---|
| String or single-quoted literal, or a `+` concatenation of them | `keybindings-help` | `literal` |
| Template literal; each `${...}` resolves like any expression, and one that does not renders as an ellipsis | `color` argument hint | `template` |
| Identifier bound to a value, followed by the module rule below | `description:Ki` | `constant` |
| Identifier naming a `function f(...){...}`, or a call with or without arguments (a tool's `description(){...}` method is read the same way) | `description:ta` (`code-review`); `ClaudeDesign`, `Glob` tools (2.1.285) | `call` |
| `get description(){...}`, each `return` collected | `exit`, `init`, `diff`, `terminal-setup` | `getter` |
| `()=>...` | `artifact-pr-review` | `arrow` |
| A loop variable of a literal-table roster | `artifact-report` | `roster` |
| Anything else (`()=>n().description()`) | `design` | `unresolved` |

Within a returned expression, only operands in value position count: the start, after a
top-level ternary `?` or `:`, and after a `||` or `??` fallback unless the fallback is an empty
string. An operand followed by `?` is a condition, which is how
`OMt(rc()?"fullscreen":"inline")==="fullscreen"?"Toggle...":"View..."` yields the two branch
strings and not the condition's. Several values become `_variants`, and `value` is the last:
the else branch of a ternary, the final `return` of a getter, which is the default-session text in
every 2.1.284 case. An operand is a `+` concatenation whose parts may also be a parenthesized
expression (`d+(x()?m:c)+p`) or a literal array's `.join(sep)`.

A parameter of the function or method being read, a `catch` parameter, a `let`/`const` bound in a
`for (...)` head, and a declaration in an enclosing block that the reader can see are runtime
values: each is shadowed, so it never resolves to a same-named import or outer binding, and what depends on it becomes a condition, an
ellipsis, or nothing. A result whose ellipses leave no static word (`${a}\n\n${b}` with neither
resolved) is unresolved, not a value.

The 2.1.285 bytecode bundle concatenates about two thousand modules, each opening with a
`// @bun` header, and minified names repeat from module to module (`jd` is `"Workflow"` in one and
a local `"host_exit"` ternary in another). So an identifier longer than one character resolves by
module: a name its module imports resolves to the one top-level declaration in the one module that
exports it; any other name resolves inside its own module, nearest before the reader, else first
after (a function declaration always, being hoisted; a value binding only at the module's top level
and only when the read is deferred, reached through a getter, method, arrow or function-valued
field that runs after the module loads); a name neither imported nor declared there is
unresolved. A single-character identifier is function-local: a binding is trusted only within
`SHORT_VALUE_LOCALITY_BYTES` before the reader and inside its module, and a function only as the
one top-level `function X(` of its own module. A source with no module
headers keeps the plain nearest-preceding rule. A skill field that resolves to nothing falls back to
its descriptor object, then to `menuDescription`.

A description no form resolves is listed in `integrity.undetermined.description_unresolved`
(2.1.285: `design`, whose description reads a table keyed by a runtime mode). That list feeds
`/claude-ops:changelog apply`'s native-drift step, which files each name the previous run did not
list, so a release that adds a shape this reader cannot follow is filed rather than absorbed.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| The bytecode bundle is about two thousand concatenated modules, each opening with a `// @bun` header, and minified names repeat between them | 2,125 `// @bun` headers counted in the bundle `read_bundle` returns for the Claude Code 2.1.285 native build (release: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>, 2.1.285 entry; Bun's bytecode output: <https://bun.sh/docs/bundler/bytecode>); `jd` bound to `"Workflow"` in one module and to a `"host_exit"` ternary in another | 2026-09-30, Claude Code 2.1.285 | A release drops the `// @bun` module header or the header count falls to one; `--self-check` reports it as a changed layout |
| `design` is the only description the reader leaves unresolved | `inventory.py --binary-only` on the 2.1.285 build of that release: `integrity.undetermined.description_unresolved` lists `design` alone (14 names before this reader). This is derived per run, so no document restates it | 2026-09-30, Claude Code 2.1.285 | That list changes on any run; `/claude-ops:changelog apply` files each new name |

### 8. Find bundled workflows by what the registrar does

The workflow registrar has no readable export name (`function dro(o,e,r){eo().bundledWorkflows.push(
{source:"built-in",...e,script:o,disableModelInvocation:r?.disableModelInvocation})}` in 2.1.284),
so `_workflow_registrars` finds every function whose body pushes onto `bundledWorkflows` and reads
which parameter is spread (the metadata) and which carries `disableModelInvocation`. Each call's
metadata object is resolved from the call site: the first argument is the workflow script, a
template literal whose own `const e = ...` lines would otherwise win the nearest-preceding rule, so
identifier lookups anchor at the call, not at the field. `phases` resolves to the `title` of each
row of its array literal. `bundled_workflow_notes.registrar_route` is `push-site`.

A literal list of workflow names (`["autopilot","bugfix","dashboard","deep-research",...]`) also
sits in the bundle; it is a telemetry allowlist, not a registration, and is not read.

### 9. Find built-in subagents by their definition literal

A built-in subagent is an object literal with `agentType`, `source:"built-in"`, and `whenToUse`
or `getSystemPrompt`; the last requirement drops runtime context objects that copy `agentType`
and `source` from a definition. How the definition is registered (the roster function, a chunk
export, a feature's own spawn) does not matter for finding it. `agentType` is a literal or a
constant resolved by the nearest-preceding rule against PascalCase or kebab-case bindings
(`bF="fork"`, `WSr="claude-code-guide"` in 2.1.285).

`roster` comes from the function whose array initializer holds a known agent and whose pushes add
more, in 2.1.285:

```js
let n=[D5];if(!br())n.push(Cvt);if(!zit()){let{CLAUDE_AGENT:s}=import.meta.require(...);n.push(s)}
if(FL())n.push(uw,u8);if(ire())n.push(tot);if(...)n.push(Rvt);return n
```

An agent in the initializer is `default`, one pushed is `conditional`, one never named is
`absent`. An agent defined in another chunk is reached by its export name: every
`export{X as NAME}` for a three-character-or-longer binding is read, since the chunk's own closing
export can name it plainly (`export{qHe}`) while a later statement renames it. `tools` and
`disallowedTools` resolve element by element (literals, tool-name constants, one level of
`...spread`); `get tools(){...}` is `getter` and `tools:uw.tools` is `reference`, each null. A
spread reads the binding its own module and scope see, not the nearest same-name binding in the
bundle. When that binding is not an array literal, is itself a bare or conditional assignment
rather than a declaration, or any other code assigns it (a conditional write in the same block such
as `if(c)pY=["B"]`, a nested block, a function such as `function init(){pY=["B"]}`, or an
expression-bodied arrow such as `()=>pY=["B"]`), the list is `partial`.

### 10. Find built-in tools by shape, not by builder

The tool builder is a single-character minified name reused by unrelated modules, and some tools
(`Monitor`, `Artifact`) are plain objects never passed to it. The shape is what holds: an object
literal with top-level `name` and `maxResultSizeChars` (a value or a getter). `isMcp:!0` marks the
MCP tool template and is skipped.

Tool-name constants sit megabytes ahead of use, and unrelated modules rebind the same identifiers
in between (`no="SendMessage"`, then `no="column"`; `yh="SendUserFile"`, then
`yh="system_assigned_managed_identity"`). The index holds only tool-shaped values, PascalCase or
snake_case, and `resolve_tool_ident` takes the nearest PascalCase binding, falling back to
snake_case only when none precedes. A name read from a parameter (`name:e.name`, or a lone `e`
with nothing bound in reach) is a factory: `factory_definitions` counts it and nothing is guessed.

Per tool: `description` through `resolve_field` with methods read as getters (`async
description(){return X}`), which often yields the per-call permission text or nothing, so
`search_hint` is kept beside it; `deferred` from `shouldDefer`, `always_load` from `alwaysLoad`
(absent is false, `!0`/`!1` as written, anything else null and listed in `flag_driven`); `gated`
when the literal carries `isEnabled`; `aliases`; `user_facing_name` when it differs.

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

`check_integrity` returns `lanes` (`builtin_commands`, `bundled_skills`, `plugin_backed`, and
`bundled_workflows`, `builtin_agents`, `builtin_tools` whenever those were extracted), each with its own `status`, `problems`, and
`advisories`. One rule for one state: the top-level `status` is
the worst lane. `broken` at the top level means every lane is broken or the binary is unreadable; a
run with at least one healthy lane is at most `degraded`, with each broken lane's problems restated
as top-level advisories prefixed by the lane name. The exit mapping is `ok` 0, `broken` 1,
`degraded` 3, and a single broken lane never voids the healthy lanes' counts.

| Lane | Breaks on | Degrades on |
|---|---|---|
| `builtin_commands` | a canary command absent; command yield under `MIN_COMMAND_YIELD` | nothing lane-specific |
| `bundled_skills` | no bundled skill resolved | an unknown registrar-shaped export (either export shape); computed names unresolved; a dynamic roster; registration literals in runs below the floor |
| `plugin_backed` | a `PLUGIN_BACKED_CANARY` name absent | nothing lane-specific |
| `bundled_workflows` | no `bundledWorkflows.push` registrar; a `WORKFLOW_CANARY` name absent | a registration whose name did not resolve |
| `builtin_agents` | no definition resolved; an `AGENT_CANARY` name absent | a definition whose `agentType` did not resolve; the roster function not found |
| `builtin_tools` | no definition resolved; a `TOOL_CANARY` name absent | a definition whose name constant did not resolve (a factory does not degrade: it is counted) |

The CLI-version advisory is top-level, not a lane's. `integrity.undetermined` is informational: a
runtime-decided field is a property of the build, not an extraction failure, so it never degrades
a lane.

## Docs cross-check

`scripts/docs_crosscheck.py` runs only with `--docs` and writes `docs_crosscheck`. It reads the
binary lanes and never changes them.

`parse_commands_table` reads rows of the form ``| `/name <args>` | text |`` under
`## All commands`, stopping at the next `##`. From each row: the synopsis after the name, a
leading **Skill** or **Workflow** marker, `Alias for`/`Alias of` `/x` at the start (the row is an
alias), `Alias:`/`Aliases:` lists and "`/x` and `/y` are aliases" (the row declares aliases),
"`/x` is an alias" naming the row itself (an alias whose target the row does not state), and
`Removed` or `Removed in vX.Y.Z` at the start. Anchoring on the start is what keeps `/reload-skills`
("how many were added or removed") from reading as removed, and present tense is what keeps
"Before v2.1.212, `/bug` and `/share` were aliases of `/feedback`" from declaring anything.

| Status | Docs | Binary |
|---|---|---|
| `documented` | a row, not an alias, not removed | registers the name or has it as an alias |
| `undocumented` | absent | registers it (internal names are left out) |
| `alias` | an alias row, or an alias another row declares | has it as an alias |
| `docs_alias_but_registered` | an alias | registers it as its own name |
| `removed_in_docs` | a removed row | absent |
| `removed_in_docs_but_registered` | a removed row | still registers it |
| `docs_only` | a row or a declared alias | absent |

Each entry also carries `binary_kind`, `docs_kind`, `kind_mismatch`, `docs_args`, `docs_summary`,
`docs_alias_of`, `binary_alias_of`, `alias_disagreement` (aliases only one side lists), and
`changelog`. `parse_changelog` walks `## X.Y.Z` headings and, for each name, records the earliest
version whose lines mention `/name` and every mentioning line that also uses an add, rename,
remove, deprecate, or alias word. That is a heuristic, and `method.changelog` says so.

The block's own `status`: `unavailable` when the commands page cannot be read or the binary was
not, `broken` when no table rows parse, `degraded` when the changelog is unavailable or a binary
lane is not `ok`, else `ok`.

`docs_crosscheck.tools` is a nested block with a status of its own, which never changes the
parent's. `parse_tools_table` reads the ``| `Name` | text | permission |`` rows of the table headed
`| Tool | Description |` in `docs/en/tools-reference.md` and stops where it ends. Statuses:
`documented`, `undocumented`, `alias` (a docs row naming a binary tool's alias), `docs_only`. It is
`unavailable` without a `builtin_tools` lane or the page, `broken` with no rows, and `degraded`
when that lane is not `ok`. The sub-agents page lists built-ins as prose tabs, not a table, so
agents have no cross-check.

## When a build changes

Work the integrity block, not the symptom. `--self-check` prints each lane's status and names which
check failed, and each maps to one edit:

| Verdict | Cause | Fix |
|---|---|---|
| `builtin_commands` broken: canary commands absent | Source found but parsing yields little | Confirm `joined_bytes` looks right; if so the object shape changed, so re-derive from a known command |
| `bundled_skills` broken: registrar lookup failed | All three routes missed | Read the export shape around `registerBundledSkill` and add a fourth route |
| `plugin_backed` broken: canary absent | The `pluginName` field moved | Re-derive `extract_plugin_backed` from `security-review` |
| broken: joined region under 1 MB | Packer layout changed | Add the new marker to `BUNDLE_MARKERS`, or lower the floor after measuring it |
| `bundled_skills` degraded: unrecognized registrar export | A new registration path may exist | Inspect it; add to `KNOWN_REGISTRAR_EXPORTS` if it funnels into the known registrar, otherwise extract it |
| `bundled_skills` degraded: computed names unresolved | A binding shape the locality rule does not see | Report as a floor; extend `_KEBAB_BINDING_RE` only if the count grows |
| `bundled_skills` degraded: dynamic roster | A family registered in a loop or template over something other than a literal table | Acceptable; the names are enumerable only by running the binary |
| `builtin_commands` broken: yield collapses and one brace pair spans megabytes | The tokenizer desynced on a new syntax shape | Find the largest pairs in `build_brace_map`, read the text at the open brace, fix the tokenizer state that misread it |
| `bundled_workflows` broken: no push-site registrar | The registrar no longer pushes onto `bundledWorkflows` | Find where `deep-research` is registered and adapt `_workflow_registrars` |
| `bundled_workflows` broken: canary absent | The call shape changed | Read the `deep-research` call and adapt `extract_bundled_workflows` |
| `builtin_agents` broken: canary absent | The definition shape changed | Read the `general-purpose` definition and adapt `extract_builtin_agents` |
| `builtin_agents` degraded: roster not found | The roster function changed shape | Find where `general-purpose` is added to the list and adapt `_agent_roster` |
| `builtin_tools` broken: canary absent | Tools lost `maxResultSizeChars`, or `Bash`'s name constant moved | Read the `Bash` definition and adapt `extract_builtin_tools` or `resolve_tool_ident` |
| `builtin_tools` or `builtin_agents` degraded: unresolved names | A name constant the index does not see | Read the binding; widen `TOOL_NAME_RE` or `AGENT_NAME_RE` only for a real name shape |
| `integrity.undetermined` grows | A field moved behind a getter or a new indirection | Read one such field; extend `_scan` or `_resolve_chain` if the form is static |
| `docs_crosscheck` broken | The commands page restructured its table | Re-derive `_ROW_RE` and `_SECTION` from the page |

After revalidating, bump `VALIDATED_AGAINST`. Leaving it stale is not a bug: every report then says
its counts are believed rather than verified, which is the honest state until someone checks.

## Cost

Reading and scanning the executable dominates. On 2.1.284 under WSL2: about 243 MB read once, the
region pass under 2 seconds, and about 11 seconds wall clock in all, including field resolution
and, with `--docs`, both fetches. On 2.1.285 with the agent and tool lanes, about 12 seconds for
`--binary-only`. The binding lookup puts the identifier before its boundary lookbehind: a pattern
that opens with a lookbehind loses the regex engine's literal-prefix scan, and at about 0.2 seconds
per lookup it tripled the run. The file is opened read-only and never executed.
