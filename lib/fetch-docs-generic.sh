# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2153  # fetch-docs.sh sources this file; it sets these globals and reads the G_ results
generic_slug() {
  local LC_ALL=C s
  url_parts "$1" || return 1
  s="${U_ORIGIN#https://}$U_PATH"
  s="${s%/}"
  s="${s%.md}"
  dc_lower s "$s"
  s="${s//[^a-z0-9_\/-]/-}"
  printf '%s' "$s"
}

resolve_python() {
  local c v
  if [[ -n "${PY_STATE:-}" ]]; then
    [[ "$PY_STATE" == ok ]]
    return
  fi
  PY_STATE=none
  for c in python3 python; do
    command -v "$c" >/dev/null 2>&1 || continue
    v="$(with_timeout 30 "$c" -I -c 'import sys; print(sys.version_info[0])' 2>/dev/null </dev/null)"
    [[ "${v%$'\r'}" == 3 ]] || continue
    PY="$c" PY_STATE=ok
    return 0
  done
  return 1
}

html_title() {
  LC_ALL=C awk '
    { buf = buf " " $0 }
    END {
      low = tolower(buf)
      s = index(low, "<title")
      if (!s) exit
      rest = substr(buf, s); g = index(rest, ">")
      if (!g) exit
      rest = substr(rest, g + 1); e = index(tolower(rest), "</title")
      if (!e) exit
      t = substr(rest, 1, e - 1); gsub(/[ \t\r\n]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
      print t
    }' "$1"
}

bundle_link() {
  local origin="$1" path="$2" idx="$WORK/bundle-${#BUNDLES_K[@]}.txt" u p v
  B_LINK=""
  if ! map_get BUNDLES "$origin" v; then
    v=none
    http_get "$origin/llms.txt" "$idx" "" "" ""
    if [[ $H_RC -eq 0 && "$H_STATUS" =~ ^2[0-9][0-9]$ && "$H_CTYPE_LC" =~ $MD_OR_TEXT_CTYPE && -s "$idx" &&
      "$(landed "$origin/llms.txt" "$H_EFF")" == same ]]; then
      v="$idx"
    fi
    map_put BUNDLES "$origin" "$v"
  fi
  [[ "$v" != none ]] || return 0
  idx="$v"
  while IFS= read -r u; do
    [[ "$u" != /* || "$u" == //* ]] || u="$origin$u"
    url_parts "$u" && [[ "$U_ORIGIN" == "$origin" ]] || continue
    p="${U_PATH%.md}"
    p="${p%.txt}"
    p="${p%/index}"
    if [[ "$p" == "$path" && "$u" != "$3" ]]; then
      B_LINK="$u"
      return 0
    fi
  done < <(link_urls "$idx")
}

markdown_channel() {
  request "$1" "$2" "$3.part" "$3" && return 0
  if [[ $H_RC -eq 0 && "$(landed "$2" "$H_EFF")" == same && "$H_STATUS" =~ ^2[0-9][0-9]$ &&
  "$H_CTYPE_LC" =~ $4 && -s "$3.part" ]] && mv "$3.part" "$3"; then
    G_STATE=read G_FORMAT=markdown G_STATUS="$H_STATUS" G_CTYPE="$H_CTYPE" G_DATE="$H_DATE"
    G_VALIDATORS="$(dc_validators_or_none "$1" "$2")"
    return 0
  fi
  rm -f "$3.part"
  return 1
}

convert() {
  if ! resolve_python; then
    G_REASON="no-python"
  elif [[ ! -f "$CONVERTER" ]]; then
    G_REASON="converter-missing"
  elif with_timeout 120 env PYTHONUTF8=1 "$PY" "$CONVERTER" "$1" >"$2.part" 2>/dev/null </dev/null && [[ -s "$2.part" ]] &&
    mv "$2.part" "$2"; then
    return 0
  else
    G_REASON="convert-failed"
  fi
  rm -f "$2.part"
  return 1
}

check_expect() {
  [[ -z "$EXPECT" || "$G_STATE" != read ]] && return 0
  if ! grep -qF -- "$EXPECT" "$1"; then
    rm -f "$1"
    G_STATE=unread G_REASON=no-content G_FORMAT="" G_VALIDATORS="" G_TITLE_HINT=""
    G_STALE="" G_KEY="" G_VALIDATED="" G_AGE="" G_TITLE="" G_QUAR=""
    return 1
  fi
  return 0
}

render_fallback() {
  local url="$1" dest="$2" rdir meta r_url r_status r_title has_md rc=0
  [[ $RENDER_FALLBACK -eq 1 && "$DC_CFG_renderer" == firecrawl && $FIXTURE_SET -eq 0 ]] || return 1
  case "$G_REASON" in
  fetch-failed | http-403 | http-429 | unexpected-content-type | no-content) ;;
  *) return 1 ;;
  esac
  if [[ $PUBLIC_ONLY -eq 1 ]]; then
    url_parts "$url" || return 1
    [[ "${U_ORIGIN#https://}" =~ ^([^:]+)(:[0-9]+)?$ ]]
    pin "${BASH_REMATCH[1]:-}" || {
      H_RC=$?
      G_REASON="$(failure_reason)"
      return 1
    }
  fi
  command -v firecrawl >/dev/null 2>&1 || return 1
  RENDER_SEQ=$((RENDER_SEQ + 1))
  rdir="$WORK/render-$RENDER_SEQ"
  mkdir "$rdir" || return 1
  (
    cd "$rdir" || exit 1
    with_timeout 120 firecrawl scrape "$url" --format markdown --json -o out.json </dev/null >/dev/null 2>&1
  ) || rc=$?
  if [[ $rc -ne 0 || ! -s "$rdir/out.json" ]]; then
    rm -rf "$rdir"
    return 1
  fi
  # shellcheck disable=SC2016 # jq expression, not shell
  meta="$(jq -r '
    if type != "object" or (has("success") and .success == false) then empty
    else (if (.data | type) == "object" then .data else . end)
    | (.metadata | if type == "object" then . else {} end) as $m
    | [
        (([$m.url] | map(select(type == "string" and length > 0)) | .[0]) // "" | if (test("[[:cntrl:]]") | not) then . else "" end),
        ($m.statusCode // "" | tostring | if test("^[0-9]+$") then . else "" end),
        ($m.title // "" | if type == "string" then gsub("[\u001f\r\n]"; " ") else "" end),
        (if (.markdown | type) == "string" and (.markdown | length) > 0 then "1" else "0" end)
      ] | join("\u001f")
    end' "$rdir/out.json" 2>/dev/null)"
  meta="${meta%$'\r'}"
  if [[ -z "$meta" ]]; then
    rm -rf "$rdir"
    return 1
  fi
  IFS=$'\x1f' read -r r_url r_status r_title has_md <<<"$meta"
  if [[ -z "$r_url" ]]; then
    rm -rf "$rdir"
    return 1
  fi
  case "$(landed "$url" "$r_url")" in
  off-origin)
    rm -rf "$rdir"
    G_STATUS="$r_status" G_REASON="redirected-off-origin"
    return 1
    ;;
  off-path)
    rm -rf "$rdir"
    G_STATUS="$r_status" G_REASON="redirected-off-path"
    return 1
    ;;
  same) ;;
  *)
    rm -rf "$rdir"
    return 1
    ;;
  esac
  if [[ "$r_status" == 404 || "$r_status" == 410 ]]; then
    rm -rf "$rdir"
    G_STATUS="$r_status" G_REASON="http-$r_status"
    return 1
  fi
  if [[ -n "$r_status" && ! "$r_status" =~ ^2[0-9][0-9]$ ]]; then
    rm -rf "$rdir"
    return 1
  fi
  if [[ "$has_md" != 1 ]] || ! jq -j '
    (if (.data | type) == "object" then .data else . end) | .markdown
    ' "$rdir/out.json" 2>/dev/null | tr -d '\r' >"$dest.part"; then
    rm -rf "$rdir" "$dest.part"
    return 1
  fi
  rm -rf "$rdir"
  if [[ ! -s "$dest.part" ]]; then
    rm -f "$dest.part"
    return 1
  fi
  if [[ $(wc -c <"$dest.part") -gt $MAX_PAGE ]]; then
    rm -f "$dest.part"
    G_REASON="too-large"
    return 1
  fi
  if [[ -n "$EXPECT" ]] && ! grep -qF -- "$EXPECT" "$dest.part"; then
    rm -f "$dest.part"
    return 1
  fi
  if ! mv "$dest.part" "$dest"; then
    rm -f "$dest.part"
    return 1
  fi
  G_STATE=read G_SOURCE=fetch G_REASON="" G_FORMAT=rendered G_CTYPE="text/markdown"
  G_STATUS="$r_status" G_VALIDATORS="" G_DATE="" G_TITLE_HINT="$r_title"
  G_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  return 0
}

generic_read() {
  local url="$1" dest="$2" html="$WORK/page.html" html_status="" html_ctype="" html_val="" html_date="" sfx=""
  local fmts=(markdown html-converted)
  [[ $RENDER_FALLBACK -eq 0 ]] || fmts+=(rendered)
  reset_g
  rm -f "$dest" "$dest.part" "$html"
  mkdir -p "$(dirname "$dest")"
  cache_candidate "$url" "${fmts[@]}"
  if serve_fresh "$dest"; then
    if check_expect "$dest"; then return 0; fi
    C_REF=""
    reset_g
  fi
  if [[ $FIXTURE_SET -eq 1 ]]; then
    fixture_read "$dest" "$3" markdown
    check_expect "$dest" || true
    return 0
  fi
  G_SOURCE=fetch
  if [[ $CURL_MISSING -eq 1 ]]; then
    G_REASON="curl-missing"
    return 0
  fi
  G_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  url_parts "$url"
  local origin="$U_ORIGIN" path="$U_PATH"

  if request text/markdown "$url" "$dest.part" "$dest"; then
    check_expect "$dest" && return 0
    render_fallback "$url" "$dest"
    [[ "$G_STATE" == read ]] || settle_unread "$url" "$dest" markdown html-converted rendered
    return 0
  fi
  G_STATUS="$H_STATUS" G_CTYPE="$H_CTYPE"
  if [[ $H_RC -ne 0 ]]; then
    G_REASON="$(failure_reason)"
  else
    case "$(landed "$url" "$H_EFF")" in
    off-origin) G_REASON="redirected-off-origin" ;;
    off-path) G_REASON="redirected-off-path" ;;
    *) ;;
    esac
  fi
  if [[ -n "$G_REASON" ]]; then
    rm -f "$dest.part"
    [[ "$G_REASON" != fetch-failed ]] || render_fallback "$url" "$dest"
    if [[ "$G_STATE" != read ]]; then
      settle_unread "$url" "$dest" markdown html-converted rendered
      return 0
    fi
    G_REASON=""
    return 0
  fi
  local own_md_re="$MD_CTYPE"
  [[ "$path" != *.md ]] || own_md_re="$MD_OR_TEXT_CTYPE"
  if [[ "$H_STATUS" =~ ^2[0-9][0-9]$ && "$H_CTYPE_LC" =~ $own_md_re && -s "$dest.part" ]] && mv "$dest.part" "$dest"; then
    G_STATE=read G_FORMAT=markdown G_VALIDATORS="$(dc_validators_or_none text/markdown "$url")" G_DATE="$H_DATE"
  elif [[ "$H_STATUS" =~ ^2[0-9][0-9]$ && "$H_CTYPE_LC" =~ $HTML_CTYPE && -s "$dest.part" ]]; then
    mv "$dest.part" "$html"
    html_status="$H_STATUS" html_ctype="$H_CTYPE" html_val="$(dc_validators_or_none text/markdown "$url")" html_date="$H_DATE"
  else
    G_REASON="http-${H_STATUS:-unknown}"
    [[ ! "$H_STATUS" =~ ^2[0-9][0-9]$ ]] || G_REASON="unexpected-content-type"
  fi
  rm -f "$dest.part"

  if [[ "$G_STATE" != read && "$path" != *.md ]]; then
    sfx="$origin$path.md"
    [[ "$path" != / ]] || sfx="$origin/index.md"
    if markdown_channel "" "$sfx" "$dest" "$MD_OR_TEXT_CTYPE" && [[ "$G_SOURCE" == cache ]]; then
      check_expect "$dest" && return 0
    fi
  fi
  if [[ "$G_STATE" != read ]]; then
    bundle_link "$origin" "$path" "${sfx:-}"
    if [[ -n "$B_LINK" ]]; then
      if markdown_channel "" "$B_LINK" "$dest" "$MD_OR_TEXT_CTYPE" && [[ "$G_SOURCE" == cache ]]; then
        check_expect "$dest" && return 0
      fi
    fi
  fi
  if [[ "$G_STATE" != read && -z "$html_status" ]]; then
    if request "" "$url" "$html" "$dest"; then
      check_expect "$dest" && return 0
    fi
    [[ $H_RC -ne 63 ]] || G_REASON="too-large"
    if [[ $H_RC -eq 0 && "$(landed "$url" "$H_EFF")" == same && "$H_STATUS" =~ ^2[0-9][0-9]$ &&
    "$H_CTYPE_LC" =~ $HTML_CTYPE && -s "$html" ]]; then
      html_status="$H_STATUS" html_ctype="$H_CTYPE" html_val="$(dc_validators_or_none "" "$url")" html_date="$H_DATE"
    fi
  fi
  if [[ "$G_STATE" != read && -n "$html_status" ]]; then
    G_STATUS="$html_status" G_CTYPE="$html_ctype"
    if convert "$html" "$dest"; then
      G_STATE=read G_REASON="" G_FORMAT=html-converted G_VALIDATORS="$html_val" G_DATE="$html_date"
      G_TITLE_HINT="$(html_title "$html")"
    fi
  fi
  rm -f "$html"
  check_expect "$dest" || true
  if [[ "$G_STATE" != read ]]; then
    render_fallback "$url" "$dest"
  fi
  if [[ "$G_STATE" != read ]]; then
    settle_unread "$url" "$dest" markdown html-converted rendered
    return 0
  fi
  G_REASON=""
}

login_wall() {
  local LC_ALL=C words
  url_parts "$1" && [[ "$U_ORIGIN" =~ ^https://((www|mobile)\.)?(x|twitter)\.com(:443)?$ ]] || return 1
  grep -qF redirect_after_login "$2" || return 1
  words="$(awk '{ gsub(/\[[^]]*\]\([^)]*\)/, ""); n += NF } END { print n + 0 }' "$2")"
  [[ $words -lt 200 ]]
}

get_generic() {
  generic_read "$@"
  check_expect "$2" || return 0
  [[ "$G_STATE" == read ]] || return 0
  if login_wall "$1" "$2"; then
    rm -f "$2"
    G_STATE=unread G_REASON=login-wall G_STALE="" G_KEY="" G_VALIDATED="" G_AGE=""
    return 0
  fi
  [[ "$G_SOURCE" == cache ]] || store "$1" "$2"
}
