# shellcheck shell=bash

[[ -n "${_GUARDRAILS_PS_COMMAND_LOADED:-}" ]] && return 0
_GUARDRAILS_PS_COMMAND_LOADED=1

readonly PS_HERESTRING_PLACEHOLDER="__GUARDRAILS_PS_HERESTRING__"

PS_BLANKED=""
PS_HERESTRING_UNBALANCED=0
PS_HERESTRING_QUOTE=""
PS_HERESTRING_EXPANDABLE=0
PS_HERESTRING_EXPANDABLE_SUBEXPR=0
PS_REDUCTION_UNTRUSTED=0
PS_REDUCTION_UNTRUSTED_REASON=""
PS_QUOTED_SPAN_SAW_EXPANDABLE=0
PS_SINK_TRIGGER=""
# Read by the sourcing guard, not within this library.
# shellcheck disable=SC2034
PS_SAFE_COMMAND=""

ps::_chomp_to() {
  local __ch_s="$2"
  while [[ "$__ch_s" == *$'\n' ]]; do
    __ch_s="${__ch_s%$'\n'}"
    __ch_s="${__ch_s%$'\r'}"
  done
  printf -v "$1" '%s' "$__ch_s"
}

ps::_mark_untrusted() {
  ((PS_REDUCTION_UNTRUSTED)) && return 0
  PS_REDUCTION_UNTRUSTED=1
  PS_REDUCTION_UNTRUSTED_REASON="$1"
}

ps::has_bare_cr() {
  local s="${1//$'\r\n'/}"
  [[ "$s" == *$'\r'* ]]
}

ps::payload_has_bare_cr() {
  local s="${1-}" t
  [[ -n "$s" ]] || return 1
  ps::has_bare_cr "$s" && return 0
  [[ "$s" == *"\\r"* ]] || return 1
  t="${s//\\\\/}"
  while [[ "$t" == *"\\r"* ]]; do
    t="${t#*"\\r"}"
    [[ "$t" == "\\n"* ]] || return 0
  done
  return 1
}

ps::line_confirms_herestring_opener() {
  local opener_scan
  ps::_gsub_to opener_scan "$1" "'[^']*'" ''
  ps::_gsub_to opener_scan "$opener_scan" '"([^"\\]|\\.)*"' ''
  [[ "$opener_scan" == *"@'" || "$opener_scan" == *'@"' ]]
}

ps::_split_lines_to() {
  local -n __sl_out="$1"
  local __sl_rest="$2"
  __sl_out=()
  while [[ "$__sl_rest" == *$'\n'* ]]; do
    __sl_out+=("${__sl_rest%%$'\n'*}")
    __sl_rest="${__sl_rest#*$'\n'}"
  done
  __sl_out+=("$__sl_rest")
}

