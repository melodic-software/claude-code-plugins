---
bump: patch
---

### Fixed

`block-root-delete-target` now judges whether a command sets the name behind `rm -rf $S/x` with an allowlist instead of a list of setter shapes. With quotes and backslashes removed, as bash removes them before a builtin reads its words, `S` may appear only as a read (`$S`, `${S...}`), an assignment `S=` or a `for S` at the start of a word, an option letter, or inside a longer word. Any other mention refuses the operand: a setter's operand (`read S`, `export S`, `declare -n S=R`), an option glued to a setter's name (`printf -vS`), a subscript (`S[0]=`, `${S[0]:=...}`, any `${S[`), `${S:=...}`, or a brace (`{S,}`), however it is quoted. A glued option also refuses when the command word is built by expansion (`p${x}rintf -vS`, `$x -vS`), and an option letter counts only as a `-` that opens a word, so `${y:-S}` refuses. Beside a setter builtin, a name built by expansion (`printf -v ${x:-S}`), a nameref flag, or any `$'...'`/`$"..."` word also refuses, as do `${!...}` and a quote opening a `NAME=` word that holds a blank (`export "S=/ tmp"`). A mention of `S` only inside a string (`echo "S[1]"`) now refuses too. These refusals were not replayed against the corpus.
