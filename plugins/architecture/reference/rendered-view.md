# Interactive views of the map records

How the `map-*` skills offer an interactive view of their record. The markdown file and the JSON record
stay authoritative. A view never sits beside them, and nothing reads a view back as a finding.

A record holds repository text: manifest paths, connection hosts, type names, file citations. That text is
attacker-controllable, so a view is built from a checked-in template plus the record as escaped data, and
never from markup or script written in the session.

## Procedure

1. **Write the record and its markdown first.** The view is built from the record the skill just wrote.
2. **Offer the view in one sentence.** Build only when the reader accepts and the environment can serve a
   file. A CI or other non-interactive run builds nothing: the record stands.
3. **Resolve `medium`.** Read the `rendered-views` cascade surface: `~/.claude/rendered-views.md`, then
   `<repo root>/.claude/rendered-views.md`, then `<repo root>/.claude/rendered-views.local.md`, whichever exist.
   The last layer that states `medium:` wins (`auto`, `terminal`, `file`, `artifact`). A team layer that is not
   tracked is a hard stop; an overlay that is staged or not gitignored is reported, not honored; a malformed
   layer is reported and treated as absent. Name the layer that decided. Absent or `auto` means `file`.
4. **Build.** Pass the record file to the builder. It prints the path of the page it wrote under the OS
   temp directory:

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/build-view.mjs" dependencies --record "<architecture_dir>/dependency-graph.json"
   ```

   The first argument is the skill's kind, and the record is the file in the table below. Never write markup
   or script for the page, and never hand-edit the output. When `node` is missing, deliver the markdown and say
   the view was not built. A non-zero exit means the record is not a schema_version 1 map record or the page
   failed its checks: report the builder's message and deliver the markdown.
5. **Deliver by `medium`.**
   - `file`: hand back the printed path.
   - `artifact`: publish that file with the Artifact tool (private by default) and give the link. When the
     Artifact tool is unavailable, hand back the path and say why in one line.
   - `terminal`: build nothing, name the layer that chose it, and stop.

| Skill | Kind | Record |
|---|---|---|
| `map-landscape` | `landscape` | `landscape.json` |
| `map-containers` | `containers` | `containers.json` |
| `map-components` | `components` | `dependency-graph.json`, with `--from <node-id>` |
| `map-dependencies` | `dependencies` | `dependency-graph.json` |
| `map-data` | `data` | `data-model.json` |
| `map-events` | `events` | `events.json` |
| `map-flow` | `flow` | `flow.json` |
| `map-context` | `context` | `context.json` |
| `map-deployment` | `deployment` | `deployment.json` |

`--from <node-id>` keeps the project nodes reachable from that deployable over resolved project edges, and the edges between them, which is the
closure a component view charts, and drops the record's other arrays.

## What the page shows

The page lists the record's own rows, in record order. Each array in the record is counted in a header fact and
each item is a row labeled with its array (`nodes`, `edges`, `findings`). An edge row is named `from -> to`; any
other row takes the first of `id`, `name`, `message`, `title`, `path`, `entry`, `resource`. Open a row for every
field it holds, evidence citations included. The filter matches a row's whole text, so typing a node id lists the
node and every edge, finding and cycle that names it. The page draws no diagram: the markdown holds that.