ps::_gsub_to() {
  local __gs_re="$3" __gs_repl="$4" __gs_out="" __gs_line __gs_acc __gs_pre __gs_m __gs_i
  local -a __gs_lines=()
  ps::_split_lines_to __gs_lines "$2"
  for ((__gs_i = 0; __gs_i < ${#__gs_lines[@]}; __gs_i++)); do
    __gs_line="${__gs_lines[__gs_i]}"
    ((__gs_i + 1 < ${#__gs_lines[@]})) && __gs_line="${__gs_line%$'\r'}"
    __gs_acc=""
    while [[ "$__gs_line" =~ $__gs_re ]]; do
      __gs_m="${BASH_REMATCH[0]}"
      [[ -n "$__gs_m" ]] || break
      __gs_pre="${__gs_line%%"$__gs_m"*}"
      __gs_acc+="${__gs_pre}${__gs_repl}"
      __gs_line="${__gs_line:${#__gs_pre}+${#__gs_m}}"
    done
    ((__gs_i)) && __gs_out+=$'\n'
    __gs_out+="${__gs_acc}${__gs_line}"
  done
  ps::_chomp_to "$1" "$__gs_out"
}

PS_TOKEN_SEPARATING_SPACES=(
  $'\xc2\x85'     # U+0085 NEXT LINE
  $'\xc2\xa0'     # U+00A0 NO-BREAK SPACE
  $'\xe1\x9a\x80' # U+1680 OGHAM SPACE MARK
  $'\xe2\x80\x80' # U+2000 EN QUAD
  $'\xe2\x80\x81' # U+2001 EM QUAD
  $'\xe2\x80\x82' # U+2002 EN SPACE
  $'\xe2\x80\x83' # U+2003 EM SPACE
  $'\xe2\x80\x84' # U+2004 THREE-PER-EM SPACE
  $'\xe2\x80\x85' # U+2005 FOUR-PER-EM SPACE
  $'\xe2\x80\x86' # U+2006 SIX-PER-EM SPACE
  $'\xe2\x80\x87' # U+2007 FIGURE SPACE
  $'\xe2\x80\x88' # U+2008 PUNCTUATION SPACE
  $'\xe2\x80\x89' # U+2009 THIN SPACE
  $'\xe2\x80\x8a' # U+200A HAIR SPACE
  $'\xe2\x80\xa8' # U+2028 LINE SEPARATOR
  $'\xe2\x80\xa9' # U+2029 PARAGRAPH SEPARATOR
  $'\xe2\x80\xaf' # U+202F NARROW NO-BREAK SPACE
  $'\xe2\x81\x9f' # U+205F MEDIUM MATHEMATICAL SPACE
  $'\xe3\x80\x80' # U+3000 IDEOGRAPHIC SPACE
)

PS_NORMALIZED=""
ps::normalize_token_separating_spaces() {
  local ws
  PS_NORMALIZED="$1"
  for ws in "${PS_TOKEN_SEPARATING_SPACES[@]}"; do
    PS_NORMALIZED="${PS_NORMALIZED//"$ws"/ }"
  done
}

ps::blank_herestrings() {
  ps::normalize_token_separating_spaces "$1"
  local cmd="$PS_NORMALIZED"
  local line out="" pending="" in_hs=0 hs_quote="" first2 prefix
  local saw_block_comment=0
  local -a hs_lines=()
  PS_HERESTRING_UNBALANCED=0
  PS_HERESTRING_QUOTE=""
  PS_HERESTRING_EXPANDABLE=0
  PS_HERESTRING_EXPANDABLE_SUBEXPR=0
  PS_REDUCTION_UNTRUSTED=0
  PS_REDUCTION_UNTRUSTED_REASON=""
  ps::has_bare_cr "$1" && ps::_mark_untrusted bare-cr
  [[ -n "${INPUT:-}" ]] && ps::payload_has_bare_cr "$INPUT" && ps::_mark_untrusted bare-cr

  ps::_split_lines_to hs_lines "$cmd"
  for line in "${hs_lines[@]}"; do
    line="${line%$'\r'}"
    if ((in_hs)); then
      if [[ "${line:0:2}" == "${hs_quote}@" ]]; then
        out+="${pending}${line:2}"$'\n'
        pending=""
        in_hs=0
        hs_quote=""
      elif [[ "$hs_quote" == '"' && "$line" == *"\$("* ]]; then
        PS_HERESTRING_EXPANDABLE_SUBEXPR=1
      fi
      continue
    fi
    first2="${line:0:2}"
    if [[ "$first2" == "'@" || "$first2" == '"@' ]]; then
      ps::_mark_untrusted herestring-orphan-closer
    fi
    [[ "$line" == *'<#'* ]] && saw_block_comment=1
    if ps::line_confirms_herestring_opener "$line"; then
      prefix="${line%??}"
      if [[ "$prefix" == *"#"* ]]; then
        ps::_mark_untrusted herestring-comment-char
      elif [[ "$prefix" == *"'"* || "$prefix" == *'"'* || "$prefix" == *"\\"* || "$prefix" == *'`'* ]]; then
        ps::_mark_untrusted herestring-opener-untrusted
      fi
      ((saw_block_comment)) && ps::_mark_untrusted herestring-comment-span
      hs_quote="${line: -1}"
      [[ "$hs_quote" == '"' ]] && PS_HERESTRING_EXPANDABLE=1
      pending="${prefix}${PS_HERESTRING_PLACEHOLDER}"
      in_hs=1
      continue
    fi
    out+="${line}"$'\n'
  done

  if ((in_hs)); then
    PS_HERESTRING_UNBALANCED=1
    PS_HERESTRING_QUOTE="$hs_quote"
    PS_BLANKED="$cmd"
    PS_HERESTRING_EXPANDABLE=0
    PS_HERESTRING_EXPANDABLE_SUBEXPR=0
    return 0
  fi
  PS_BLANKED="${out%$'\n'}"
}

ps::_walk_quoted_spans_to() {
  local __wq_text="$2" __wq_mode="$3" __wq_out="" __wq_i=0 __wq_n __wq_j __wq_q __wq_found __wq_c __wq_inner
  __wq_n=${#__wq_text}
  PS_QUOTED_SPAN_SAW_EXPANDABLE=0
  while ((__wq_i < __wq_n)); do
    __wq_q="${__wq_text:__wq_i:1}"
    if [[ "$__wq_q" == "'" || "$__wq_q" == '"' ]]; then
      [[ "$__wq_q" == '"' ]] && PS_QUOTED_SPAN_SAW_EXPANDABLE=1
      __wq_found=0
      for ((__wq_j = __wq_i + 1; __wq_j < __wq_n; __wq_j++)); do
        __wq_c="${__wq_text:__wq_j:1}"
        [[ "$__wq_c" == $'\n' ]] && break
        if [[ "$__wq_q" == '"' && "$__wq_c" == '`' ]] ||
          [[ "$__wq_c" == "$__wq_q" && "${__wq_text:__wq_j+1:1}" == "$__wq_q" ]]; then
          for (( ; __wq_j < __wq_n; __wq_j++)); do [[ "${__wq_text:__wq_j:1}" == $'\n' ]] && break; done
          break
        fi
        if [[ "$__wq_c" == "$__wq_q" ]]; then
          __wq_found=1
          break
        fi
      done
      if ((__wq_found)); then
        if [[ "$__wq_mode" == "opaque" ]]; then
          __wq_inner="${__wq_text:__wq_i+1:__wq_j-__wq_i-1}"
          if [[ -n "$__wq_inner" ]]; then
            if [[ "$__wq_inner" == -* && "$__wq_q" == '"' && "$__wq_inner" == *'$'* ]]; then
              __wq_out+='-_q_'
            elif [[ "$__wq_q" == '"' && "$__wq_inner" == *'$'* ]]; then
              __wq_out+="\$q"
            else
              __wq_out+='_q_'
            fi
          fi
        elif [[ "$__wq_mode" == "cmpoperand" ]]; then
          if ps::_is_comparison_operand_context "$__wq_out"; then
            __wq_out+='_q_'
          else
            __wq_out+="${__wq_text:__wq_i:__wq_j-__wq_i+1}"
          fi
        fi
        __wq_i=$((__wq_j + 1))
        continue
      fi
      __wq_out+="${__wq_text:__wq_i:__wq_j-__wq_i}"
      __wq_i=$__wq_j
      continue
    fi
    __wq_out+="$__wq_q"
    __wq_i=$((__wq_i + 1))
  done
  ps::_chomp_to "$1" "$__wq_out"
}

ps::blank_quoted_spans_to() {
  ps::_walk_quoted_spans_to "$1" "$2" blank
}

ps::_is_comparison_operand_context() {
  local p="$1" hops
  for ((hops = 0; hops < 16; hops++)); do
    if [[ "$p" =~ ^(.*[^[:space:]])[[:space:]]*$ ]]; then p="${BASH_REMATCH[1]}"; else p=""; fi
    [[ "$p" =~ (^|[^[:alnum:]_-])-[ci]?(eq|ne|in|notin|contains|notcontains|like|notlike|match|notmatch|lt|le|gt|ge)$ ]] && return 0
    case "$p" in
    *'(')
      p="${p%?}"
      if [[ "$p" =~ ^(.*[^[:space:]])[[:space:]]*$ ]]; then p="${BASH_REMATCH[1]}"; else p=""; fi
      [[ "$p" == *'@' ]] && p="${p%?}"
      ;;
    *',')
      p="${p%?}"
      if [[ "$p" =~ ^(.*[,()[:space:]])[^,()[:space:]]*$ ]]; then p="${BASH_REMATCH[1]}"; else p=""; fi
      ;;
    *) return 1 ;;
    esac
  done
  return 1
}

ps::_blank_comparison_operand_literals_to() {
  ps::_walk_quoted_spans_to "$1" "$2" cmpoperand
}

ps::_is_readonly_cmdlet() {
  case "$1" in
  gps | ps | gcim | gwmi | gci | ls | dir | gi | gc | cat | type | gsv | gcm | gmo | gv | gl | pwd) return 0 ;;
  where-object | where | '?') return 0 ;;
  select-object | select) return 0 ;;
  foreach-object | foreach | '%') return 0 ;;
  sort-object | sort | measure-object | measure | group-object | group) return 0 ;; # portability-ok: cmdlet names in a case pattern, not a sort -V invocation
  format-table | ft | format-list | fl | format-wide | fw) return 0 ;;
  out-string | out-host | oh | out-null) return 0 ;;
  write-output | write | echo | write-host) return 0 ;;
  select-string | sls) return 0 ;;
  test-path | resolve-path | rvpa | split-path | join-path) return 0 ;;
  compare-object | compare | diff) return 0 ;;
  convertto-json | convertfrom-json | convertto-csv) return 0 ;;
  if | else | elseif | in | return) return 0 ;;
  *) ;;
  esac
  [[ "$1" =~ ^get-[a-z0-9]+$ ]]
}

