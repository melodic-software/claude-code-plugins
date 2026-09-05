# Tooling — the reading layers, what each proves, how to get it

`dissolve-comments` never assumes a tool. `${CLAUDE_PLUGIN_ROOT}/scripts/comment-tooling-probe.sh`
asks the environment at scope time and the run states the layer it operated at. Every layer is
optional; each row below names what its absence costs, so the reader can decide whether to install
it. The consumer's own `.claude/ecosystems/*.yaml` (the ecosystem-commands convention) is read as an
enrichment where it exists, never as the source of truth for presence: a probe stays true across
convention churn, and most repositories ship no such file.

| Layer | Tool | What it gives the skill | Absent |
|---|---|---|---|
| count | [`scc`](https://github.com/boyter/scc) | Per-file comment and code lines plus a complexity estimate, one pass, 300+ languages. Feeds the census and the repo-wide ranking | Census lines come from pygments; complexity is unavailable |
| extract | [`pygments`](https://pygments.org/) | Every comment with its line and bytes, in every language through one token stream. Correct on heredocs, trailing comments and block comments. Feeds the census byte and token estimate | The census and the ranking cannot run (exit 3) |
| attach | [`tree-sitter`](https://tree-sitter.github.io/tree-sitter/) + a grammar per language | What a comment sits on (exported symbol, private member, statement). Powers `change-shape.py`'s token proof and `commented-out-code.py`'s reparse | Deletions and renames lose their proof and fall to proposals; the exported-symbol exemption becomes a prefix heuristic |
| commented-out | [`ruff`](https://docs.astral.sh/ruff/) rule ERA001 | Precise commented-out-code detection in Python | The cross-language reparse detector still runs where tree-sitter is present |
| rules | [`ast-grep`](https://ast-grep.github.io/) | Declarative comment triage: `kind: comment` with `precedes`/`inside`/`not` classifies attachment without bespoke traversal. Detection, triage and class-A deletion only; it fixes one node at a time and cannot rename a symbol with its references | The skill walks the parse tree itself |

## Installing

| Tool | Command | Runtime |
|---|---|---|
| scc | a release binary from the project's GitHub releases; also `brew install scc`, `go install github.com/boyter/scc/v3@latest` | none, static Go binary |
| pygments | `pip install pygments` | Python 3 |
| tree-sitter | `pip install tree-sitter tree-sitter-python tree-sitter-c-sharp tree-sitter-typescript tree-sitter-bash tree-sitter-javascript tree-sitter-yaml` | Python 3; per-language wheels ship the grammar compiled in, so no network at run time |
| ruff | `pip install ruff`, or the pinned wrapper a repository provides | none, static binary |
| ast-grep | `pip install ast-grep-cli`, `npm i -g @ast-grep/cli`, `brew install ast-grep`, `cargo install ast-grep --locked` | none, static Rust binary |

Probe `ast-grep`, never `sg`: shadow-utils ships `/usr/bin/sg` (a symlink to `newgrp`) and ast-grep
historically installed its own now-deprecated `sg` shim, so on a machine carrying both, PATH order
alone decides which one answers.

Prefer the per-language tree-sitter wheels over `tree-sitter-language-pack`. The pack covers 371
grammars from one install but downloads its parser bundle at first use, which fails behind a
restricted proxy; the per-language wheels need no network after `pip install`.

## What was measured, and when

These are this skill's own measurements on this marketplace's tree (3,494 files, 40 MB), not
claims about the tools' documentation. Recheck trigger: any of the pinned versions in
`.github/requirements-ci.txt` moves, or a probe row changes status on a machine where it used to
pass.

| Fact | Measured | Date |
|---|---|---|
| `scc` full-tree scan | 0.376 s | 2026-09-04 |
| `pygments` per 100 shell files | 0.73 s | 2026-09-04 |
| tree-sitter query vs pygments on the same 20.9 MB | 2.61 s vs 11.68 s; a Python-level node walk of the same parse is 5.4x slower than the query | 2026-09-04 |
| Line-prefix grep vs `scc` on one heredoc-heavy test file | 95 "comments" vs 64; the 31 extra were fixture data inside heredocs | 2026-09-04 |
| Shell files in this tree carrying a heredoc | 263 | 2026-09-04 |
| `tree-sitter-language-pack` first-use download behind the cloud proxy | HTTP 502; per-language wheels unaffected | 2026-09-04 |
| Both `sg` binaries present on the cloud image | `/usr/bin/sg -> newgrp` and `/usr/local/bin/sg` (ast-grep shim) | 2026-09-04 |
| Versions pinned for CI | tree-sitter 0.26.0; grammars python 0.25.0, c-sharp 0.23.5, typescript 0.23.2, bash 0.25.1, javascript 0.25.0, yaml 0.7.2 | 2026-09-05 |

## What no tool covers

Five things this skill ships its own scripts for, because nothing packaged does them:

- The token-level change proof (`change-shape.py`). Structural diff tools report a comment deletion
  as a change, which destroys the signal.
- Cross-language commented-out-code detection (`commented-out-code.py`): reparse the comment body
  with the file's own grammar and require structure prose cannot produce.
- The comment-drift column in `rank-comment-targets.py`: comment lines older than the code under
  them, from `git blame` author-time, bounded to the top rows because blame is per-file and slow.
- A comment census with byte-level token accounting and a baseline delta (`comment-census.py`).
- Comment-versus-code contradiction detection in free prose. Nothing packaged exists; the
  structured slice is covered per language by the C# compiler's CS1572/CS1573, Ruff's `DOC` rules
  (preview) and `eslint-plugin-jsdoc`, and only where a repository already runs them.

Prose quality of kept comments has one candidate, [Vale](https://vale.sh/), which lifts comments out
of source through tree-sitter for about 25 languages. It covers none of Bash or YAML, so it is
named here as an optional lane, never a dependency.
