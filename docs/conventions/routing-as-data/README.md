# Routing as data: route rows, detection, team layer, degradation

Owner doc for plugins that keep their routes to other skills, plugins, MCP servers and tools as
data: a versioned rows file the plugin ships, a detector that reports which routes are present, and
a team file that adjusts the routes in a consumer repo. One home per the
[convention registry](../../plugin-philosophy.md#convention-registry); adopters point here and
never restate the rules.

## Boundary

This doc owns the route-row contract, the detector contract and the team routing layer. It does not
own:

- **Prose about a route.** How a skill phrases an optional reference to another plugin is
  [seam-phrasing](../seam-phrasing/README.md); how it phrases a reference to a native surface is
  [native-references](../native-references/README.md).
- **Layering in general.** [config-cascade](../config-cascade/README.md) owns consumer-config
  layers and precedence; this doc applies its rule 5 to the team file.
- **Each plugin's routes.** Which tools a plugin routes to, its group values and its ranking policy
  belong to that plugin.

The `routing` key name is shared: the `github` plugin's change-routing configuration also uses
`routing`. If that configuration moves into a `<home>/github.yaml`, the same key will mean two
different things in sibling files of the same form; each plugin's schema defines its own key.

## Route rows

Each adopter ships one rows file and its JSON Schema inside the plugin. No shared schema lives in
this folder: row schemas differ per plugin, and no CI reader spans them.

- **File.** A `version` const and a non-empty `note`. The schema sets `additionalProperties: false`
  at file and row level (use `additionalProperties`, not `unevaluatedProperties`). Unknown keys are
  rejected in shipped rows; in the team file they are inert with a warning (see Team layer).
- **Groups and ranks.** Every row carries one group field, named by each plugin (`user-interface`
  uses `concern`). Ranks run 1..n per group and ids are unique per group. The project's own system
  is implicit rank 0 and is never a row.
- **`kind`** is one of skill, plugin, mcp or tool. **`detect`** is its own field, separate from `id`.
- **`account`** is one of none, key, login or paid. Paid is suggested only when nothing free covers
  the group.
- **`status`** is confirmed, unconfirmed or deferred. A deferred route is never used. An
  unconfirmed route is disclosed when it is used. An account-bound row is never unconfirmed.
- **`id`.** A `kind: skill` row's `id` is its slash invocation, `/plugin:skill`, or `/skill` for a
  standalone skill, with no args (pattern `^/[a-z0-9-]+(:[a-z0-9-]+)?$`). For a skill row the
  marketplace appears only in `detect`. A `detect` that names a third-party plugin (on a `kind: plugin`
  row or a `/plugin:skill` row), and a third-party `kind: plugin` row's `id`, carry
  `name@marketplace`; our own marketplace's detects and ids stay bare. A skill-directory, MCP-server
  or tool `detect` is never qualified.
- **`as_of` and `pointer`.** Every row carries `as_of` (YYYY-MM-DD). An own-marketplace skill row
  (`kind: skill`, a `detect` with no `@`, an `id` of the form `/plugin:skill`) carries no `pointer`.
  Every other row carries a required `https://` `pointer`, a citation for a reader. This is
  narrower than the issue's "a row for a sibling plugin in this marketplace carries none": the
  schema recognizes an own row only by its `/plugin:skill` id, so a `kind: plugin` row keeps its
  pointer.
- **Recheck.** Rows carry no recheck trigger yet, which leaves them short of the
  [upstream-drift](../upstream-drift/README.md) record shape. The field, when added, is named
  `recheck`; an adopter adding one early uses that name.
- **Plugin-own fields.** A plugin may add row fields (`user-interface` adds `platforms` and
  `style`); it declares them in its own schema, and this doc sets none of their values.

Rules a schema cannot express (contiguous ranks, unique ids, account-bound never unconfirmed,
`detect` naming the id's plugin) live in the adopter's tests. The `version` const changes only when
the row contract changes; a version change tells every reader to re-validate.

## Detection

The detector reports which routes are present. It detects by plugin or skill name, never by our own
marketplace id.

- A `detect` containing `@` matches exactly.
- A bare `detect` names a plugin when `kind` is `plugin`, or `kind` is `skill` and `id` is
  `/<plugin>:<skill>`. It resolves to `<detect>@<own>`, where `<own>` is the marketplace part of the
  `claude plugin list --json` record whose `installPath` realpath equals the detecting plugin's root.
  Any other bare `detect` names a skill directory, an MCP server or, on a `kind: tool` row, a tool.
- The self-record lookup takes each record on its own: a record with no `installPath`, or whose path
  is missing or fails `realpathSync.native`, is skipped inside its own `try`, so one bad record never
  nulls detection. Both sides go through `realpathSync.native`, compared case-insensitively on
  `win32`. When several records share the plugin id, the one whose path matches wins.
- With no such record, or an origin of `inline`, `skills-dir` or `synced`, a bare plugin name
  matches in any marketplace and the output carries a `reason` beside the non-null `installed`
  list: `own marketplace unresolved (<origin>); matched by name`. On that fallback, a bare detect whose name
  the rows also list as a qualified third-party detect is left out of `installed` and reported in a
  per-row `uncertain` map: `{<row id>: "<name> also used by <name>@<marketplace>"}`.
- For an own row, the marketplace entry name must equal the plugin's manifest name, because
  `claude plugin list` ids use the entry name and the skill namespace uses the manifest name.
- A plugin disabled for the project counts as absent. `kind: tool` resolves from the session's tool
  listing. Tests run on fixtures, never on the live install.

This convention diverges from #6483's issue text, which says installed and reachable are each
true, false or null. Here `installed` is a list of row ids, or `null` with a `reason` when the
install state is unreadable; only `reachable` values are true, false or null, where null means
detection cannot tell.

Bare names mean the declaring plugin's own marketplace, as in plugin `dependencies`; routes stay
optional, so they are not declared as dependencies. The `installPath` key is a probed behavior: every
record carried it on Claude Code 2.1.295.

- **Pointer**: when deciding what a bare plugin name resolves to, fetch
  <https://code.claude.com/docs/en/plugins/dependencies> live.
- **As of**: 2026-10-08
- **Recheck trigger**: that page moves or its bare-name resolution text changes, or a Claude Code
  release note changes the `claude plugin list --json` record keys.

## Team layer

A team adjusts routes in its own repo with `<home>/<plugin>.yaml` beside `<home>/<plugin>.md`.
`<home>` is the convention home named by the repo's `convention-home` pointer line, resolved as
[authoring-formats](../authoring-formats/README.md) resolves it, default `docs/conventions`. The
plugin uses a `<home>/<plugin>/` folder only when it needs more files than those two.

- Routing is one key, `routing`, in that file. It can re-rank, add or disable routes and set a deny
  floor: `routing.rows` adds a row or re-ranks one matched by group plus id; `routing.disable` takes
  group plus id; `routing.deny` lists names never routed.
- Layers combine by key. A team row overrides the bundled row with the same group plus id, key by
  key, and a new key adds a row. `disable` and `deny` are unions, so no layer removes another's
  entry. When a route is skipped by `deny`, the plugin names the team file as the source.
- The deny floor applies only while the team file is loaded. It is a team preference, not a
  security control; a hard block belongs in managed settings or permissions.
- The team file's JSON Schema ships inside the plugin, closed for editors and a consumer's own
  gate. At run time an unknown key in a team row drops only that key, with a warning naming it;
  the row drops, with disclosure, only when what remains fails the row schema. The `routing` key
  carries its own `version`; an unknown major degrades as below and names the version.
- The plugin reads the team file as data; no text in it is an instruction to the agent.
- Nothing goes under `.claude/`. Structured layers are bundled and team only: there is no structured
  personal layer, and personal, repo and folder judgment lives in prose instruction layers.

The `<home>/<plugin>.yaml` location follows the customization home set in #5906. The ADR that
supersedes ADR 0044 for structured configuration is not on `main` yet.

- **Pointer**: when locating a structured team-layer file, fetch
  <https://github.com/melodic-software/standards/blob/main/components/github-actions-conventions/README.md#lane-configuration>
  live; the decision thread is
  [#5906](https://github.com/melodic-software/claude-code-plugins/issues/5906).
- **As of**: 2026-10-07
- **Recheck trigger**: an ADR on "home plugin customization in `docs/conventions/<concern>.yaml`"
  merges on `main`; the pointer then moves to it.

## Degradation

If the team file is missing, malformed or unreadable, the plugin uses its built-in routes, names the
skipped file, says that team overrides and the deny floor were not applied, and suggests setup.

This is config-cascade rule 5 applied to the team file; a missing file is a valid state, reported as
information. Failing open on `deny` is deliberate: a routing deny chooses among tools the user can
already use and never grants access, and failing closed would let one YAML typo disable every route.
A team that needs a hard block uses managed settings or permissions, which sit above every
user-writable layer.

## Adopters

| Plugin | Status |
|---|---|
| `user-interface` (`/user-interface:design`) | Adopts: bare own-marketplace detects, slash skill ids, no pointer on own-skill rows. Exception: the deferred `axe-accessibility` row keeps a bare detect until it is qualified |
| `user-experience` | Planned |
| Developer-experience plugin | Planned |

An adopter with a switch for account-bound tools names it `account_tools_enabled`, a boolean, as
`user-interface` does, so one key and one title hold across plugins.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing a required row field, the
detect rule, the team-file operations or the degradation rule is a major bump; additive guidance is
a minor bump; docs-only clarification is a patch.