ps::_is_readonly_cmdlet_pipeline() {
  local lc i n ch tok="" cmdpos=1
  ps::opaque_quoted_spans_to lc "$1"
  ((PS_QUOTED_SPAN_SAW_EXPANDABLE)) && return 1
  lc="${lc,,}"
  case "$lc" in
  *'`'* | *'<#'* | *'--%'* | *'::'* | *'['* | *'&'*) return 1 ;;
  *) ;;
  esac
  [[ "$lc" =~ \.[a-z0-9_]*\( ]] && return 1
  ((${#lc} > 4096)) && return 1
  lc+=$'\n'
  n=${#lc}
  for ((i = 0; i < n; i++)); do
    ch="${lc:i:1}"
    case "$ch" in
    '|' | ';' | '{' | '}' | '(' | '=' | $'\n' | ' ' | $'\t' | $'\r' | ',' | '@' | ')' | '>' | '<' | '+' | '*') ;;
    *)
      tok+="$ch"
      continue
      ;;
    esac
    if [[ -n "$tok" ]]; then
      case "$tok" in
      '$'* | -* | '_q_') ;;
      *)
        if [[ "$tok" =~ ^[0-9]+$ ]]; then
          :
        elif ((cmdpos)); then
          ps::_is_readonly_cmdlet "$tok" || return 1
        fi
        ;;
      esac
      tok=""
      cmdpos=0
    fi
    case "$ch" in
    '|' | ';' | '{' | '}' | '(' | '=' | $'\n') cmdpos=1 ;;
    *) ;;
    esac
  done
  return 0
}

ps::opaque_quoted_spans_to() {
  ps::_walk_quoted_spans_to "$1" "$2" opaque
}

ps::fold_escaped_brace_closers_to() {
  local __fb_s="$2" __fb_out="" __fb_i __fb_n __fb_ch
  __fb_n=${#__fb_s}
  for ((__fb_i = 0; __fb_i < __fb_n; __fb_i++)); do
    __fb_ch="${__fb_s:__fb_i:1}"
    if [[ "$__fb_ch" == '`' ]] && ((__fb_i + 1 < __fb_n)); then
      case "${__fb_s:__fb_i+1:1}" in
      '}')
        __fb_out+='_'
        __fb_i=$((__fb_i + 1))
        continue
        ;;
      '`')
        __fb_out+='``'
        __fb_i=$((__fb_i + 1))
        continue
        ;;
      *)
        ;;
      esac
    fi
    __fb_out+="$__fb_ch"
  done
  ps::_chomp_to "$1" "$__fb_out"
}

ps::has_special_constructs() {
  local scan="$1"
  # The single-quoted needles are literal glob patterns, not expansions.
  # shellcheck disable=SC2016
  case "$scan" in
  *'`'*) return 0 ;;
  *'--%'*) return 0 ;;
  *'('* | *')'*) return 0 ;;
  *'{'* | *'}'*) return 0 ;;
  *) return 1 ;;
  esac
}

ps::call_target_is_bare_computed() {
  local lc="${1//\`/}"
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*[\$\(] ]]
}

ps::call_target_is_bare_subexpression() {
  local lc="${1//\`/}"
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*\$?\( ]]
}

ps::quoted_call_names_writer() {
  local q="\"'"
  [[ "$1" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*[$q]([a-z.]+\\)?(set-content|add-content|out-file|tee-object|ac|tee|iex|invoke-expression|new-item|ni|epcsv|export-[a-z]+) ]]
}

ps::computed_call_var_resolves_to_literal() {
  local v="$1" s="$2" rest head="" tail lit="" have=0 blanked i ch depth base
  local re_asg=$'^[ \t]*=[ \t]*\'([^\']*)\'[ \t]*([;\r\n]|$)'
  local re_stmt=$'(^|[;\r\n])[ \t]*$'
  local re_call='(^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*$'
  local re_byname='(^|[^a-z0-9_-])(set-variable|set|sv|new-variable|nv|get-variable|gv|clear-variable|clv|remove-variable|rv|set-item|si)([^a-z0-9_-]|$)'
  local re_commonvar='[[:space:]]-(outvariable|ov|pipelinevariable|pv|errorvariable|ev|warningvariable|wv|informationvariable|iv)([[:space:]]|:|$)'
  [[ "$v" =~ ^[a-z_][a-z0-9_]*$ ]] || return 1
  case "$v" in
  _ | psitem | args | input | this | matches | foreach | switch | sender | event | eventargs | eventsubscriber | lastexitcode | error | myinvocation | psboundparameters | pscmdlet) return 1 ;;
  *) ;;
  esac
  [[ "$s" == *'`'* ]] && return 1
  [[ "$s" =~ $re_byname || "$s" =~ $re_commonvar ]] && return 1
  [[ "$s" == *variable:* || "$s" == *psvariable* || "$s" == *":$v"* ]] && return 1
  [[ "$s" == *"\${"* && "$s" == *"$v}"* ]] && return 1
  rest="$s"
  while [[ "$rest" == *"\$$v"* ]]; do
    head+="${rest%%"\$$v"*}"
    tail="${rest#*"\$$v"}"
    rest="$tail"
    if [[ "$tail" == [a-z0-9_?:]* ]]; then
      head+="\$$v"
      continue
    fi
    if [[ "$tail" =~ $re_asg ]]; then
      if ((have)); then
        [[ "${BASH_REMATCH[1]}" == "$lit" ]] || return 1
      else
        lit="${BASH_REMATCH[1]}"
        [[ "$head" =~ $re_stmt ]] || return 1
        ps::blank_quoted_spans_to blanked "$head"
        depth=0
        for ((i = 0; i < ${#blanked}; i++)); do
          ch="${blanked:i:1}"
          case "$ch" in
          '{' | '(') depth=$((depth + 1)) ;;
          '}' | ')') depth=$((depth - 1)) ;;
          *) ;;
          esac
          ((depth < 0)) && return 1
        done
        ((depth == 0)) || return 1
        have=1
      fi
    elif ((!have)) || [[ ! "$head" =~ $re_call ]]; then
      return 1
    fi
    head+="\$$v"
  done
  ((have)) || return 1
  base="${lit##*[/\\:]}"
  case "$base" in
  *.exe | *.cmd | *.bat | *.ps1) base="${base%.*}" ;;
  *) ;;
  esac
  [[ "$base" == *[\*\?\[[:space:]]* || "$base" == sc ]] && return 1
  ! ps::quoted_call_names_writer "& '$base'"
}

ps::call_site_operand_region_to() {
  local __cs_s="$2" __cs_out="" __cs_i __cs_ch __cs_depth=0
  for ((__cs_i = 0; __cs_i < ${#__cs_s}; __cs_i++)); do
    __cs_ch="${__cs_s:__cs_i:1}"
    case "$__cs_ch" in
    '{' | '(')
      __cs_depth=$((__cs_depth + 1))
      ;;
    '}' | ')')
      ((__cs_depth == 0)) && break
      __cs_depth=$((__cs_depth - 1))
      ;;
    ';' | '|' | '&')
      ((__cs_depth == 0)) && break
      ;;
    *)
      ;;
    esac
    __cs_out+="$__cs_ch"
  done
  ps::_chomp_to "$1" "$__cs_out"
}

ps::blank_bracket_interiors_to() {
  local __bb_s="$2" __bb_out="" __bb_i __bb_ch __bb_depth=0
  for ((__bb_i = 0; __bb_i < ${#__bb_s}; __bb_i++)); do
    __bb_ch="${__bb_s:__bb_i:1}"
    case "$__bb_ch" in
    '{' | '(')
      __bb_out+="$__bb_ch"
      __bb_depth=$((__bb_depth + 1))
      continue
      ;;
    '}' | ')')
      ((__bb_depth > 0)) && __bb_depth=$((__bb_depth - 1))
      __bb_out+="$__bb_ch"
      continue
      ;;
    *)
      ;;
    esac
    if ((__bb_depth > 0)); then __bb_out+=" "; else __bb_out+="$__bb_ch"; fi
  done
  ps::_chomp_to "$1" "$__bb_out"
}

