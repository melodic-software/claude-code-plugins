---
bump: minor
---

### Added

- **`compress_articles` decides whether `compress` removes `a`, `an` and `the`.** Set it per user
  in `userConfig` or per repository in `docs/conventions/docs-hygiene.yaml` (schema
  `schemas/docs-hygiene.schema.json`), which wins and is read by
  `skills/compress/scripts/articles-setting.sh` through a bundled copy of the shared reader in
  `lib/`. The run's summary ends with the value and the layer that supplied it; a value other than
  `keep` or `cut` is named with its file and key, that layer is dropped, and the run continues.
  Keys: `reference/config.md`.
- **`/docs-hygiene:setup apply` writes `docs/conventions/docs-hygiene.yaml`.** It writes only the
  keys named on the command line after validating the existing file and the result against the
  schema, replaces only an empty, null or out-of-list value, and refuses with one line, the file
  untouched, on a key set twice, a map or list, an empty quoted string, an unknown key, a parse
  error, a root that is `$HOME` or an ancestor of it, a symlinked or hard-linked path, or a
  directory or file in the way, or a file that mixes CRLF and LF line endings (a CRLF file is
  updated in place and keeps CRLF). Changing an existing
  file shows a diff and needs the operator's yes. `check` also validates that file and reports
  the effective `compress_articles`, resolved the way `compress` resolves it: an invalid value in
  the file resolves to the default, `keep`, never to the `userConfig` value, and a key the schema
  does not list is a warning that leaves a valid `compress_articles` in force. Setup now needs
  `node` for this step.

### Changed

- **`compress` keeps articles by default, and under the default it no longer uses the `caveman`
  backend or the full single-file latitude.** With `compress_articles` at `keep` (the default),
  every run uses the in-session Edit backend even when `/caveman:compress` is installed, because
  caveman always removes articles, and a single-file run is held to the batch path's word-level
  cuts minus articles: no sentence or restatement is deleted. Set `compress_articles: cut` to get
  the earlier behavior: caveman when installed, and the full flavor matrix on a single file. Expect
  smaller yields under `keep`. The semantic-diff prompt takes the resolved value as `{ARTICLES}`:
  under `keep` a dropped article is SEMANTIC LOSS and the revert pass restores it, and under `cut`
  it stays a FALSE POSITIVE. `audit-scan.sh` takes `--articles keep|cut` (default `keep`), and its
  COMPRESS reason names article cuts only under `cut`.
- **`write-for-humans` reports new metaphor jargon.** After writing, a figurative noun the AI-tell
  catalog does not list is named in the reply as a candidate for ai-slop's
  `rule-abstract-metaphor-jargon`, when `/ai-slop:audit` is available. The skill never edits the
  ai-slop catalog.
- **`write-for-humans` reworded in its own terms.** The three surviving rules and the worked
  example are tables; the mode picker gives each mode's voice, opening, body and exclusions in
  columns; the rhythm section is a table of three checks; the first-read goal, and the instruction
  to drop a rule where it makes a sentence worse, are now the first after-writing check.
  `sentence-rules.md` groups the address rules by the part of the page they govern and states
  every address, load and ambiguity rule against one running example, a made-up backup tool. The
  worked example uses a new worker-reload passage. No rule or limit changed.
- **`write-for-agents` words three rules in its own terms.** The cognitive-load line, the
  matching-term pointer rule and the negation rule no longer share phrasing with an upstream course
  skill. The rules are unchanged.
- **Shared `parse-concern-value.sh` synced, with its parser `yaml-subset.awk` beside it in
  `skills/audit-noise/scripts/lib/`.** The reader takes dotted keys, `--list`, stdin (`-`), a
  validated `--ref` and `--strict`; every existing root-key read resolves as before, and a file the
  parser rejects now yields the fallback with one stderr line.
