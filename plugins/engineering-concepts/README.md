# engineering-concepts

A built-in catalog of software engineering concepts (principles, patterns, practices and
architectures) kept as data. Each record is a short pointer to the concept's official source, never
a copied definition, tagged so a session can find the concepts that apply to the work in front of
it. The catalog states no positions: whether to follow a concept is a team's or person's stance,
kept in their own standards layers.

## Skills

| Skill | What it does |
|---|---|
| `/engineering-concepts:lookup` | Finds records by name, alias, id or tag and reports their sources, counterweights and conflicts |
| `/engineering-concepts:load` | Brings a topic or one entry into the session as working context |

## Data

One JSONL file per topic under `data/`, one record per line. No curated records ship yet. A record
carries:

| Field | Meaning |
|---|---|
| `id` | Readable kebab-case slug, minted once and never changed; a merged id stays as an alias of the surviving record |
| `name`, `aliases[]` | What the concept is called; lookups match either, whatever the case |
| `concern`, `kind` | What the concept is about and what sort of thing it is |
| `stage` | `interview`, `design`, `plan`, `build`, `review`, `operate` or `any` |
| `reversibility` | `one-way`, `two-way` or `unrated` |
| `source_url` | The official source, `https://` |
| `confirming_sources[]` | Optional further sources that agree with it |
| `owner` | The skill (`/plugin:skill`) or page that owns the practice in depth |
| `counterweights[]`, `conflicts_with[]` | Ids of concepts that pull against or contradict it |

A record that fails these rules is reported on stderr with its file and line, and the others load.

## Lookup script

`scripts/lookup.mjs` reads only the plugin's data. Its `--help` lists the filters and options. It
prints one JSON record per line, with `counterweights` and `conflicts_with` given as `{id, name}`.

`--check-sources` is the one mode that touches the network: it fetches each record's `source_url`
and marks one that fails with `needs_resourcing: true`, keeping the record. Run it by hand or on a
schedule and read its report; tests never run it against the network.
