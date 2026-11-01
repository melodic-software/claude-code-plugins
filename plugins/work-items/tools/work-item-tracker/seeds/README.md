# Adapter seeds

The seam bundles two adapters, `github` and `local-markdown`, under `../adapters/`. The adapters
here (`jira`, `gitea`, `linear`) are seeds: the dispatcher never resolves them from this
directory. `/work-items:setup apply` copies the bound provider's seed into the consuming repo at
`<repo root>/tools/work-item-tracker/adapters/<provider>/`, and from then on the consumer owns
that copy.

`../seed-copy.sh <provider>` does the copy. It leaves out the seed's offline tests (`*.test.sh`
and `mock.sh`) and linear's `schema-check/`, which need this plugin's test helpers and
conformance bindings, and writes `.seed-hash`, the content hash of what it copied. On a re-run:

| Copy state | Result | Exit |
|---|---|---|
| absent | copied | 0 |
| hash matches, seed unchanged | `up-to-date` | 0 |
| hash matches, seed changed | `fast-forwarded` to the current seed | 0 |
| edited since the copy, or no `.seed-hash` | `edited`, the diff printed, nothing written | 1 |

Versions need no header in the copied files: each seed's `capabilities.json` carries the
`schema_version` the dispatcher's contract-version handshake checks (`../CONTRACT.md`
"Contract-version handshake"), so a copy the engine has outgrown is refused at dispatch.