ps::computed_call_has_positional_write_signal() {
  local lc="$1" resolve_text="${2-}" rest="" tok count count_lit piped=0 scan depth opens closes target
  local re_var='(^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*(\$\{[^}]*\}[^[:space:]]*|\$[a-z0-9_:?]+)([[:space:]]+|$)(.*)'
  local re_pipe='^(.*)[.\&][[:space:]]*\$'
  lc="${lc//\`/}"
  lc="${lc,,}"
  if [[ "$lc" =~ $re_pipe ]]; then
    [[ "${BASH_REMATCH[1]}" == *'|'* ]] && piped=1
  fi
  scan="$lc"
  while [[ "$scan" =~ $re_var ]]; do
    rest="${BASH_REMATCH[4]}"
    target="${BASH_REMATCH[2]}"
    scan="$rest"
    if [[ -n "$resolve_text" ]] &&
      ps::computed_call_var_resolves_to_literal "${target#\$}" "$resolve_text"; then
      continue
    fi
    count=0
    count_lit=0
    depth=0
    ps::call_site_operand_region_to rest "$rest"
    ps::_gsub_to rest "$rest" '[0-9*]*>+[^[:space:]]*' ''
    ps::_gsub_to rest "$rest" '[0-9*]*<+[^[:space:]]*' ''
    # shellcheck disable=SC2086 # intentional word-split on PowerShell tokens
    for tok in $rest; do
      [[ -z "$tok" ]] && continue
      opens="${tok//[^\(\{]/}"
      closes="${tok//[^\)\}]/}"
      if ((depth > 0)); then
        depth=$((depth + ${#opens} - ${#closes}))
        ((depth < 0)) && depth=0
        continue
      fi
      [[ "$tok" == -* ]] && break
      count=$((count + 1))
      depth=$((${#opens} - ${#closes}))
      ((depth < 0)) && depth=0
      if [[ "$tok" == [\(\{]* ]] || ((depth > 0)); then
        continue
      fi
      if [[ "$tok" != \$* && "$tok" != @* ]]; then
        count_lit=$((count_lit + 1))
      fi
    done
    ((count >= 2 && count_lit >= 1 || piped == 1 && count >= 1)) && return 0
  done
  return 1
}

ps::computed_call_has_splat_operand() {
  local lc="$1" rest scan
  local re_var='(^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*(\$\{[^}]*\}[^[:space:]]*|\$[a-z0-9_:?]+)([[:space:]]+|$)(.*)'
  lc="${lc//\`/}"
  lc="${lc,,}"
  scan="$lc"
  while [[ "$scan" =~ $re_var ]]; do
    rest="${BASH_REMATCH[4]}"
    scan="$rest"
    ps::call_site_operand_region_to rest "$rest"
    ps::blank_bracket_interiors_to rest "$rest"
    if [[ "$rest" =~ (^|[[:space:]])@[a-z0-9_:]+ ]]; then
      return 0
    fi
  done
  return 1
}

ps::call_target_is_interpolating_string() {
  local lc="${1//\`/}"
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*\"[^\"]*\$ ]]
}

ps::might_invoke_git() {
  local recovered="${1//\`/}" lc narrowed
  lc="${recovered,,}"
  if [[ "$lc" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]]; then
    ps::_is_readonly_cmdlet_pipeline "$1" || return 0
    ps::_blank_comparison_operand_literals_to narrowed "$lc"
    [[ "$narrowed" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]] && return 0
  fi
  [[ "$lc" =~ (^|[^[:alnum:]_-])(iex|invoke-expression)([^[:alnum:]_-]|$) ]] && return 0
  ps::call_target_is_bare_subexpression "$recovered" && return 0
  ps::call_target_is_interpolating_string "$recovered" && return 0
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(=])(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?[[:space:]]+(-[a-z]+[[:space:]]+)?[\(\$] ]] && return 0
  return 1
}

ps::git_command_is_readonly() {
  local recovered="${1//\`/}" lc
  lc="${recovered,,}"
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]] || return 1
  while [[ "$lc" =~ (^|[^[:alnum:]_.-])(remote([[:space:]]+(-v|--verbose))?[[:space:]]*([\;\|\}\)]|$)|remote[[:space:]]+(show|get-url)|stash[[:space:]]+(list|show))([^[:alnum:]_.-]|$) ]]; do
    lc="${lc/"${BASH_REMATCH[0]}"/ }"
  done
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(add|am|annex|apply|bisect|branch|checkout|checkout-index|cherry-pick|citool|clean|commit)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(commit-graph|config|credential|credential-cache|credential-store|cvsexportcommit|fast-import|filter-branch|filter-repo|gc|gui|http-push|interpret-trailers|lfs)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(maintenance|merge|merge-file|merge-index|merge-one-file|mergetool|multi-pack-index|mv|notes|p4|prune)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(prune-packed|pull|push|quiltimport|read-tree|rebase|receive-pack|reflog|remote|repack)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(replace|rerere|reset|restore|revert|rm|send-pack|sparse-checkout|stage|stash)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(submodule|subtree|svn|switch|symbolic-ref|tag|update-index|update-ref|update-server-info|worktree)([^[:alnum:]_.-]|$) ]] && return 1
  return 0
}

ps::_is_plain_word() {
  [[ "$1" =~ ^[a-z0-9_.:\\/~*?-]+$ ]]
}

ps::_operands_plain_to() {
  local __op_out="$1" __op_a __op_name __op_val __op_depth __op_lit=0 __op_skip=0 __op_rc=0
  shift
  while (($#)); do
    __op_a="$1"
    shift
    [[ "$__op_a" == ';' ]] && break
    if ((__op_skip)); then
      __op_skip=0
      if [[ "$__op_a" == '(' ]]; then
        __op_depth=1
        while (($# && __op_depth > 0)); do
          [[ "$1" == '(' ]] && __op_depth=$((__op_depth + 1))
          [[ "$1" == ')' ]] && __op_depth=$((__op_depth - 1))
          shift
        done
      fi
      continue
    fi
    case "$__op_a" in
    ')') break ;;
    -*)
      __op_name="${__op_a#-}"
      __op_val=""
      if [[ "$__op_name" == *:* ]]; then
        __op_val="${__op_name#*:}"
        __op_name="${__op_name%%:*}"
      fi
      if [[ "$__op_name" == va* ]]; then
        [[ -n "$__op_val" ]] || __op_skip=1
      elif [[ -n "$__op_val" ]]; then
        ps::_is_plain_word "$__op_val" || __op_rc=1
        __op_lit=$((__op_lit + 1))
      fi
      ;;
    *)
      ps::_is_plain_word "$__op_a" || __op_rc=1
      __op_lit=$((__op_lit + 1))
      ;;
    esac
  done
  printf -v "$__op_out" '%s' "$__op_lit"
  return "$__op_rc"
}

ps::has_unprovable_env_write() {
  local IFS=$' \t\n'
  local recovered="${1//\`/}" lc opaque s ch head a k j n nlit env_lhs write_head=0 dyn_cd=0
  local -a t=()
  lc="${recovered,,}"
  # shellcheck disable=SC2016  # literal PowerShell `$env:` text, not expansions
  local env_assign='\$\{?env:[^[:space:]=]+[[:space:]]*((\?\?|[-+*/%])?=)'
  [[ "$lc" =~ $env_assign ]] && return 0
  ps::call_target_is_bare_computed "$recovered" && return 0
  ps::opaque_quoted_spans_to opaque "$recovered"
  # shellcheck disable=SC2016  # literal PowerShell `$(` text
  ((PS_QUOTED_SPAN_SAW_EXPANDABLE)) && [[ "$lc" == *'$('* ]] && return 0
  opaque="${opaque,,}"
  for s in "$lc" "$opaque"; do
    s="${s//\$\{env:/}"
    s="${s//\$env:/}"
    [[ "$s" == *env:* || "$s" == *environment:* || "$s" == *function:* || "$s" == *alias:* ]] && return 0
  done
  [[ "$opaque" == *::* || "$opaque" == *'[ref]'* || "$opaque" =~ \.[[:space:]]*[\$a-z0-9_{}:]*\( ]] && return 0
  s="$opaque"
  while [[ "$s" =~ ^(.*)\$\{env:([^\}]*)\}(.*)$ ]]; do
    s="${BASH_REMATCH[1]}\$env:${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
  done
  for ch in ';' '|' '&' '{' '}' $'\n'; do s="${s//"$ch"/ ; }"; done
  for ch in '(' ')' ',' '='; do s="${s//"$ch"/ $ch }"; done
  read -ra t <<<"$s"
  n=${#t[@]}
  for ((k = 0; k < n; k++)); do
    if ((k == 0)) || [[ "${t[k - 1]}" == ';' || "${t[k - 1]}" == '(' ]]; then
      env_lhs=0
      for ((j = k; j < n; j++)); do
        # shellcheck disable=SC2016  # literal PowerShell `$env:` text
        case "${t[j]}" in
        *'$env:'*) env_lhs=1 ;;
        '$'* | '['* | ',' | '(' | ')') ;;
        '=' | in)
          ((env_lhs)) && return 0
          break
          ;;
        *) break ;;
        esac
      done
    fi
    head="${t[k]}"
    [[ "$head" != _q_ && "$head" =~ ^[a-z0-9_.:\\/~*?-]*_q_[a-z0-9_.:\\/~*?-]*$ ]] && return 0
    [[ "$head" =~ ^[a-z0-9_.]+\\([a-z-]+)$ ]] && head="${BASH_REMATCH[1]}"
    a="${t[k + 1]-;}"
    case "$head" in
    function | filter | set-alias | sal | new-alias | nal | add-type | new-psdrive | ndr | mount | invoke-command | icm) return 0 ;;
    env | env.exe | */env | */env.exe | *\\env | *\\env.exe) return 0 ;;
    set-location | sl | cd | chdir | push-location | pushd) ps::_operands_plain_to nlit "${t[@]:k+1}" && ((nlit)) || dyn_cd=1 ;;
    foreach-object | foreach | '%') [[ "$a" == ';' || "$a" == '(' || ("$a" == -* && "$a" != -m*) ]] || return 0 ;;
    set-item | si | new-item | ni | mkdir | md | set-content | sc | add-content | ac | copy-item | cpi | copy | cp | move-item | mi | move | mv | rename-item | rni | ren | set-itemproperty | sp | new-itemproperty | copy-itemproperty | cpp | move-itemproperty | mp | rename-itemproperty | rnp)
      write_head=1
      ps::_operands_plain_to nlit "${t[@]:k+1}" && ((nlit)) || return 0
      ;;
    *) ;;
    esac
  done
  ((write_head && dyn_cd))
}

