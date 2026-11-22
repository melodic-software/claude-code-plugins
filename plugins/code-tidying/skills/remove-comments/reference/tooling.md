# Tooling: the reading layers, what each proves, how to get it

`remove-comments` never assumes a tool. `../../../scripts/comment-tooling-probe.sh`
asks the environment at scope time and the run states the layer it operated at. Every layer is
optional; each row below names what its absence costs, so the reader can decide whether to install
it. The consumer's own `docs/conventions/ecosystems/*.yaml` (the ecosystem-commands convention) is read as an
enrichment where it exists, never as the source of truth for presence: a probe stays true across
convention churn, and most repositories ship no such file.

| Layer | Tool | What it gives the skill | Absent |
|---|---|---|---|
| count | [`scc`](https://github.com/boyter/scc) | Per-file comment and code lines plus a complexity estimate, one pass, 300+ languages. Feeds the census and the repo-wide ranking | Census lines come from pygments; complexity is unavailable |
| extract | [`pygments`](https://pygments.org/) | Every comment with its line and bytes, in every language through one token stream. Shell scripts are read by `comment-census.py`'s `tokens` instead (pygments' [Bash lexer source](https://github.com/pygments/pygments/blob/master/pygments/lexers/shell.py)). Feeds the census byte and token estimate | Comment bytes and the token estimate are unavailable; with `scc` also absent, the census and the ranking cannot run (exit 3) |
| attach | [`tree-sitter`](https://tree-sitter.github.io/tree-sitter/) + a grammar per language | What a comment sits on (exported symbol, private member, statement). Powers `change-shape.py`'s token proof and `commented-out-code.py`'s reparse | Deletions and renames lose their proof and fall to proposals; the exported-symbol exemption becomes a prefix heuristic |
| proof-powershell | [`pwsh`](https://github.com/PowerShell/PowerShell) 7+ | The same two things for `.ps1` and `.psm1`, through PowerShell's own `Parser::ParseFile` rather than a grammar. `#Requires` is kept as its own leaf; a here-string is one token, so a `#` inside one is never a comment | Every PowerShell deletion and rename is a proposal (exit 2, an unproven edit, never a tacit pass); `commented-out-code.py` skips those files |
| commented-out | [`ruff`](https://docs.astral.sh/ruff/) rule ERA001 | Precise commented-out-code detection in Python | The cross-language reparse detector still runs where tree-sitter is present |
| rules | [`ast-grep`](https://ast-grep.github.io/) | Declarative comment triage: `kind: comment` with `precedes`/`inside`/`not` classifies attachment without bespoke traversal. Detection, triage and class-A deletion only; it fixes one node at a time and cannot rename a symbol with its references | The skill walks the parse tree itself |

## Installing

| Tool | Command | Runtime |
|---|---|---|
| scc | a release binary from the project's GitHub releases; also `brew install scc`, `go install github.com/boyter/scc/v3@latest` | none, static Go binary |
| pygments | `pip install pygments` | Python 3 |
| tree-sitter | `pip install tree-sitter tree-sitter-python tree-sitter-c-sharp tree-sitter-typescript tree-sitter-bash tree-sitter-javascript tree-sitter-yaml tree-sitter-toml` | Python 3; per-language wheels ship the grammar compiled in, so no network at run time |
| pwsh | a platform package or release binary from the project's GitHub releases; `winget install Microsoft.PowerShell`, `brew install powershell/tap/powershell` | none, self-contained; not a pip install |
| ruff | `pip install ruff`, or the pinned wrapper a repository provides | none, static binary |
| ast-grep | `pip install ast-grep-cli`, `npm i -g @ast-grep/cli`, `brew install ast-grep`, `cargo install ast-grep --locked` | none, static Rust binary |

Probe `ast-grep`, never `sg`: shadow-utils ships `/usr/bin/sg` (a symlink to `newgrp`) and ast-grep
historically installed its own now-deprecated `sg` shim, so on a machine carrying both, PATH order
alone decides which one answers.

Prefer the per-language tree-sitter wheels over `tree-sitter-language-pack`. The pack covers 371
grammars from one install but downloads its parser bundle at first use, which fails behind a
restricted proxy; the per-language wheels need no network after `pip install`.

## What no tool covers

Six things this skill ships its own scripts for, because nothing packaged does them:

- The token-level change proof (`change-shape.py`). Structural diff tools report a comment deletion
  as a change, which destroys the signal.
- The PowerShell reading of both (`ps-tokens.ps1`). The maintained tree-sitter grammar is not a
  usable backend here and adding it as a fallback would be worse than its absence: it would make the
  probe report a layer as present that returns UNPROVABLE on every real file.
- Cross-language commented-out-code detection (`commented-out-code.py`): reparse the comment body
  with the file's own grammar and require structure prose cannot produce.
- The comment-drift column in `rank-comment-targets.py`: comment lines older than the code under
  them, from `git blame` author-time, bounded to the top rows because blame is per-file and slow.
- A comment census with byte-level token accounting and a baseline delta (`comment-census.py`).
- Comment-versus-code contradiction detection in free prose. Nothing packaged exists.
