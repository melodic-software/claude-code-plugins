# Where shfmt's parse differs from bash's

`hook::bash_parse_segments_shfmt` (`lib/hook-utils.sh`) reads a command from
`shfmt -ln bash --to-json`. This page lists each form where that parse differs from what bash
does with the same text, as measured against bash 5 with extglob off and on, and shfmt v3.14.1.
`lib/hook-utils-shfmt.test.sh` runs every row.

- **handled**: the reader hands the guard the command bash runs.
- **refused**: shfmt rejects the text, so the guard denies the call (exit 2). Nothing runs. The
  message names the cause: shfmt or jq missing, the 5 s bound, or shfmt's own syntax error line,
  plus the reason a cloud session's shfmt install failed when there is one.

## Extglob

shfmt always parses extglob on. Bash's default in `bash -c` is off, and the command string cannot
say which mode applies.

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `!(x)#; cmd` | off: negated subshell, then a comment; on: a pattern word, then `cmd` | the on reading | handled: the reader also parses the off reading |
| `!(cmd)` | off: a subshell running `cmd` | a pattern, no command | handled: each pattern is also parsed as a command |
| `@(x)#; cmd`, `echo @(a\|b)#; cmd` | on: one word, then `cmd`; off: syntax error | the on reading | handled |
| `echo @(x;y)#; cmd` | on: `;` is pattern text | the on reading | handled |
| `` echo @(`cmd`) ``, `echo @(<(cmd))` | on: `cmd` runs | pattern text | handled: each pattern is also parsed as a command |
| `f@()#; cmd` | on: one word, then `cmd`; off: a function | syntax error | refused |

## `case` patterns

shfmt follows the grammar here, so these need nothing further.

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `echo $(case x in a\|esac) :;; esac)#; cmd` | `esac` after `\|` is a pattern | the same | handled |
| `echo $(case x in esac)#; cmd` | `esac` right after `in` closes the case | the same | handled |
| `echo $(case x in (a) :;; esac)#; cmd` | `(` opens the pattern | the same | handled |

## `[[ =~ ]]`

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `[[ x =~ (a\|b) ]]; cmd`, `[[ x =~ k=(a\|b) ]]; cmd`, `[[ x =~ (a b) ]]; cmd` | parentheses are regex text | a regex word | handled |
| `[[ x =~ a\|b ]]; cmd` | `\|` is regex text | a regex word | handled |

## A `#` after `)`

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `a=(x)#; cmd` | the `#` starts the next word, so `cmd` runs | a comment, so `cmd` is lost | handled: the reader also parses with that `#` replaced |
| `echo $(echo ${x/)/})#; cmd`, `echo $(echo ${x/(/})#; cmd` | the `#` continues the word | the same | handled |

## Backticks

Bash ends a backtick substitution at its first unescaped backtick, then reads what is inside. shfmt
reads quotes and here-docs inside first.

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `` echo `$'`; cmd #'` ``, `` echo `'`; cmd #' `` | the quote ends at the backtick, so `cmd` runs | a quote that spans the backtick | refused: the reader finds an unescaped backtick inside the span |
| `` echo `cat <<E` `` with `cmd` on the next line | no body comes from the lines after, so `cmd` runs | a here-doc body holding `cmd` | refused: the reader finds a here-doc inside the span |
| ``echo `echo \`:\`#; cmd` `` | the unescaped text is parsed when it runs, so `cmd` runs | `\`` is text | handled: the reader parses the unescaped text as well |

## Here-doc bodies

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `$\` newline `(cmd)` in an unquoted body | the backslash-newline goes first, so `cmd` runs | body text | handled: the reader parses the joined body as well |

## Arithmetic

Bash reads `((…))` and `$((…))` as text and evaluates it when it runs, so a bad expression fails
then and the next command still runs. When the closing `))` is missing it re-reads the text as nested
subshells. shfmt parses the expression at once and has no second reading.

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `((a\|b) ); cmd`, `echo $((a\|b) ); cmd` | nested subshells, then `cmd` | syntax error | refused |
| `((:)); cmd` | an arithmetic error at run time, then `cmd` | syntax error | refused |

## Text bash reads lazily

Bash runs a `-c` string one complete command at a time, reads a backtick's text only when it runs,
and warns about a here-doc with no delimiter line. shfmt parses the whole string first.

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `cat <<E; cmd` | the body runs to the end, with a warning, and `cmd` runs | syntax error | refused |
| `` echo `case`; cmd `` | the backtick's error is reported, and `cmd` runs | syntax error | refused |
| `cmd` then a later line with an open quote or an unbalanced `(` | `cmd` runs, then a syntax error | syntax error | refused |

## PowerShell text

The git guards reduce a PowerShell command to text they parse as Bash (`lib/powershell/ps-command.sh`).

| Form | PowerShell | Reduced text | Status |
|---|---|---|---|
| `Write-Host ""; & $py script.py`, `& $w 'f.txt'` | `&` calls the command `$py` names | the `&` is dropped: `$py script.py` | handled |
| `iex x; git status` with the dynamic-invocation sink allowed | the blanked statement leaves `; git status` | the empty `;` is dropped | handled |
| ``gh pr merge 42 --body "line`nnext"`` (block-unresolved-pr-merge, which parses the PowerShell text without a reduction) | a backtick escape | an unclosed Bash backtick | handled: that guard parses PowerShell text with every backtick dropped |

## Other forms

| Form | Bash | shfmt | Status |
|---|---|---|---|
| `x[1]=2 cmd` | a temporary assignment for `cmd` | syntax error | refused |
| `cmd` ending in CR LF | the CR is part of the last word | the CR is dropped | handled: the guard reads the word without it |
| A byte that is not valid UTF-8 | the byte, in a word | syntax error | refused |