ps::git_command_is_interrogation_only() {
  local recovered="${1//\`/}" lc opaque s tok ch i k j sub next n_probe=0 n_git=0
  local -a toks=()
  lc="${recovered,,}"
  ps::has_unprovable_env_write "$1" && return 1
  ps::has_dynamic_invocation "$1" && return 1
  ps::has_launcher "$1" && return 1
  ps::call_target_is_interpolating_string "$recovered" && return 1
  s="$lc"
  while [[ "$s" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]]; do
    n_probe=$((n_probe + 1))
    s="${s#*"${BASH_REMATCH[0]}"}"
  done
  ((n_probe > 0)) || return 1
  ps::opaque_quoted_spans_to opaque "$recovered"
  tok=""
  for ((i = 0; i < ${#opaque}; i++)); do
    ch="${opaque:i:1}"
    case "$ch" in
    [[:space:]] | '=')
      [[ -n "$tok" ]] && toks+=("$tok")
      tok=""
      ;;
    ';' | '|' | '&' | '{' | '}' | '(' | ')' | ',')
      [[ -n "$tok" ]] && toks+=("$tok")
      tok=""
      toks+=(';')
      ;;
    *) tok+="$ch" ;;
    esac
  done
  [[ -n "$tok" ]] && toks+=("$tok")
  for ((k = 0; k < ${#toks[@]}; k++)); do
    [[ "${toks[k],,}" =~ (^|[/\\:])git([.]exe)?$ ]] || continue
    n_git=$((n_git + 1))
    j=$((k + 1))
    while ((j < ${#toks[@]})); do
      case "${toks[j]}" in
      -C)
        [[ "${toks[j + 1]-;}" != ';' ]] || return 1
        j=$((j + 2))
        ;;
      --no-pager | -P | --no-optional-locks | --literal-pathspecs) j=$((j + 1)) ;;
      *) break ;;
      esac
    done
    sub="${toks[j]-}"
    next="${toks[j + 1]-;}"
    case "$sub" in
    status | log | show | diff | rev-parse | ls-files | ls-tree | cat-file | describe | blame | shortlog | for-each-ref | show-ref | merge-base | rev-list | name-rev | count-objects | version | cherry | range-diff | check-ignore | check-attr) ;;
    remote)
      case "$next" in
      ';' | show | get-url) ;;
      -v | --verbose) [[ "${toks[j + 2]-;}" == ';' ]] || return 1 ;;
      *) return 1 ;;
      esac
      ;;
    stash)
      case "$next" in
      list | show) ;;
      *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
    esac
  done
  ((n_git == n_probe))
}

ps::might_write_via_python3() {
  local recovered="${1//\`/}" lc q="\"'" blanked
  lc="${recovered,,}"
  ps::blank_quoted_spans_to blanked "$1"
  ps::has_launcher "$recovered" && [[ "$blanked" == *'$'* || "$blanked" == *'('* ]] && return 0
  ps::call_target_is_interpolating_string "$recovered" && return 0
  [[ "$lc" =~ (^|[^[:alnum:]_.])(pypy|python|py)[0-9]*([.][0-9]+)*([.]exe)?([^[:alnum:]_.]|$) ]] || return 1
  [[ "$lc" =~ (^|[[:space:]$q])-c([[:space:]$q]|$) ]] && return 0
  [[ "$lc" =~ (^|[[:space:]$q])-c[\$\(] ]] && return 0
  ps::has_special_constructs "$blanked" && return 0
  return 1
}

ps::has_dynamic_invocation() {
  local recovered="${1//\`/}" lc q="\"'" blanked
  lc="${recovered,,}"
  [[ "$lc" =~ (^|[^[:alnum:]_-])(iex|invoke-expression)([^[:alnum:]_-]|$) ]] && return 0
  [[ "$recovered" =~ (^|[[:space:]\;\{\}\(\|\&])[.\&][[:space:]]*[$q] ]] && return 0
  [[ "$recovered" =~ (^|[[:space:]\;\{\}\(\|\&])\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*[.\&][[:space:]]*[$q] ]] || return 1
  ps::blank_quoted_spans_to blanked "$recovered"
  [[ "$blanked" =~ \$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*[.\&] ]]
}

ps::has_launcher() {
  local lc="${1//\`/}" blanked
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(])(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?([[:space:]]|$) ]] && return 0
  ps::blank_quoted_spans_to blanked "$lc"
  [[ "$blanked" =~ (^|[[:space:]\;\|\&\(])\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?([[:space:]]|$) ]]
}

ps::classify_git_command() {
  local tool="$1" cmd="$2" sink_scope="${3:-mutating}" scan
  PS_SAFE_COMMAND="$cmd"
  PS_SINK_TRIGGER=""
  [[ "$tool" == "PowerShell" ]] || return 0

  ps::blank_herestrings "$cmd"
  ps::blank_quoted_spans_to scan "$PS_BLANKED"
  if ((PS_HERESTRING_UNBALANCED)); then
    PS_SINK_TRIGGER="herestring-unbalanced"
  elif ps::has_special_constructs "$scan"; then
    PS_SINK_TRIGGER="special-construct"
  elif ps::has_dynamic_invocation "$PS_BLANKED"; then
    PS_SINK_TRIGGER="dynamic-invocation"
  elif ps::has_launcher "$PS_BLANKED"; then
    PS_SINK_TRIGGER="launcher"
  elif ((PS_HERESTRING_EXPANDABLE_SUBEXPR)); then
    PS_SINK_TRIGGER="herestring-subexpr"
  fi
  if [[ -n "$PS_SINK_TRIGGER" ]]; then
    ((PS_REDUCTION_UNTRUSTED)) && return 2
    ((PS_HERESTRING_EXPANDABLE)) && return 2
    ps::might_invoke_git "$PS_BLANKED" || return 1
    if [[ "$sink_scope" == "readonly-ok" ]] && ps::git_command_is_readonly "$PS_BLANKED"; then
      return 1
    fi
    if [[ "$sink_scope" == "interrogation-ok" && "$PS_SINK_TRIGGER" == "special-construct" ]] &&
      ps::git_command_is_interrogation_only "$PS_BLANKED"; then
      return 1
    fi
    return 2
  fi
  if ((PS_REDUCTION_UNTRUSTED)); then
    PS_SINK_TRIGGER="${PS_REDUCTION_UNTRUSTED_REASON:-herestring-comment-char}"
    return 2
  fi
  local reduced="${PS_BLANKED//\\//}"
  ps::_gsub_to reduced "$reduced" '[Gg][Ii][Tt]\.[Ee][Xx][Ee]' git
  ps::_gsub_to reduced "$reduced" '\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*(\+=|-=|\*=|/=|%=|=)[[:space:]]*' ' '
  # Read by the sourcing guard, not within this library.
  # shellcheck disable=SC2034
  ps::_bash_ready_to PS_SAFE_COMMAND "$reduced"
  return 0
}

ps::blank_sink_opaque_regions() {
  local cmd="$1" trigger="$2"
  case "$trigger" in
  dynamic-invocation) ps::_blank_cmd_statements "$cmd" "dynamic" ;;
  launcher) ps::_blank_cmd_statements "$cmd" "launcher" ;;
  special-construct) ps::_blank_special_construct_regions "$cmd" ;;
  herestring-unbalanced) ps::_blank_unbalanced_herestring_tail "$cmd" ;;
  herestring-subexpr)
    ps::blank_herestrings "$cmd"
    # shellcheck disable=SC2034
    PS_SAFE_COMMAND="$PS_BLANKED"
    ;;
  *)
    # shellcheck disable=SC2034
    PS_SAFE_COMMAND=""
    ;;
  esac
}

ps::_at_command_position() {
  local cmd="$1" idx="$2" prev
  ((idx == 0)) && return 0
  prev="${cmd:idx-1:1}"
  [[ "$prev" == [[:space:]\;\|\&\{\}\(\)] ]]
}

ps::_skip_double_quote_to() {
  local __dq_cmd="$2" __dq_i="$3" __dq_n=${#2} __dq_c
  __dq_i=$((__dq_i + 1))
  while ((__dq_i < __dq_n)); do
    __dq_c="${__dq_cmd:__dq_i:1}"
    if [[ "$__dq_c" == '`' ]]; then
      __dq_i=$((__dq_i + 2))
      continue
    fi
    if [[ "$__dq_c" == '"' ]]; then
      printf -v "$1" '%s' "$((__dq_i + 1))"
      return 0
    fi
    __dq_i=$((__dq_i + 1))
  done
  printf -v "$1" '%s' "$__dq_n"
}

ps::_skip_single_quote_to() {
  local __sq_cmd="$2" __sq_i="$3" __sq_n=${#2} __sq_c
  __sq_i=$((__sq_i + 1))
  while ((__sq_i < __sq_n)); do
    __sq_c="${__sq_cmd:__sq_i:1}"
    if [[ "$__sq_c" == "'" ]]; then
      printf -v "$1" '%s' "$((__sq_i + 1))"
      return 0
    fi
    __sq_i=$((__sq_i + 1))
  done
  printf -v "$1" '%s' "$__sq_n"
}

ps::_skip_statement_tail_to() {
  local __st_cmd="$2" __st_i="$3" __st_n=${#2} __st_depth=0 __st_c
  while ((__st_i < __st_n)); do
    __st_c="${__st_cmd:__st_i:1}"
    if ((__st_depth == 0)); then
      if [[ "$__st_c" == "'" ]]; then
        ps::_skip_single_quote_to __st_i "$__st_cmd" "$__st_i"
        continue
      fi
      if [[ "$__st_c" == '"' ]]; then
        ps::_skip_double_quote_to __st_i "$__st_cmd" "$__st_i"
        continue
      fi
      if [[ "$__st_c" == ';' || "$__st_c" == $'\n' || "$__st_c" == '|' ]] ||
        [[ "$__st_c" == '&' && "${__st_cmd:__st_i+1:1}" == '&' ]]; then
        printf -v "$1" '%s' "$__st_i"
        return 0
      fi
    fi
    case "$__st_c" in
    '{' | '(') __st_depth=$((__st_depth + 1)) ;;
    '}' | ')') ((__st_depth > 0)) && __st_depth=$((__st_depth - 1)) ;;
    *) ;;
    esac
    __st_i=$((__st_i + 1))
  done
  printf -v "$1" '%s' "$__st_n"
}

ps::_bash_ready_to() {
  local __br_cmd="$2" __br_i=0 __br_n=${#2} __br_c __br_end __br_out="" __br_word=0
  while ((__br_i < __br_n)); do
    __br_c="${__br_cmd:__br_i:1}"
    case "$__br_c" in
    "'" | '"')
      if [[ "$__br_c" == "'" ]]; then
        ps::_skip_single_quote_to __br_end "$__br_cmd" "$__br_i"
      else
        ps::_skip_double_quote_to __br_end "$__br_cmd" "$__br_i"
      fi
      __br_out+="${__br_cmd:__br_i:__br_end-__br_i}"
      __br_i=$__br_end
      __br_word=1
      continue
      ;;
    '#')
      if [[ "${__br_out: -1}" == '' || "${__br_out: -1}" == [[:space:]\;\|\&] ]]; then
        __br_end="${__br_cmd:__br_i}"
        __br_end="${__br_end%%$'\n'*}"
        __br_out+="$__br_end"
        __br_i=$((__br_i + ${#__br_end}))
        continue
      fi
      __br_word=1
      ;;
    ';' | $'\n')
      if [[ "$__br_c" == ';' ]] && ((!__br_word)); then
        __br_out+=' '
        __br_i=$((__br_i + 1))
        continue
      fi
      __br_word=0
      ;;
    '&' | '|')
      if [[ "${__br_cmd:__br_i+1:1}" == "$__br_c" ]]; then
        __br_out+="$__br_c$__br_c"
        __br_i=$((__br_i + 2))
        __br_word=0
        continue
      fi
      if [[ "$__br_c" == '&' ]] && ((!__br_word)); then
        __br_out+=' '
        __br_i=$((__br_i + 1))
        continue
      fi
      __br_word=0
      ;;
    [[:space:]]) ;;
    *) __br_word=1 ;;
    esac
    __br_out+="$__br_c"
    __br_i=$((__br_i + 1))
  done
  printf -v "$1" '%s' "$__br_out"
}

ps::_blank_cmd_statements() {
  local cmd="$1" kind="$2" n=${#1} i=0 out="" c lc end blank_from j
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      if [[ "$c" == "'" ]]; then
        ps::_skip_single_quote_to end "$cmd" "$i"
      else
        ps::_skip_double_quote_to end "$cmd" "$i"
      fi
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    blank_from=-1
    if ps::_at_command_position "$cmd" "$i"; then
      lc="${cmd:i}"
      lc="${lc,,}"
      case "$kind" in
      dynamic)
        if [[ "$lc" =~ ^(iex|invoke-expression)([^a-z0-9_-]|$) ]]; then
          if [[ "$lc" == iex* ]]; then blank_from=$((i + 3)); else blank_from=$((i + 18)); fi
        elif [[ "$c" == '&' || "$c" == '.' ]]; then
          j=$((i + 1))
          while ((j < n)) && [[ "${cmd:j:1}" == [[:space:]] ]]; do j=$((j + 1)); done
          if ((j < n)) && [[ "${cmd:j:1}" == "'" || "${cmd:j:1}" == '"' ]]; then
            blank_from=$i
          fi
        fi
        ;;
      launcher)
        if [[ "$lc" =~ ^(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?([^a-z0-9_-]|$) ]]; then
          blank_from=$i
        fi
        ;;
      *) ;;
      esac
    fi
    if ((blank_from >= 0)); then
      ps::_skip_statement_tail_to i "$cmd" "$blank_from"
      out+=" "
      continue
    fi
    out+="$c"
    i=$((i + 1))
  done
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="$out"
}

ps::_blank_special_construct_regions() {
  local cmd="$1" n=${#1} i=0 out="" c end depth open close
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      if [[ "$c" == "'" ]]; then
        ps::_skip_single_quote_to end "$cmd" "$i"
      else
        ps::_skip_double_quote_to end "$cmd" "$i"
      fi
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    if [[ "$c" == '`' ]]; then
      i=$((i + 2))
      out+=" "
      continue
    fi
    if [[ "${cmd:i:3}" == '--%' ]]; then
      ps::_skip_statement_tail_to end "$cmd" "$i"
      i=$end
      out+=" "
      continue
    fi
    if [[ "$c" == '{' || "$c" == '(' ]]; then
      open="$c"
      if [[ "$open" == '{' ]]; then close='}'; else close=')'; fi
      depth=1
      i=$((i + 1))
      while ((i < n && depth > 0)); do
        c="${cmd:i:1}"
        if [[ "$c" == "'" ]]; then
          ps::_skip_single_quote_to i "$cmd" "$i"
          continue
        fi
        if [[ "$c" == '"' ]]; then
          ps::_skip_double_quote_to i "$cmd" "$i"
          continue
        fi
        if [[ "$c" == '`' ]]; then
          i=$((i + 2))
          continue
        fi
        if [[ "$c" == "$open" ]]; then
          depth=$((depth + 1))
        elif [[ "$c" == "$close" ]]; then
          depth=$((depth - 1))
        fi
        i=$((i + 1))
      done
      out+=" "
      continue
    fi
    out+="$c"
    i=$((i + 1))
  done
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="$out"
}

ps::_blank_unbalanced_herestring_tail() {
  local cmd="$1" line out="" pending="" in_hs=0 hs_quote=""
  local -a hs_lines=()
  ps::_split_lines_to hs_lines "$cmd"
  for line in "${hs_lines[@]}"; do
    line="${line%$'\r'}"
    if ((in_hs)); then
      if [[ "${line:0:2}" == "${hs_quote}@" ]]; then
        out+="${pending}${line:2}"$'\n'
        pending=""
        in_hs=0
        hs_quote=""
      fi
      continue
    fi
    if ps::line_confirms_herestring_opener "$line"; then
      hs_quote="${line: -1}"
      pending="${line%??}"
      in_hs=1
      continue
    fi
    out+="${line}"$'\n'
  done
  if ((in_hs)); then
    # Hanging opener: keep only the prefix before it; drop the opaque tail.
    # shellcheck disable=SC2034
    PS_SAFE_COMMAND="$out$pending"
    return 0
  fi
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="${out%$'\n'}"
}

ps::print_sink_trigger_line() {
  local closer
  case "$PS_SINK_TRIGGER" in
  herestring-unbalanced)
    case "$PS_HERESTRING_QUOTE" in
    "'") closer="the '@ terminator" ;;
    '"') closer="the \"@ terminator" ;;
    *) closer="the terminator matching the opener (@' closes with '@, @\" closes with \"@)" ;;
    esac
    echo "Trigger: an unbalanced here-string. Close it: $closer must start at column 0." >&2
    ;;
  special-construct)
    echo "Trigger: a construct the guard cannot tokenize (backtick, '--%', subexpression, or {}/() grouping). Rewrite it as flat statements (unroll the loop or grouping, one command per line), or use the Bash tool." >&2
    ;;
  dynamic-invocation)
    echo "Trigger: a dynamic invocation (iex/Invoke-Expression, or a call '&' / dot-source '.' with a quoted-string target, a constant one included). Drop the iex/'&'/'.' and write the program as a plain command word, or use the Bash tool." >&2
    ;;
  launcher)
    echo "Trigger: a process launcher or nested shell (Start-Process/saps/start, pwsh, powershell, cmd). Run the launched command directly ('git status', not \"pwsh -Command 'git status'\"; for a repo script, 'Set-Location <dir>; & ./<script>.ps1'), or use the Bash tool." >&2
    ;;
  herestring-subexpr)
    echo "Trigger: an expandable here-string (@\" … \"@) containing '\$( … )'. Use a verbatim here-string (@' … '@) or compute the value into a variable first, or use the Bash tool." >&2
    ;;
  herestring-comment-char)
    echo "Trigger: a here-string opener (@' or @\") on a line that also contains a '#'. Drop the comment or move the opener to a line of its own, or use the Bash tool." >&2
    ;;
  herestring-opener-untrusted)
    echo "Trigger: a here-string opener (@' or @\") on a line that also contains a quote, backslash, or backtick. Move the opener to a line of its own, or use the Bash tool." >&2
    ;;
  herestring-comment-span)
    echo "Trigger: a here-string opener (@' or @\") after a '<#' block-comment opener. Close the block comment before the here-string, or use the Bash tool." >&2
    ;;
  herestring-orphan-closer)
    echo "Trigger: a here-string closer ('@ or \"@) at column zero with no confirmed opener. Write a balanced here-string, or use the Bash tool." >&2
    ;;
  bare-cr)
    echo "Trigger: a carriage return that is not part of a CRLF pair. Use LF or CRLF line endings, or use the Bash tool." >&2
    ;;
  *)
    echo "Rewrite the command in PowerShell without the unparsable construct, or run it via the Bash tool." >&2
    ;;
  esac
}

ps::print_unparsable_block_message() {
  ps::_sink_once || return 0
  local lc="${1,,}"
  echo "BLOCKED: this PowerShell command cannot be parsed with confidence." >&2
  ps::print_sink_trigger_line
  if (($# == 0)) || [[ "$lc" =~ (^|[^a-z0-9_-])git[[:space:]]([^\;\|\&]*[[:space:]])?commit([^a-z0-9_-]|$) ]]; then
    echo "The canonical PowerShell commit form (a here-string piped to 'git commit -F -') is:" >&2
    echo "  @'" >&2
    echo "  <subject>" >&2
    echo "  '@ | git commit -F -" >&2
    echo "or commit via the Bash tool (/source-control:commit)." >&2
  fi
  ps::print_sink_token_line block-dangerous-git
}

ps::print_sink_token_line() {
  case "$PS_SINK_TRIGGER" in
  herestring-comment-char | herestring-opener-untrusted | herestring-comment-span | herestring-orphan-closer | bare-cr)
    echo "No allow token exists for this shape; rewrite it." >&2
    return
    ;;
  *) ;;
  esac
  echo "False positive: the user adds ps-unparsable-${PS_SINK_TRIGGER:-<trigger>} to block_dangerous_git_allow; it clears $1 too." >&2
}

_PS_SINK_SAID=" "
ps::_sink_once() {
  local key="${1:-trigger:${PS_SINK_TRIGGER:-}}"
  [[ "$_PS_SINK_SAID" == *" $key "* ]] && return 1
  _PS_SINK_SAID+="$key "
}

ps::print_sink_budget_message() {
  ps::_sink_once budget || return 0
  echo "BLOCKED: this PowerShell command is still unparsable after five allowed sink shapes were set aside, and could reach git. No allow token clears this; split it into smaller commands." >&2
}

ps::print_unparsable_git_block_message() {
  ps::_sink_once || return 0
  echo "BLOCKED: this PowerShell command cannot be parsed with confidence and could reach git." >&2
  ps::print_sink_trigger_line
  ps::print_sink_token_line block-no-verify
}

PS_WRITE_BYPASS_ARM=""
ps::write_bypass() {
  local cmd="$1" scan lcs seg head lcq lcq_bt blanked_gate opaque_gate
  PS_WRITE_BYPASS_ARM=""
  ps::blank_herestrings "$cmd"
  ((PS_REDUCTION_UNTRUSTED)) && return 0

  ps::fold_escaped_brace_closers_to lcq "$PS_BLANKED"
  lcq_bt="${lcq,,}"
  lcq="${lcq//\`/}"
  lcq="${lcq,,}"
  ps::quoted_call_names_writer "$lcq" && return 0
  if ps::call_target_is_bare_computed "$lcq"; then
    ps::blank_quoted_spans_to blanked_gate "$lcq_bt"
    blanked_gate="${blanked_gate//\`/}"
    ps::_gsub_to blanked_gate "$blanked_gate" '[0-9*]*>&[0-9]+' ''
    ps::opaque_quoted_spans_to opaque_gate "$lcq_bt"
    opaque_gate="${opaque_gate//\`/}"
    ps::_gsub_to opaque_gate "$opaque_gate" '[0-9*]*>&[0-9]+' ''
    if ps::call_target_is_bare_subexpression "$blanked_gate" ||
      [[ "$blanked_gate" == *'--%'* ]] ||
      ps::computed_call_has_splat_operand "$blanked_gate" ||
      [[ "$blanked_gate" == *'>'* ]] ||
      [[ "$blanked_gate" =~ [[:space:]]-va[a-z]*([[:space:]]|:) ]]; then
      return 0
    fi
    if ps::computed_call_has_positional_write_signal "$opaque_gate" "$lcq_bt"; then
      # shellcheck disable=SC2034 # read by the sourcing guard
      PS_WRITE_BYPASS_ARM="computed-positional"
      return 0
    fi
  fi

  ps::blank_quoted_spans_to scan "$PS_BLANKED"
  scan="${scan//\`/}"
  lcs="${scan,,}"

  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(set-content|add-content|out-file|tee-object|ac|tee)([[:space:]]|$) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(])sc[[:space:]] ]] &&
    [[ "$lcs" =~ [[:space:]]-(va[a-z]*|path|literalpath|lp|stream)([[:space:]]|:) ]]; then
    return 0
  fi

  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(iex|invoke-expression)([[:space:]]|$) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(new-item|ni)([[:space:]]) ]] &&
    [[ "$lcs" =~ [[:space:]]-va[a-z]*([[:space:]]|:) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(export-[a-z]+|epcsv)([[:space:]]|$) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ io\.file\][^:]*::[[:space:]]*(writeall|appendall) ]] ||
    [[ "$lcs" =~ streamwriter ]]; then
    return 0
  fi

  ps::_gsub_to lcs "$lcs" '[0-9*]*>&[0-9]+' ''
  local norm="${lcs//[|;&]/$'\n'}"
  local -a seg_lines=()
  ps::_split_lines_to seg_lines "$norm"
  for seg in "${seg_lines[@]}"; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [[ "$seg" == *'>'* ]] || continue
    # Exclude the `$null` discard (PowerShell's /dev/null).
    # portability-ok: `\>` is a literal `>` in a bash [[ =~ ]] ERE, not GNU grep's word boundary.
    [[ "$seg" =~ \>\>?[[:space:]]*\$null([[:space:]]|$) ]] && continue
    seg="${seg//[()]/}"
    seg="${seg//\{/}"
    seg="${seg//\}/}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    head="${seg%%[[:space:]]*}"
    head="${head##*\\}"
    [[ "$seg" == '>'* ]] && return 0
    case "$head" in
    echo | write | write-output | write-host | write-error | write-warning | \
      write-verbose | write-debug | write-information | \
      "${PS_HERESTRING_PLACEHOLDER,,}") return 0 ;;
    '$'*) return 0 ;;
    '['*) return 0 ;;
    *) ;;
    esac
    [[ "$head" =~ ^[0-9]+([.][0-9]+)?$ ]] && return 0
  done
  return 1
}
