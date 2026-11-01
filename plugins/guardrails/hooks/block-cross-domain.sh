#!/usr/bin/env bash
# PreToolUse hook: deny a Bash or PowerShell call, from a session in one of
# this machine's identity domains, that names a path of another, and, from any
# session, one that writes the machine's git identity.
#
# An identity domain is a set of trees one identity owns, with its own git
# author, gh and az config directories and remote owners. THE MAP names each
# domain's roots, owners and markers; this guard classifies the session cwd
# into a domain or neutral, finds the domains a command names, and denies the
# call when the cwd is in a domain and the command names another domain's path.
#
# THE MAP. ${CLAUDE_PLUGIN_DATA}/identity-domains.json, machine-local and never
# tracked. Its keys follow docs/contracts/plugin-option-naming:
#
#   {
#     "domains": {
#       "<name>": {
#         "roots": { "linux": ["<abs>"], "macos": ["<abs>"], "windows": ["<abs>"] },
#         "owners": ["<owner>"],
#         "identity_markers": ["<text>"],
#         "gh_config_dir": "<dir>",
#         "az_config_dir": "<dir>"
#       }
#     },
#     "identity_files": ["<path>"],
#     "shared_exceptions": [{ "path": "<abs>", "from": ["<name>"], "to": "<name>" }],
#     "messages": { "<key>": "<text>" }
#   }
#
# `domains` and each domain's `roots` are required; every other key may be left
# out. A domain name is letters, digits, `.`, `_` and `-`; every value is a
# non-empty one-line string; a root is absolute and below a filesystem root
# (`/x`, and on Windows also `C:/x`, `C:\x` or `/c/x`). A shared exception
# needs all three keys, a `to` and a non-empty `from` that name domains of the
# map, and no `to` among its `from`. An unknown key or any other shape makes the
# map malformed. Only this host's roots (OSTYPE: msys, cygwin and win32 read
# `windows`, darwin `macos`, every other host `linux`), the owners, the markers,
# the gh and az config directories, the identity files and the shared
# exceptions are used here; `messages` is validated and kept for the rules that
# read it.
#
# SHARED EXCEPTIONS. One exception opens one directory of its `to` domain to
# sessions in its `from` domains, one way. From a cwd in a `from` domain, a
# command that names the path, or a path below it, is not denied for it, as long
# as the command text, quotes and `\` dropped, holds no `..`. Every other foreign
# path the command names still denies it, and the exception opens nothing to a
# session in `to` or in a domain `from` does not list. Any character right
# after the path but the text's end, `/`, whitespace or a word-ending operator
# (`;&|<>()`) closes it for that mention: a glob, brace or expansion
# (`shared*`, `shared{,-x}`, `shared$x`) can reach a sibling, and any other
# character (`shared+x`, `shared~x`) names one. The path counts only when
# it is a path of `to` on this host: the longest root or owner directory of any
# domain that holds it, or equals it, is `to`'s, compared with runs of `\` and
# `/` as one `/` and a drive spelled `C:`, `/cygdrive/c` or `/mnt/c` (and on
# Windows `/c`) as one drive, in any case on Windows. An exception whose path is
# not one, or an entry that is a plain string (the earlier shape), grants
# nothing; it leaves the map well formed, and the user is told which entry once
# per session.
#
# WHAT A CALL COSTS. Each step leaves at the first that settles the call:
#   1. the kill switch, before any source;
#   2. no map file: no domain and no step 3 or 4, so only the GIT IDENTITY
#      WRITES rule below can deny, and a call its prefilter misses leaves at
#      step 5, or before the jq gate when its raw input already misses, with
#      no trace and no telemetry;
#   3. the map, compiled by jq into CACHE (identity-domains.cache beside it)
#      once per change of its bytes or of HOME and read back with builtins
#      otherwise, so a steady call starts no process; a malformed map is
#      reported to the user once per session and the call is allowed unchecked;
#   4. the cwd, classified into the domain whose path holds it (the longest
#      path wins), else neutral;
#   5. the prefilter: the command text, lowercased with `\` read as `/` and
#      its quotes dropped, is tested for each path and marker, and, from a cwd
#      in a domain of a map with a gh or az config directory, for the word `gh`
#      or `az`, and, from a cwd in a domain with a gh config directory, for
#      the word `gh` or the text `gh_token`, and, from every cwd, for both
#      `git` and `config` or the last
#      name of an identity file the map lists. A command that names none
#      leaves here, before it is parsed;
#   6. the parse: on the Bash tool hook::bash_parse_segments, whose argv words
#      and redirection targets are tested the same way; on PowerShell the text
#      as a whole, parsed only for the identity positions and identity writes
#      below;
#   7. the decision: from a cwd in a domain, a path of another domain named in
#      step 6 denies the call, a read as much as a write, as does a gh or az
#      call that breaks the CONFIG DIRECTORIES rule below, and an account
#      switch or GH_TOKEN removal the AUTH SWITCHES rule names. A marker never
#      denies here. From every cwd, neutral included, an identity write denies
#      the call; from a neutral cwd nothing else is denied.
#
# A domain's PATHS are its roots and, for each owner, the owner's directory
# below $HOME/src/github.com and $HOME/worktrees/github.com. A text NAMES a
# path or marker when it holds it with no letter, digit, `.`, `_` or `-` right
# before or after it: the root /x/work names neither /x/workshop nor
# /y/x/work. `\` reads as `/` and a run of separators as one, so `C:\x`,
# `C:\\x` and `C:/x` are one spelling. A path on a drive is also named in its
# other drive forms (`C:/x`, `/c/x`, `/cygdrive/c/x`, `/mnt/c/x`, where a
# Windows root `/c/x` and a `/cygdrive/c` or `/mnt/c` root on any host are on
# drive C) and, below $HOME, after `~`, `$HOME`, `${HOME}`, `$env:HOME`,
# `$env:USERPROFILE` or `%USERPROFILE%`. A path below two nested paths names
# the domain of the inner one only; every other path and every marker a text
# names counts. Text is compared in any case, so on Linux a path that differs
# from a root only in case names it too.
#
# IDENTITY POSITIONS. From a cwd in a domain, a command whose prefilter named
# another domain's marker is denied when a word in an identity position names
# a marker of a domain other than the cwd's that the cwd's own domain does not
# also list. The positions:
#   - every word after `git remote add` or `git remote set-url` (not
#     `set-url --delete`)
#   - the value `git config` (old form or `set`, not a read or an unset) or
#     `git -c` gives user.email,
#     user.name, author.email, author.name, committer.email, committer.name,
#     remote.<name>.url or remote.<name>.pushurl
#   - `git commit --author <v>` and `--author=<v>`
#   - the value of an assignment to GH_CONFIG_DIR, AZURE_CONFIG_DIR,
#     GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME or
#     GIT_COMMITTER_EMAIL: a leading `NAME=value` (after a compound keyword or
#     `{` too), one after `export` or `env`, and PowerShell's `$env:NAME = value`
#     in any case
# PowerShell text goes through the same parse with each `\` read as `/`. The
# same marker in any other word (a commit message, an `echo`) is allowed. The
# deny is a PreToolUse permissionDecision document on stdout.
#
# CONFIG DIRECTORIES. From a cwd in a domain, a `gh` call runs with the
# GH_CONFIG_DIR the command text gives it, else the one in the hook's own
# environment, and an `az` call likewise with AZURE_CONFIG_DIR. When the cwd's
# domain has a `gh_config_dir`, a gh call that does not run with it is denied;
# when it has none, a gh call that runs with another domain's is denied. The
# same holds for az and `az_config_dir`. `gh --version` and `az --version` are
# exempt. The text gives a value by a `NAME=value` before the command or after
# `env`, which holds for that command only, and by `export NAME=value`,
# `unset NAME` or PowerShell's `$env:NAME = value`, which hold for every later
# command; a bare `NAME=value` holds for later commands only when NAME is
# already exported. `env -u NAME` and `env -i` remove it. Directories compare
# in the prefilter's form, with `~`, `$HOME` and the other HOME spellings read
# as HOME and, on Windows, a `/c/`, `/cygdrive/c/` or `/mnt/c/` prefix read as
# `c:/`.
#
# AUTH SWITCHES. From a cwd in a domain that has a `gh_config_dir`, a call is
# denied that switches gh's account or removes GH_TOKEN, whatever GH_CONFIG_DIR
# it runs with: `gh auth switch`, `gh auth login` and `gh auth logout` (behind
# the same wrappers CONFIG DIRECTORIES reads); `unset GH_TOKEN`, `export -n
# GH_TOKEN`, and `env -u GH_TOKEN` in each spelling (`-uGH_TOKEN`, `--unset
# GH_TOKEN`, `--unset=GH_TOKEN`); an assignment that empties it (`GH_TOKEN=`
# before a command, alone, after `export` or `env`, and PowerShell's
# `$env:GH_TOKEN = ''` or `= $null`); and, on PowerShell, `Remove-Item
# Env:GH_TOKEN` and its aliases. A plain gh call, `gh auth status` and `gh auth
# token` included, is left to CONFIG DIRECTORIES. From a domain with no
# `gh_config_dir`, or a neutral cwd, the rule denies nothing.
#
# GIT IDENTITY WRITES. From every cwd, in a domain or neutral, and on a host
# with no map, a call is denied that writes the machine's git identity:
#   - `git config` with `--global`, `--system` or `--file <identity file>`
#     (`-f`, `--file=`) that sets, adds, replaces or unsets user.email,
#     user.signingkey, user.useConfigOnly, credential.helper (and its
#     credential.<url>.helper form), core.sshCommand, core.hooksPath or an
#     includeIf key, in the old form or after `set` or `unset`; one that
#     renames or removes the user, core, credential or an includeIf section;
#     and `--edit` or `edit`, which may touch every key;
#   - a shell write to an identity file: an output redirection to it (the
#     targets of `&>`, `&>>` and `>|`, which the parse splits at the `&` or
#     `|`, are read from the folded text); an operand of tee, touch, truncate,
#     rm, unlink, shred, mv or a PowerShell writer (Set-Content, Add-Content,
#     Out-File, Clear-Content, Remove-Item, New-Item, Move-Item, Rename-Item,
#     Tee-Object and their aliases); the destination of cp, install, ln,
#     rsync, scp (not a `host:path` one) or Copy-Item; a file sed or perl
#     edits in place; dd's `of=`.
# An IDENTITY FILE is a `<name>.gitconfig` file anywhere, one directly in HOME
# whose name starts with `.gitconfig`, and each of the map's
# identity_files with every path below it, compared as CONFIG DIRECTORIES
# compares a directory. Reads pass: `--get` and the other `--get-*` forms,
# `-l`/`--list`, `config get`, `config list`, the old form with a key and no
# value, and a command that only reads an identity file (`cat`, a cp source).
#
# Steps 4, 6 and 7 feed the telemetry envelope: `cwd` is domain or neutral,
# `form` is prefilter-miss, not-named, own-domain (the cwd's domain alone is
# named), other-domain, identity-deny, config-deny, auth-deny,
# identity-write-deny, or map-malformed (whose cwd is always neutral), and
# `status` is blocked for a denied call, else ok. The envelope
# names no domain; `subject` is the command word, as in every guard's. The
# path deny reason, on the model's channel, names the cwd's domain and the
# others.
#
# DECLARED GAPS. The guard reads command text: a deterrent, not a sandbox.
#   - a computed path: a variable, a substitution, or a path spelled in pieces
#     the prefilter cannot join (`/x/wo\rk`); quoted pieces (`"/x/wo"rk`) are
#     joined
#   - a script run by name, whose own commands the guard never sees, and a
#     heredoc body, which the parse skips even when a shell runs it
#     (`bash <<'EOF'`)
#   - a path relative to the cwd (`../other`), and a symlink into a root
#   - on macOS, a cwd spelled in another case than its root, which reads as
#     neutral
#   - an identity position inside a `bash -c` or `sh -c` operand, a git alias,
#     or a variable set some other way (`declare -x`, `Set-Item env:`)
#   - a gh or az call inside a `bash -c` operand, or behind a wrapper other
#     than `env`, `command`, `exec`, `nohup` and `time` or after a wrapper
#     option that takes a value (`exec -a <name>`, `env -S`)
#   - an export inside a subshell or a pipeline, which counts for later
#     commands, and `export NAME` with no value after a bare `NAME=value`,
#     which does not
#   - a GH_TOKEN removal by `env -i`, `declare` and its kin, `builtin unset`,
#     a value that only expands to empty (`GH_TOKEN=$unset`), a name spelled
#     with an escape (`GH\_TOKEN`), PowerShell's `Clear-Item`, a glob, list or
#     pipeline into `Remove-Item`, or a .NET call; and an account switch
#     through a gh alias
#   - an identity write inside a `bash -c` or `sh -c` operand, through a git
#     alias (`git -c alias.c=config c --global ...`), after a wrapper option
#     that takes a value (`sudo -u <user> tee`), by a redirection with no
#     command word (`> ~/.gitconfig` alone), by a copy into a directory that
#     leaves the file's name out, across a PowerShell backtick line
#     continuation, or to git's XDG global file (`~/.config/git/config`),
#     which is no identity file here; and, the other way, an `&>` or `>|`
#     with an identity file after it inside quoted text, which denies
#   - a shared exception's `..` test reads the whole text, so a `..` anywhere
#     (`git log a..b`) closes the exception for that command; and a path computed
#     from inside the exception (`cd <exception> && ls "${PWD%/*}/x"`) is the
#     computed-path gap above
#   - a map that is malformed, or a missing jq, which turns the whole guard
#     off, the identity-write rule included
#
# TEST HOOK. GUARDRAILS_CROSS_DOMAIN_TRACE=1 writes one stderr line per step a
# call reaches (`block-cross-domain: trace <step>`).
#
# Kill switch: block_cross_domain_enabled userConfig option.
#
# Every exit is 0, an internal error included: a deny is the decision in the
# stdout document, and an internal error allows the call.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off (scripts/check-killswitch-hoist.sh).
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CROSS_DOMAIN_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a "guard did not run" notice. 0 is the
# only chosen status: this guard never blocks by exit code.
guard::abort_boundary block-cross-domain PreToolUse open 0

# Empty when there is no map: then no domain, and only the identity-write rule.
BCD_MAP=""
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" && -f "${CLAUDE_PLUGIN_DATA%/}/identity-domains.json" ]]; then
  BCD_MAP="${CLAUDE_PLUGIN_DATA%/}/identity-domains.json"
fi

# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

# Every stdin failure (empty, stalled, not JSON, cut short) allows the call.
hook::buffer_stdin_to INPUT || exit 0

# With no map only the identity-write rule can deny, and only a command whose
# text holds both `git` and `config` reaches it (bcd::write_prefilter). That test
# runs here first, on the raw input, so a call the rule would never read leaves
# before the jq gate and a missing jq is not reported for it. Lowercased, with
# its escaped backslashes, escaped CRs, `\`, `"` and `'` dropped, the raw input
# holds every letter run the command text does; a `\u` escape can spell a
# letter, so an input with one goes on to the gate.
if [[ -z "$BCD_MAP" ]]; then
  BCD_RAW=${INPUT//\\\\/}
  if [[ "$BCD_RAW" != *\\u* ]]; then
    BCD_RAW=${BCD_RAW,,}
    BCD_RAW=${BCD_RAW//\\r/}
    BCD_RAW=${BCD_RAW//[$'\r'\\\"\']/}
    [[ "$BCD_RAW" == *git* && "$BCD_RAW" == *config* ]] || exit 0
  fi
fi

# The map is compiled by jq, and the call's fields are read through it. Without
# it: one notice per session, then allow.
hook::require jq PreToolUse guardrails "$INPUT"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || jq_rc=$?
((jq_rc == 0 && HOOK_JQ_FIELDS_NUL == 0)) || exit 0
COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
BCD_CWD_RAW="${HOOK_JQ_FIELDS[2]}"

case "${OSTYPE:-}" in
msys* | cygwin* | win32) BCD_OS=windows ;;
darwin*) BCD_OS=macos ;;
*) BCD_OS=linux ;;
esac

# What the compiler below writes. A change to the jq program or to how the
# records are read changes it, so a cache an older guard wrote is compiled again.
BCD_FORMAT=5
BCD_CACHE="${BCD_MAP%.json}.cache"
BCD_TAB=$'\t'
BCD_CWD_DOMAIN=""
BCD_HOME=""
BCD_HOME_FOLD=""
BCD_RECORDS=()
BCD_ROOT=()
BCD_ROOT_DOMAIN=()
BCD_NEEDLE=()
BCD_NEEDLE_DOMAIN=()
BCD_NEEDLE_PATH=()
BCD_NEEDLE_FROM=()
BCD_DOTDOT=0
BCD_GRANTS_NOTHING=()
BCD_NOTICE=""
BCD_NOTICE_JSON=""
BCD_NAMED=" "
BCD_DENY=()
BCD_SUBJECT=""
BCD_FOREIGN_MARKER=0
BCD_IDENTITY=0
BCD_OWN_MARKERS=$'\n'
BCD_IDENTITY_DENY=()
BCD_PATHS=0
BCD_CONFIG=0
BCD_CONF_KIND=()
BCD_CONF_DOMAIN=()
BCD_CONF_DIR=()
BCD_CONF_RAW=()
BCD_CONFIG_DENY=()
BCD_AUTH=0
BCD_AUTH_DENY=()
# What the command text set GH_CONFIG_DIR and AZURE_CONFIG_DIR to for later
# commands: _SET is 1 for set, 0 for removed, empty for untouched.
BCD_GH_SET=""
BCD_GH=""
BCD_AZ_SET=""
BCD_AZ=""
BCD_WRITES=0
BCD_IDFILES=()
BCD_IDFILE_NAMES=()
BCD_WRITE_DENY=()

# The compiler: the map's raw text and HOME in, one line per record out:
# `marker`, `gh` and `az` records, one `idfile` record per identity file with
# an empty domain, a `legacy` or `outside` record for each shared exception that
# grants nothing (its index as the value), then this host's `root` records, each
# owner's two `owner` directories below HOME and each `shared` record (its
# domain `<to><TAB><from domains, space-separated>`), longest first
# (`<kind><TAB><domain><TAB><value>`), or one `invalid<TAB><reason>` line for a
# map it rejects. The whole map is validated before any record is written, so a
# rejected map yields no partial set. The reason names keys, never values.
# shellcheck disable=SC2016  # a jq program: its $names are jq variables
BCD_COMPILE='
def fail($m): error({bcd: $m});
def oneline: explode | map(if . < 32 or . == 127 then 63 else . end) | implode;
def line($what):
  if type == "string" and length > 0 and (explode | all(. >= 32 and . != 127)) then .
  else fail("\($what) is not a non-empty one-line string") end;
def list($what):
  if type != "array" then fail("\($what) is not an array")
  else range(length) as $i | .[$i] | line("\($what)[\($i)]") end;
def object($what): if type == "object" then . else fail("\($what) is not an object") end;
def only($what; $allowed):
  object($what)
  | if (keys - $allowed) != [] then fail("\($what) has an unknown key, \((keys - $allowed)[0])") else . end;
def optional($key; f): if has($key) then .[$key] | f else empty end;
def absolute($os):
  if $os == "windows"
  then test("^[A-Za-z]:[\\\\/]+[^\\\\/]") or (test("^/[^/]") and (test("^/[A-Za-z][\\\\/]*$") | not))
  else test("^/[^/]") end;
def domain($d; $os; $home):
  if ($d | test("\\A[A-Za-z0-9_.-]+\\z")) | not
  then fail("a domain name holds a character other than a letter, digit, dot, underscore or hyphen")
  else . end
  | only("domains.\($d)"; ["roots", "owners", "identity_markers", "gh_config_dir", "az_config_dir"])
  | if has("roots") | not then fail("domains.\($d) has no roots") else . end
  | [optional("owners"; list("domains.\($d).owners"))] as $owners
  | [optional("gh_config_dir"; line("domains.\($d).gh_config_dir"))] as $gh
  | [optional("az_config_dir"; line("domains.\($d).az_config_dir"))] as $az
  | [optional("identity_markers"; list("domains.\($d).identity_markers"))] as $markers
  | [.roots | only("domains.\($d).roots"; ["linux", "macos", "windows"])
      | to_entries[] | .key as $o | .value
      | list("domains.\($d).roots.\($o)")
      | if absolute($o) then select($o == $os)
        else fail("domains.\($d).roots.\($o) holds a path that is not absolute below a filesystem root") end] as $roots
  | ($roots[] | {kind: "root", d: $d, v: .}), ($markers[] | {kind: "marker", d: $d, v: .}),
    ($gh[] | {kind: "gh", d: $d, v: .}), ($az[] | {kind: "az", d: $d, v: .}),
    (if $home == "" then empty
     else $owners[] | {kind: "owner", d: $d, v: "\($home)/src/github.com/\(.)"},
       {kind: "owner", d: $d, v: "\($home)/worktrees/github.com/\(.)"} end);
def fold($os):
  gsub("[\\\\/]+"; "/") | sub("(?<=.)/$"; "")
  | if $os == "windows" then ascii_downcase | sub("^/(cygdrive/|mnt/)?(?<d>[a-z])(?=/|$)"; "\(.d):")
    else sub("^/(cygdrive|mnt)/(?<d>[A-Za-z])(?=/|$)"; "\(.d | ascii_downcase):")
      | sub("^(?<d>[A-Z]):"; "\(.d | ascii_downcase):") end;
def shared($names; $paths; $os):
  if type != "array" then fail("shared_exceptions is not an array") else . end
  | range(length) as $i | .[$i] | "shared_exceptions[\($i)]" as $w
  | if type == "string" then line($w) | {kind: "legacy", d: "", v: "\($i)"}
    else only($w; ["path", "from", "to"])
    | if (has("path") and has("from") and has("to")) | not then fail("\($w) needs path, from and to") else . end
    | (.path | line("\($w).path")) as $p
    | (.to | line("\($w).to")) as $to
    | [.from | list("\($w).from")] as $from
    | if any($names[]; . == $to) | not then fail("\($w).to names no domain of the map")
      elif $from == [] then fail("\($w).from is empty")
      elif any($from[]; . as $f | any($names[]; . == $f) | not) then fail("\($w).from names no domain of the map")
      elif any($from[]; . == $to) then fail("\($w).from holds its to")
      elif ($p | fold($os)) as $q
        | [$paths[] | (.v | fold($os)) as $r | select($q == $r or ($q | startswith($r + "/"))) | {d, n: ($r | length)}]
        | max_by(.n) | .d == $to
      then {kind: "shared", d: "\($to)\t\($from | join(" "))", v: $p}
      else {kind: "outside", d: $to, v: "\($i)"} end
    end;
def compile($os; $home):
  only("the map"; ["domains", "identity_files", "shared_exceptions", "messages"])
  | if has("domains") | not then fail("the map has no domains") else . end
  | [optional("identity_files"; list("identity_files"))] as $files
  | [optional("messages"; object("messages") | to_entries[] | .key as $k | .value | line("messages.\($k)"))] as $messages
  | (.domains | object("domains") | [to_entries[] | .key as $d | .value | domain($d; $os; $home)]) as $records
  | ($records | map(select(.kind == "root" or .kind == "owner"))) as $paths
  | (.domains | keys) as $names
  | [optional("shared_exceptions"; shared($names; $paths; $os))] as $shared
  | $records
  | map(select(.kind != "root" and .kind != "owner"))
    + [$files[] | {kind: "idfile", d: "", v: .}]
    + ($shared | map(select(.kind != "shared")))
    # A shared path sorts after a root of its length, so the reverse puts its
    # needles first and it spends its text before that root reads it.
    + ($paths + ($shared | map(select(.kind == "shared")))
      | sort_by(.v | gsub("[\\\\/]+"; "/") | sub("/$"; "") | sub("^/(cygdrive|mnt)/"; "/") | length) | reverse)
  | map("\(.kind)\t\(.d)\t\(.v)");
(try [fromjson] catch null) as $doc
| if $doc == null then ["invalid\tit is not valid JSON"]
  else try ($doc[0] | compile($os; $home))
    catch (if type == "object" and has("bcd") then ["invalid\t" + (.bcd | oneline | .[0:300])]
      else ["invalid\tit cannot be read"] end)
  end
| .[]
'

bcd::trace() {
  [[ "${GUARDRAILS_CROSS_DOMAIN_TRACE:-}" == 1 ]] || return 0
  printf 'block-cross-domain: trace %s\n' "$1" >&2
}

bcd::emit_tel() { # <form> [<status>, default ok]
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local subject data cwd=neutral
  [[ -n "$BCD_CWD_DOMAIN" ]] && cwd=domain
  hook::extract_bash_subject_to subject "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$1" cwd "$cwd"
  hook::emit_telemetry "block-cross-domain" "PreToolUse" "${2:-ok}" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# bcd::malformed <reason>: tell the user once per session, then allow.
# shellcheck disable=SC2154  # HOOK_NOTICE_TO_USER is set by hook::notice_once
bcd::malformed() {
  bcd::emit_tel map-malformed
  if hook::notice_once guardrails-cross-domain-map "$INPUT" && [[ "$HOOK_NOTICE_TO_USER" == 1 ]]; then
    hook::emit_channels PreToolUse "" "guardrails block-cross-domain: the domain map $BCD_MAP is malformed ($1), so this guard checks nothing. Fix the file, or turn the guard off with block_cross_domain_enabled."
  fi
  exit 0
}

# bcd::compile: run the compiler over BCD_MAP_RAW into BCD_RECORDS and store
# them in CACHE, the key last, so a cache cut short ends in a partial key and is
# compiled again. A jq that fails is not cached. Two processes: jq, then the mv
# that puts the cache in place whole.
bcd::compile() {
  local out rc=0 tmp
  bcd::trace map-compile
  # On Windows the MSYS runtime would rewrite a POSIX HOME (`/home/<user>`)
  # into a Windows path on its way to the native jq; HOME reaches it as written.
  out=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' exec jq -r -R -s --arg os "$BCD_OS" --arg home "$BCD_HOME" \
    "$BCD_COMPILE" 2>/dev/null <<<"$BCD_MAP_RAW") || rc=$?
  if ((rc != 0)); then
    BCD_RECORDS=("invalid${BCD_TAB}jq exited $rc reading it")
    return 0
  fi
  # The Windows jq build writes CRLF.
  out=${out//$'\r'/}
  BCD_RECORDS=()
  [[ -n "$out" ]] && mapfile -t BCD_RECORDS <<<"$out"
  tmp="$BCD_CACHE.$$.$RANDOM"
  if printf '%s\0' ${BCD_RECORDS[@]+"${BCD_RECORDS[@]}"} "$BCD_KEY" 2>/dev/null >"$tmp"; then
    mv -f -- "$tmp" "$BCD_CACHE" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
  fi
  return 0
}

# bcd::load: BCD_RECORDS for the map as it is now, from CACHE when its key is
# this map's bytes under this format, host and HOME, else from the compiler.
bcd::load() {
  local -a cache=()
  BCD_MAP_RAW=""
  if [[ ! -r "$BCD_MAP" ]]; then
    BCD_RECORDS=("invalid${BCD_TAB}it cannot be read")
    return 0
  fi
  IFS= read -r -d '' BCD_MAP_RAW 2>/dev/null <"$BCD_MAP"
  if ((${#BCD_MAP_RAW} > 65536)); then
    BCD_RECORDS=("invalid${BCD_TAB}it is over 64 KiB")
    return 0
  fi
  BCD_KEY="block-cross-domain cache $BCD_FORMAT $BCD_OS $BCD_HOME"$'\n'"$BCD_MAP_RAW"
  [[ -f "$BCD_CACHE" ]] && mapfile -d '' -t cache 2>/dev/null <"$BCD_CACHE"
  if ((${#cache[@]})) && [[ "${cache[-1]}" == "$BCD_KEY" ]]; then
    bcd::trace map-cached
    BCD_RECORDS=("${cache[@]:0:${#cache[@]}-1}")
    return 0
  fi
  bcd::compile
}

# bcd::norm_to <var> <path>: the form a cwd and a root are compared in: the
# library's normalizer (`\` as `/`; on Windows the drive folded to `C:` and the
# rest lowercased), runs of `/` as one, no trailing `/`.
bcd::norm_to() {
  local __bcd_p __bcd_s='/' __bcd_d='//'
  hook::normalize_path_to __bcd_p "$2"
  while [[ "$__bcd_p" == *//* ]]; do __bcd_p=${__bcd_p//"$__bcd_d"/"$__bcd_s"}; done
  while [[ "$__bcd_p" == ?*/ ]]; do __bcd_p=${__bcd_p%/}; done
  printf -v "$1" '%s' "$__bcd_p"
}

# bcd::fold_to <var> <text>: the form the prefilter and the parse test in:
# lowercased, `\` as `/`, runs of `/` as one, no trailing `/`.
bcd::fold_to() {
  local __bcd_t="${2,,}" __bcd_s='/' __bcd_d='//'
  __bcd_t=${__bcd_t//\\//}
  while [[ "$__bcd_t" == *//* ]]; do __bcd_t=${__bcd_t//"$__bcd_d"/"$__bcd_s"}; done
  while [[ "$__bcd_t" == ?*/ ]]; do __bcd_t=${__bcd_t%/}; done
  printf -v "$1" '%s' "$__bcd_t"
}

# bcd::dir_to <var> <config directory as written>: the form a gh or az config
# directory is compared in: folded, a leading HOME spelling read as HOME, and on
# Windows a drive prefix read as `<drive>:`.
bcd::dir_to() {
  local __bcd_dt __bcd_p
  bcd::fold_to __bcd_dt "$2"
  if [[ -n "$BCD_HOME_FOLD" ]]; then
    # shellcheck disable=SC2016  # spellings matched as text, never expanded
    for __bcd_p in '~' '$home' '${home}' '$env:home' '${env:home}' '$env:userprofile' '${env:userprofile}' '%userprofile%'; do
      if [[ "$__bcd_dt" == "$__bcd_p" || "$__bcd_dt" == "$__bcd_p"/* ]]; then
        __bcd_dt=$BCD_HOME_FOLD${__bcd_dt#"$__bcd_p"}
        break
      fi
    done
  fi
  if [[ "$BCD_OS" == windows && "$__bcd_dt" =~ ^/(cygdrive/|mnt/)?([a-z])(/.*)?$ ]]; then
    __bcd_dt=${BASH_REMATCH[2]}:${BASH_REMATCH[3]:-/}
  fi
  printf -v "$1" '%s' "$__bcd_dt"
}

# bcd::add_needle <domain> <folded text> <1 for a path, 2 for a shared
# exception's path, 0 for a marker> [<the exception's from domains>]
bcd::add_needle() {
  [[ -n "$2" ]] || return 0
  BCD_NEEDLE+=("$2")
  BCD_NEEDLE_DOMAIN+=("$1")
  BCD_NEEDLE_PATH+=("$3")
  BCD_NEEDLE_FROM+=("${4-}")
}

# bcd::add_root <domain> <root or owner directory as spelled> [<from domains>]:
# the path for the cwd and every spelling of it a command can name; with from
# domains, a shared exception's path, which classifies no cwd.
bcd::add_root() {
  local c n rest drive="" p kind=1
  bcd::norm_to c "$2"
  if [[ -n "${3-}" ]]; then
    kind=2
  else
    BCD_ROOT+=("$c")
    BCD_ROOT_DOMAIN+=("$1")
  fi
  bcd::fold_to n "$2"
  bcd::add_needle "$1" "$n" "$kind" "${3-}"
  if [[ "$n" =~ ^([a-z]):(/.*)$ ]]; then
    drive=${BASH_REMATCH[1]}
    rest=${BASH_REMATCH[2]}
  elif [[ "$n" =~ ^/(cygdrive|mnt)/([a-z])(/.*)$ ]]; then
    drive=${BASH_REMATCH[2]}
    rest=${BASH_REMATCH[3]}
  elif [[ "$BCD_OS" == windows && "$n" =~ ^/([a-z])(/.*)$ ]]; then
    drive=${BASH_REMATCH[1]}
    rest=${BASH_REMATCH[2]}
  fi
  if [[ -n "$drive" ]]; then
    for p in "$drive:" "/$drive" "/cygdrive/$drive" "/mnt/$drive"; do
      [[ "$p$rest" == "$n" ]] || bcd::add_needle "$1" "$p$rest" "$kind" "${3-}"
    done
  fi
  if [[ -n "$BCD_HOME" && "$c" == "$BCD_HOME"/?* ]]; then
    bcd::fold_to rest "${c#"$BCD_HOME"}"
    # shellcheck disable=SC2016,SC2088  # spellings matched as text, never expanded
    for p in '~' '$home' '${home}' '$env:home' '${env:home}' '$env:userprofile' '${env:userprofile}' '%userprofile%'; do
      bcd::add_needle "$1" "$p$rest" "$kind" "${3-}"
    done
  fi
}

# bcd::named <domain> <1 when a path names it>: add the domain to BCD_NAMED,
# and to BCD_DENY when a path names it from a cwd in another domain.
bcd::named() {
  [[ "$BCD_NAMED" == *" $1 "* ]] || BCD_NAMED+="$1 "
  (($2)) && [[ -n "$BCD_CWD_DOMAIN" && "$1" != "$BCD_CWD_DOMAIN" && " ${BCD_DENY[*]-} " != *" $1 "* ]] || return 0
  BCD_DENY+=("$1")
}

# bcd::names <folded text>: add to BCD_NAMED each domain whose marker or path
# the text names. The needles come markers first, then paths longest first, and
# a path that names its domain spends its text: an outer path that text holds
# (a nested pair) is not named by it, while one named elsewhere in the text is.
# A shared exception's path open to the cwd's domain goes to bcd::spend_open;
# closed, it names its `to` domain as that domain's root would.
bcd::names() {
  local t="$1" n i
  for ((i = 0; i < ${#BCD_NEEDLE[@]}; i++)); do
    n=${BCD_NEEDLE[i]}
    [[ "$t" == *"$n"* ]] || continue
    case "$t" in
    "$n" | "$n"[!a-z0-9._-]* | *[!a-z0-9._-]"$n" | *[!a-z0-9._-]"$n"[!a-z0-9._-]*) ;;
    *) continue ;;
    esac
    if ((BCD_NEEDLE_PATH[i] == 2 && BCD_DOTDOT == 0)) && [[ -n "$BCD_CWD_DOMAIN" && " ${BCD_NEEDLE_FROM[i]} " == *" $BCD_CWD_DOMAIN "* ]]; then
      bcd::spend_open "$n" "${BCD_NEEDLE_DOMAIN[i]}"
      continue
    fi
    bcd::named "${BCD_NEEDLE_DOMAIN[i]}" "${BCD_NEEDLE_PATH[i]}"
    if ((BCD_NEEDLE_PATH[i])); then
      t=${t//"$n"/ }
    elif [[ "${BCD_NEEDLE_DOMAIN[i]}" != "$BCD_CWD_DOMAIN" ]]; then
      BCD_FOREIGN_MARKER=1
    fi
  done
  return 0
}

# bcd::spend_open <needle> <its to domain>: an open shared exception's path, in
# bcd::names's text `t`. Each occurrence that names it becomes a space, and one
# that the text's end, `/`, whitespace or a word-ending operator (`;&|<>()`)
# does not follow names its `to` domain: a glob, brace or expansion
# (`shared*`, `shared{,-x}`, `shared$x`) can reach past it, and any other
# character (`shared+x`, `shared~x`) continues a sibling's name. An occurrence
# inside a longer name is kept, so a sibling (`shared-x`) still names `to`
# through its root.
bcd::spend_open() {
  local rest=$t out="" pre
  while [[ "$rest" == *"$1"* ]]; do
    pre=${rest%%"$1"*}
    rest=${rest#*"$1"}
    if [[ "${pre: -1}" == [a-z0-9._-] || "${rest:0:1}" == [a-z0-9._-] ]]; then
      out+=$pre$1
      continue
    fi
    case "${rest:0:1}" in
    '' | / | ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '<' | '>' | '(' | ')') ;;
    *) bcd::named "$2" 2 ;;
    esac
    out+="$pre "
  done
  t=$out$rest
}

# bcd::deny: the decision, as a PreToolUse document on stdout. The exit stays 0.
bcd::deny() {
  local d others="" esc
  for d in "${BCD_DENY[@]}"; do others+="${others:+, }'$d'"; done
  hook::json_escape_to esc "guardrails block-cross-domain: denied. This session's directory is in identity domain '$BCD_CWD_DOMAIN', and the command names a path the domain map gives to another domain ($others). Reading a path there is denied too. Run the command from a session in that domain. If the map is wrong, fix $BCD_MAP; to turn the guard off, set block_cross_domain_enabled to false."
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$esc"'"}'"$BCD_NOTICE_JSON"'}'
}

# bcd::grants_nothing: the once-per-session notice naming each shared exception
# that grants nothing, into BCD_NOTICE and, for a deny document,
# BCD_NOTICE_JSON.
# shellcheck disable=SC2154  # HOOK_NOTICE_TO_USER is set by hook::notice_once
bcd::grants_nothing() {
  local e list="" esc
  hook::notice_once guardrails-cross-domain-shared "$INPUT" || return 0
  [[ "$HOOK_NOTICE_TO_USER" == 1 ]] || return 0
  for e in "${BCD_GRANTS_NOTHING[@]}"; do list+="${list:+; }$e"; done
  BCD_NOTICE="guardrails block-cross-domain: in the domain map $BCD_MAP, $list. An entry is {\"path\": <dir>, \"from\": [<domain>], \"to\": <domain>}, with the path inside the to domain's paths; re-run /guardrails:setup apply identity-domains to rewrite it."
  hook::json_escape_to esc "$BCD_NOTICE"
  BCD_NOTICE_JSON=',"systemMessage":"'"$esc"'"'
}

# bcd::allow: the call is allowed; a pending notice goes out alone, then exit 0.
bcd::allow() {
  [[ -z "$BCD_NOTICE" ]] || hook::emit_channels PreToolUse "" "$BCD_NOTICE"
  exit 0
}

# The parse callback: every argv word and redirection target of one segment.
# shellcheck disable=SC2329  # invoked by hook::bash_parse_segments
bcd::segment() {
  local __bcd_w __bcd_f
  if ((BCD_PATHS)); then
    for __bcd_w in "$@" ${HOOK_SEG_REDIR_TARGET[@]+"${HOOK_SEG_REDIR_TARGET[@]}"}; do
      bcd::fold_to __bcd_f "$__bcd_w"
      bcd::names "$__bcd_f"
    done
  fi
  ((BCD_IDENTITY)) && bcd::identity "$@"
  ((BCD_CONFIG)) && bcd::config "$@"
  ((BCD_AUTH)) && bcd::auth "$@"
  ((BCD_WRITES)) && bcd::writes "$@"
  return 0
}

# bcd::foreign_marker <text>: whether the text names a marker of a domain other
# than the cwd's that the cwd's own domain does not also list.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::foreign_marker() {
  local t n i
  bcd::fold_to t "$1"
  for ((i = 0; i < ${#BCD_NEEDLE[@]}; i++)); do
    ((BCD_NEEDLE_PATH[i] == 0)) || continue
    [[ "${BCD_NEEDLE_DOMAIN[i]}" != "$BCD_CWD_DOMAIN" ]] || continue
    n=${BCD_NEEDLE[i]}
    [[ "$t" == *"$n"* && "$BCD_OWN_MARKERS" != *$'\n'"$n"$'\n'* ]] || continue
    case "$t" in
    "$n" | "$n"[!a-z0-9._-]* | *[!a-z0-9._-]"$n" | *[!a-z0-9._-]"$n"[!a-z0-9._-]*) return 0 ;;
    *) ;;
    esac
  done
  return 1
}

# bcd::check <position> <value>: record the position once when the value names
# a foreign marker.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::check() {
  local p
  bcd::foreign_marker "$2" || return 0
  for p in ${BCD_IDENTITY_DENY[@]+"${BCD_IDENTITY_DENY[@]}"}; do
    [[ "$p" == "$1" ]] && return 0
  done
  BCD_IDENTITY_DENY+=("$1")
}

# bcd::env_name_to <var> <assigned name, or PowerShell's $env:<name> in any
# case>: the variable's name.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::env_name_to() {
  local __bcd_u=$2
  if [[ "$__bcd_u" == \$* ]]; then
    __bcd_u=${__bcd_u^^}
    __bcd_u=${__bcd_u#\$}
    __bcd_u=${__bcd_u#\{}
    __bcd_u=${__bcd_u%\}}
    __bcd_u=${__bcd_u#ENV:}
  fi
  printf -v "$1" '%s' "$__bcd_u"
}

# bcd::ps_assign <callback> <word> <next word> <word after it>: the callback on
# the name and value of PowerShell's `$env:NAME = value`, in each spacing.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::ps_assign() {
  if [[ "$2" == *=?* ]]; then
    "$1" "${2%%=*}" "${2#*=}"
  elif [[ "$2" == *= ]]; then
    "$1" "${2%=}" "$3"
  elif [[ "$3" == = ]]; then
    "$1" "$2" "$4"
  elif [[ "$3" == =* ]]; then
    "$1" "$2" "${3#=}"
  fi
  return 0
}

# shellcheck disable=SC2329  # reached from the parse callback
bcd::identity_var() { # <assigned name, or PowerShell's $env:<name> in any case> <value>
  local u
  bcd::env_name_to u "$1"
  case "$u" in
  GH_CONFIG_DIR | AZURE_CONFIG_DIR | GIT_AUTHOR_NAME | GIT_AUTHOR_EMAIL | GIT_COMMITTER_NAME | GIT_COMMITTER_EMAIL)
    bcd::check "$u" "$2"
    ;;
  *) ;;
  esac
}

# shellcheck disable=SC2329  # reached from the parse callback
bcd::git_key() { # <position> <config key> <value>
  local k=${2,,}
  case "$k" in
  user.email | user.name | author.email | author.name | committer.email | committer.name | remote.*.url | remote.*.pushurl)
    bcd::check "$1 $k" "$3"
    ;;
  *) ;;
  esac
}

# bcd::git_config <index after the subcommand> <words...>: the key and value
# of `git config [<options>] [set] <key> <value>`.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::git_config() {
  local j=$1 n w
  shift
  local -a g=("$@") pos=()
  n=${#g[@]}
  for ((; j < n; j++)); do
    w=${g[j]}
    case "$w" in
    -f | --file | --blob | --type | --default | --comment | --value) ((j++)) ;;
    --get | --get-all | --get-regexp | --get-urlmatch | --unset | --unset-all | -l | --list | --rename-section | --remove-section)
      return 0
      ;;
    --)
      pos+=("${g[@]:j+1}")
      break
      ;;
    -*) ;;
    *) pos+=("$w") ;;
    esac
  done
  [[ "${pos[0]-}" == set ]] && pos=("${pos[@]:1}")
  ((${#pos[@]} >= 2)) && bcd::git_key "git config" "${pos[0]}" "${pos[1]}"
  return 0
}

# bcd::identity <words...>: the identity positions of one segment, into
# BCD_IDENTITY_DENY.
# shellcheck disable=SC2329  # also invoked by hook::bash_parse_segments
bcd::identity() {
  local -a w=("$@") g=()
  local n=$# i=0 j w1 op
  while ((i < n)); do
    w1=${w[i]}
    case "$w1" in
    env | */env | export | if | then | elif | else | do | while | until | time | '{' | '!') ;;
    -*) ((i > 0)) || break ;;
    \$[Ee][Nn][Vv]:* | \$\{[Ee][Nn][Vv]:*)
      bcd::ps_assign bcd::identity_var "$w1" "${w[i + 1]-}" "${w[i + 2]-}"
      break
      ;;
    [A-Za-z_]*=*) bcd::identity_var "${w1%%=*}" "${w1#*=}" ;;
    *) break ;;
    esac
    i=$((i + 1))
  done

  hook::git_invocation "$@" || return 0
  for ((j = 0; j < ${#HOOK_GITINV_CONFIG_VALUES[@]}; j++)); do
    [[ "${HOOK_GITINV_CONFIG_KINDS[j]-}" == inline ]] || continue
    w1=${HOOK_GITINV_CONFIG_VALUES[j]}
    [[ "$w1" == *=* ]] && bcd::git_key "git -c" "${w1%%=*}" "${w1#*=}"
  done
  g=("${HOOK_GITINV_WORDS[@]}")
  n=${#g[@]}
  j=$((HOOK_GITINV_SUB_IDX + 1))
  case "${HOOK_GITINV_SUB,,}" in
  remote)
    while ((j < n)) && [[ "${g[j]}" == -* ]]; do j=$((j + 1)); done
    op=${g[j]-}
    [[ "$op" == add || "$op" == set-url ]] || return 0
    [[ " ${g[*]:j} " == *" --delete "* ]] && return 0
    for ((j++; j < n; j++)); do
      bcd::check "git remote $op" "${g[j]}"
    done
    ;;
  config) bcd::git_config "$j" "${g[@]}" ;;
  commit)
    for ((; j < n; j++)); do
      case "${g[j]}" in
      --author=*) bcd::check "git commit --author" "${g[j]#--author=}" ;;
      --author)
        j=$((j + 1))
        bcd::check "git commit --author" "${g[j]-}"
        ;;
      -m | -F | -C | -c | -t | --message | --file | --reuse-message | --reedit-message | --template | --fixup | --squash | --cleanup | --date | --trailer)
        j=$((j + 1))
        ;;
      --) break ;;
      *) ;;
      esac
    done
    ;;
  *) ;;
  esac
  return 0
}

# bcd::identity_deny: the PreToolUse deny naming each identity position, then
# exit 0.
bcd::identity_deny() {
  local p list="" reason
  for p in "${BCD_IDENTITY_DENY[@]}"; do list+="${list:+, }$p"; done
  hook::json_escape_to reason "BLOCKED by guardrails block-cross-domain: this session's directory is in one identity domain, and this command puts another domain's identity marker in an identity position ($list). Run it from a session in that domain's tree, or turn the guard off with the block_cross_domain_enabled option."
  bcd::emit_tel identity-deny blocked
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$reason"'"}'"$BCD_NOTICE_JSON"'}'
  exit 0
}

# bcd::config_var <assigned name, or PowerShell's $env:<name>> <value> [<1 to
# set, 0 to remove>]: into the segment's view of the two config variables.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::config_var() {
  local u
  bcd::env_name_to u "$1"
  case "$u" in
  GH_CONFIG_DIR)
    cf_gh_set=${3-1}
    cf_gh=$2
    ;;
  AZURE_CONFIG_DIR)
    cf_az_set=${3-1}
    cf_az=$2
    ;;
  *) ;;
  esac
}

# bcd::config_check <gh|az> <variable> <text state> <text value> <hook
# environment value>: record a deny when the call does not run with the cwd
# domain's directory, or, from a domain with none, runs with another domain's.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::config_check() {
  local dir="" cwd_dir="" dir_domain="" i msg
  case "$3" in
  1) bcd::dir_to dir "$4" ;;
  0) ;;
  *) [[ -z "$5" ]] || bcd::dir_to dir "$5" ;;
  esac
  for ((i = 0; i < ${#BCD_CONF_KIND[@]}; i++)); do
    [[ "${BCD_CONF_KIND[i]}" == "$1" ]] || continue
    if [[ "${BCD_CONF_DOMAIN[i]}" == "$BCD_CWD_DOMAIN" ]]; then
      cwd_dir=${BCD_CONF_RAW[i]}
      [[ "$dir" == "${BCD_CONF_DIR[i]}" ]] && return 0
    elif [[ -n "$dir" && "$dir" == "${BCD_CONF_DIR[i]}" ]]; then
      dir_domain=${BCD_CONF_DOMAIN[i]}
    fi
  done
  if [[ -n "$cwd_dir" ]]; then
    msg="runs $1 without the domain's $2 ($cwd_dir)"
  elif [[ -n "$dir_domain" ]]; then
    msg="runs $1 with domain '$dir_domain''s $2, where this domain uses the default"
  else
    return 0
  fi
  [[ " ${BCD_CONFIG_DENY[*]-} " == *" $msg "* ]] || BCD_CONFIG_DENY+=("$msg")
}

# bcd::config <words...>: the config directories of one segment's gh or az
# call, into BCD_CONFIG_DENY. A segment with no command carries what it sets to
# later segments.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::config() {
  local -a w=("$@")
  local n=$# i=0 w1 cmd="" keep=1 exported=0 wrapped=0 tool
  local cf_gh_set=$BCD_GH_SET cf_gh=$BCD_GH cf_az_set=$BCD_AZ_SET cf_az=$BCD_AZ
  while ((i < n)); do
    w1=${w[i]}
    case "$w1" in
    if | then | elif | else | do | while | until | '{' | '!') ;;
    time | command | exec | nohup) wrapped=1 ;;
    export) exported=1 ;;
    env | */env) keep=0 ;;
    unset)
      exported=1
      for ((i++; i < n; i++)); do bcd::config_var "${w[i]}" "" 0; done
      break
      ;;
    -i | - | --ignore-environment)
      ((keep)) && break
      cf_gh_set=0
      cf_az_set=0
      ;;
    -u | --unset)
      ((keep)) && break
      i=$((i + 1))
      bcd::config_var "${w[i]-}" "" 0
      ;;
    --unset=* | -u?*)
      ((keep)) && break
      w1=${w1#--unset=}
      bcd::config_var "${w1#-u}" "" 0
      ;;
    -C | --chdir)
      ((keep)) && break
      i=$((i + 1))
      ;;
    # `command -v` and `-V` look a name up and run nothing.
    -v | -V)
      ((wrapped)) && return 0
      ((keep)) && break
      ;;
    -*) ((keep && !wrapped)) && break ;;
    \$[Ee][Nn][Vv]:* | \$\{[Ee][Nn][Vv]:*)
      exported=1
      bcd::ps_assign bcd::config_var "$w1" "${w[i + 1]-}" "${w[i + 2]-}"
      break
      ;;
    [A-Za-z_]*=*) bcd::config_var "${w1%%=*}" "${w1#*=}" ;;
    *)
      cmd=$w1
      break
      ;;
    esac
    i=$((i + 1))
  done
  if [[ -z "$cmd" ]]; then
    ((keep && !wrapped)) || return 0
    if ((exported == 0)); then
      # A bare assignment reaches a later command only when the name is exported.
      [[ "$BCD_GH_SET" == 1 || ( -z "$BCD_GH_SET" && -n "${GH_CONFIG_DIR+x}" ) ]] || cf_gh_set=$BCD_GH_SET cf_gh=$BCD_GH
      [[ "$BCD_AZ_SET" == 1 || ( -z "$BCD_AZ_SET" && -n "${AZURE_CONFIG_DIR+x}" ) ]] || cf_az_set=$BCD_AZ_SET cf_az=$BCD_AZ
    fi
    BCD_GH_SET=$cf_gh_set BCD_GH=$cf_gh BCD_AZ_SET=$cf_az_set BCD_AZ=$cf_az
    return 0
  fi
  [[ "${w[i + 1]-}" == --version ]] && return 0
  tool=${cmd##*/}
  tool=${tool,,}
  tool=${tool%.exe}
  case "${tool%.cmd}" in
  gh) bcd::config_check gh GH_CONFIG_DIR "$cf_gh_set" "$cf_gh" "${GH_CONFIG_DIR-}" ;;
  az) bcd::config_check az AZURE_CONFIG_DIR "$cf_az_set" "$cf_az" "${AZURE_CONFIG_DIR-}" ;;
  *) ;;
  esac
  return 0
}

# bcd::config_deny: the PreToolUse deny naming each config directory a gh or
# az call runs without or with, then exit 0.
bcd::config_deny() {
  local m list="" reason
  for m in "${BCD_CONFIG_DENY[@]}"; do list+="${list:+; it }$m"; done
  hook::json_escape_to reason "guardrails block-cross-domain: denied. This session's directory is in identity domain '$BCD_CWD_DOMAIN', and the command $list. Set GH_CONFIG_DIR or AZURE_CONFIG_DIR in the command to this domain's directory, or leave it unset where this domain uses the default. If the map is wrong, fix $BCD_MAP; to turn the guard off, set block_cross_domain_enabled to false."
  bcd::emit_tel config-deny blocked
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$reason"'"}'"$BCD_NOTICE_JSON"'}'
  exit 0
}

# shellcheck disable=SC2329  # reached from the parse callback
bcd::auth_found() { # <what the command does, as written>
  local p
  for p in ${BCD_AUTH_DENY[@]+"${BCD_AUTH_DENY[@]}"}; do
    [[ "$p" == "$1" ]] && return 0
  done
  BCD_AUTH_DENY+=("$1")
}

# bcd::auth_token <assigned name, or PowerShell's $env:<name>> <value>: an
# assignment that empties GH_TOKEN (an empty value, or `$null` in any case).
# A value the parse cut off at a backtick or `(` arrives empty and is no removal.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::auth_token() {
  local u
  bcd::env_name_to u "$1"
  [[ "$u" == GH_TOKEN ]] || return 0
  # shellcheck disable=SC2016  # a backtick and PowerShell's $null, matched as text
  if [[ -z "$2" ]]; then
    [[ "$BCD_SUBJECT" == *'gh_token=`'* || "$BCD_SUBJECT" == *'gh_token=('* ]] || bcd::auth_found "an empty GH_TOKEN"
  elif [[ "${2,,}" == '$null' ]]; then
    bcd::auth_found "an empty GH_TOKEN"
  fi
  return 0
}

# bcd::auth <words...>: the gh account switches and GH_TOKEN removals of one
# segment (AUTH SWITCHES), into BCD_AUTH_DENY.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::auth() {
  local -a w=("$@")
  local n=$# i=0 w1 cmd="" keep=1 wrapped=0 unexport=0 tool
  while ((i < n)); do
    w1=${w[i]}
    case "$w1" in
    if | then | elif | else | do | while | until | '{' | '!') ;;
    time | command | exec | nohup) wrapped=1 ;;
    export)
      for ((i++; i < n; i++)); do
        case "${w[i]}" in
        -n) unexport=1 ;;
        GH_TOKEN) ((unexport)) && bcd::auth_found "export -n GH_TOKEN" ;;
        [A-Za-z_]*=*) bcd::auth_token "${w[i]%%=*}" "${w[i]#*=}" ;;
        *) ;;
        esac
      done
      return 0
      ;;
    unset)
      for ((i++; i < n; i++)); do
        # `unset -f` removes functions, not variables.
        [[ "${w[i]}" == -f ]] && return 0
        [[ "${w[i]}" == GH_TOKEN ]] && bcd::auth_found "unset GH_TOKEN"
      done
      return 0
      ;;
    env | */env) keep=0 ;;
    -u | --unset)
      ((keep)) && return 0
      i=$((i + 1))
      [[ "${w[i]-}" == GH_TOKEN ]] && bcd::auth_found "env $w1 GH_TOKEN"
      ;;
    --unset=* | -u?*)
      ((keep)) && return 0
      [[ "$w1" == --unset=GH_TOKEN || "$w1" == -uGH_TOKEN ]] && bcd::auth_found "env $w1"
      ;;
    -C | --chdir)
      ((keep)) && return 0
      i=$((i + 1))
      ;;
    -v | -V)
      ((wrapped || keep)) && return 0
      ;;
    -*) ((keep && !wrapped)) && return 0 ;;
    \$[Ee][Nn][Vv]:* | \$\{[Ee][Nn][Vv]:*)
      # A value the parse cut off (`= (gh auth token)`) is no word, where `''` is an empty one.
      [[ "$w1" == *= && -z "${w[i + 1]+x}" ]] && return 0
      [[ "$w1" != *=* && "${w[i + 1]-}" == = && -z "${w[i + 2]+x}" ]] && return 0
      bcd::ps_assign bcd::auth_token "$w1" "${w[i + 1]-}" "${w[i + 2]-}"
      return 0
      ;;
    [A-Za-z_]*=*) bcd::auth_token "${w1%%=*}" "${w1#*=}" ;;
    *)
      cmd=$w1
      break
      ;;
    esac
    i=$((i + 1))
  done
  tool=${cmd##*/}
  tool=${tool,,}
  tool=${tool%.exe}
  case "${tool%.cmd}" in
  gh)
    [[ "${w[i + 1]-}" == auth ]] || return 0
    case "${w[i + 2]-}" in
    switch | login | logout) bcd::auth_found "gh auth ${w[i + 2]}" ;;
    *) ;;
    esac
    ;;
  remove-item | ri | rm | del | erase | rd | rmdir)
    [[ "$TOOL_NAME" == PowerShell ]] || return 0
    for ((i++; i < n; i++)); do
      w1=${w[i],,}
      [[ "$w1" == env:gh_token || "$w1" == env:/gh_token ]] && bcd::auth_found "Remove-Item ${w[i]}"
    done
    ;;
  *) ;;
  esac
  return 0
}

# bcd::auth_deny: the PreToolUse deny naming each account switch and GH_TOKEN
# removal, then exit 0.
bcd::auth_deny() {
  local m list="" reason
  for m in "${BCD_AUTH_DENY[@]}"; do list+="${list:+; }$m"; done
  hook::json_escape_to reason "guardrails block-cross-domain: denied. This session's directory is in identity domain '$BCD_CWD_DOMAIN', which gives gh its own GH_CONFIG_DIR, and the command switches gh's account or removes GH_TOKEN ($list). Either one lets gh act as an account other than this session's. Ask the user to make the change. If the map is wrong, fix $BCD_MAP; to turn the guard off, set block_cross_domain_enabled to false."
  bcd::emit_tel auth-deny blocked
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$reason"'"}'"$BCD_NOTICE_JSON"'}'
  exit 0
}

# bcd::write_prefilter: whether the folded command text could hold an identity
# write: both `git` and `config`, or the last name of a listed identity file.
bcd::write_prefilter() {
  local n
  [[ "$BCD_SUBJECT" == *git* && "$BCD_SUBJECT" == *config* ]] && return 0
  for n in ${BCD_IDFILE_NAMES[@]+"${BCD_IDFILE_NAMES[@]}"}; do
    [[ -n "$n" && "$BCD_SUBJECT" == *"$n"* ]] && return 0
  done
  return 1
}

# bcd::is_idfile <word>: whether the word names an identity file (GIT IDENTITY
# WRITES).
# shellcheck disable=SC2329  # reached from the parse callback
bcd::is_idfile() {
  local p s
  bcd::dir_to p "$1"
  [[ "${p##*/}" == ?*.gitconfig ]] && return 0
  if [[ "${p##*/}" == .gitconfig* && "$p" == */* ]]; then
    [[ -n "$BCD_HOME_FOLD" && "${p%/*}" == "$BCD_HOME_FOLD" ]] && return 0
    # shellcheck disable=SC2016  # spellings matched as text, never expanded
    for s in '~' '$home' '${home}' '$env:home' '${env:home}' '$env:userprofile' '${env:userprofile}' '%userprofile%'; do
      [[ "${p%/*}" == "$s" ]] && return 0
    done
  fi
  for s in ${BCD_IDFILES[@]+"${BCD_IDFILES[@]}"}; do
    [[ -n "$s" && ("$p" == "$s" || "$p" == "$s"/*) ]] && return 0
  done
  return 1
}

# shellcheck disable=SC2329  # reached from the parse callback
bcd::write_found() { # <what the command writes, as written>
  local p
  for p in ${BCD_WRITE_DENY[@]+"${BCD_WRITE_DENY[@]}"}; do
    [[ "$p" == "$1" ]] && return 0
  done
  BCD_WRITE_DENY+=("$1")
}

# shellcheck disable=SC2329  # reached from the parse callback
bcd::write_word() { # <command word or operator> <operand>
  bcd::is_idfile "$2" && bcd::write_found "$1 $2"
  return 0
}

# shellcheck disable=SC2329  # reached from the parse callback
bcd::identity_key() { # <config key>
  case "${1,,}" in
  user.email | user.signingkey | user.useconfigonly | credential.helper | credential.*.helper | \
    core.sshcommand | core.hookspath | includeif.*) return 0 ;;
  *) return 1 ;;
  esac
}

# shellcheck disable=SC2329  # reached from the parse callback
bcd::identity_section() { # <config section>
  case "${1,,}" in
  user | core | credential | credential.* | includeif.*) return 0 ;;
  *) return 1 ;;
  esac
}

# bcd::inplace_flag <sed|perl> <word>: whether the option word edits in place:
# an `i` among its bundled letters before one that takes a value (`-pi.bak`,
# `-Ei`; not `-Mstrict` or `-ne`).
# shellcheck disable=SC2329  # reached from the parse callback
bcd::inplace_flag() {
  local flag=$2 stop=efl k c
  [[ "$flag" == --in-place* ]] && return 0
  [[ "$flag" == -[!-]* ]] || return 1
  [[ "$1" == perl ]] && stop=eEMmIxCl0
  for ((k = 1; k < ${#flag}; k++)); do
    c=${flag:k:1}
    [[ "$c" == i ]] && return 0
    [[ "$stop" == *"$c"* ]] && return 1
  done
  return 1
}

# bcd::text_redirs: the targets of `&>`, `&>>` and `>|`, read from the folded
# text, since the parse splits each of them at its `&` or `|`.
bcd::text_redirs() {
  local t=$BCD_SUBJECT re='(&>>?|>[|])[[:space:]]*([^[:space:];&|<>()]+)(.*)$'
  while [[ "$t" =~ $re ]]; do
    bcd::write_word "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    t=${BASH_REMATCH[3]}
  done
}

# bcd::git_config_write: the identity write of the segment's `git config`, from
# hook::git_invocation's words.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::git_config_write() {
  local -a g=("${HOOK_GITINV_WORDS[@]}") pos=()
  local n=${#HOOK_GITINV_WORDS[@]} j=$((HOOK_GITINV_SUB_IDX + 1)) w scope="" action="" key
  for ((; j < n; j++)); do
    w=${g[j]}
    case "$w" in
    --global | --system) scope=$w ;;
    -f | --file)
      j=$((j + 1))
      bcd::is_idfile "${g[j]-}" && scope="$w ${g[j]}"
      ;;
    --file=*) bcd::is_idfile "${w#--file=}" && scope=$w ;;
    --blob | --type | --default | --comment | --value | --url) j=$((j + 1)) ;;
    --get | --get-all | --get-regexp | --get-urlmatch | --get-color | --get-colorbool | -l | --list) return 0 ;;
    -e | --edit | --unset | --unset-all | --add | --replace-all | --rename-section | --remove-section) action=$w ;;
    --)
      pos+=("${g[@]:j+1}")
      break
      ;;
    -*) ;;
    *) pos+=("$w") ;;
    esac
  done
  [[ -n "$scope" ]] || return 0
  case "${pos[0]-}" in
  get | list) return 0 ;;
  set | unset | edit | rename-section | remove-section)
    action=${pos[0]}
    pos=("${pos[@]:1}")
    ;;
  *) ;;
  esac
  case "$action" in
  -e | --edit | edit)
    bcd::write_found "git config $scope $action"
    return 0
    ;;
  --rename-section | --remove-section | rename-section | remove-section)
    for key in ${pos[@]+"${pos[@]}"}; do
      bcd::identity_section "$key" && bcd::write_found "git config $scope $action $key"
    done
    return 0
    ;;
  # The old form with a key and no value reads it.
  "") ((${#pos[@]} >= 2)) || return 0 ;;
  *) ;;
  esac
  key=${pos[0]-}
  bcd::identity_key "$key" && bcd::write_found "git config $scope ${action:+$action }$key"
  return 0
}

# bcd::writes <words...>: the identity writes of one segment, into
# BCD_WRITE_DENY.
# shellcheck disable=SC2329  # reached from the parse callback
bcd::writes() {
  local -a w=("$@")
  local n=$# i=0 k op t cmd="" dest="" named=0 inplace=0
  for ((k = 0; k < ${#HOOK_SEG_REDIR_OP[@]}; k++)); do
    op=${HOOK_SEG_REDIR_OP[k]}
    t=${HOOK_SEG_REDIR_TARGET[k]-}
    case "$op" in
    '>&') [[ "$t" =~ ^([0-9]+|-)$ ]] && continue ;;
    '>'* | '<>') ;;
    *) continue ;;
    esac
    bcd::write_word "$op" "$t"
  done
  if hook::git_invocation "$@" && [[ "${HOOK_GITINV_SUB,,}" == config ]]; then
    bcd::git_config_write
  fi
  while ((i < n)); do
    case "${w[i]}" in
    if | then | elif | else | do | while | until | '{' | '!' | time | command | exec | nohup | sudo | doas | env | */env | -* | [A-Za-z_]*=*) ;;
    *)
      cmd=${w[i]##*/}
      break
      ;;
    esac
    i=$((i + 1))
  done
  cmd=${cmd,,}
  cmd=${cmd%.exe}
  case "$cmd" in
  tee | touch | truncate | rm | unlink | shred | mv | set-content | add-content | out-file | clear-content | \
    remove-item | new-item | move-item | rename-item | tee-object | ac | clc | ni | ri | del | erase | mi | move | ren | rni)
    for ((k = i + 1; k < n; k++)); do bcd::write_word "$cmd" "${w[k]}"; done
    ;;
  cp | install | ln | rsync | scp | copy-item | cpi | copy)
    # The last operand, unless an option names the destination: `-t` for cp,
    # install and ln (rsync's `-t` is --times), and PowerShell's -Destination
    # by any prefix it accepts, with a space or a colon. Only PowerShell's
    # parameters are case-blind: `-T` of cp, install and ln is
    # --no-target-directory.
    for ((k = i + 1; k < n; k++)); do
      t=${w[k]}
      case "$cmd" in
      copy-item | cpi | copy) t=${t,,} ;;
      *) ;;
      esac
      case "$cmd:$t" in
      cp:-t | install:-t | ln:-t | cp:--target-directory | install:--target-directory | ln:--target-directory | \
        copy-item:-des* | cpi:-des* | copy:-des*)
        named=1
        if [[ "$t" == -des*:?* ]]; then
          bcd::write_word "$cmd" "${w[k]#*:}"
        else
          k=$((k + 1))
          bcd::write_word "$cmd" "${w[k]-}"
        fi
        ;;
      *:--target-directory=*)
        named=1
        bcd::write_word "$cmd" "${w[k]#*=}"
        ;;
      *:-*) ;;
      *) dest=${w[k]} ;;
      esac
    done
    # A `host:path` destination of scp or rsync is another machine's file.
    [[ ("$cmd" == scp || "$cmd" == rsync) && "$dest" =~ ^[^/]{2,}: ]] && dest=""
    ((named)) || [[ -z "$dest" ]] || bcd::write_word "$cmd" "$dest"
    ;;
  sed | perl)
    for ((k = i + 1; k < n; k++)); do
      bcd::inplace_flag "$cmd" "${w[k]}" && inplace=1
    done
    if ((inplace)); then
      for ((k = i + 1; k < n; k++)); do
        [[ "${w[k]}" == -* ]] || bcd::write_word "$cmd" "${w[k]}"
      done
    fi
    ;;
  dd)
    for ((k = i + 1; k < n; k++)); do
      [[ "${w[k]}" == of=* ]] && bcd::write_word "$cmd" "${w[k]#of=}"
    done
    ;;
  *) ;;
  esac
  return 0
}

# bcd::write_deny: the PreToolUse deny naming each identity write, then exit 0.
bcd::write_deny() {
  local p list="" reason
  for p in "${BCD_WRITE_DENY[@]}"; do list+="${list:+; }$p"; done
  hook::json_escape_to reason "guardrails block-cross-domain: denied. This command writes this machine's git identity ($list). The global, system and identity-file values of user.email, user.signingkey, user.useConfigOnly, credential.helper, core.sshCommand, core.hooksPath and includeIf, and the identity files themselves (~/.gitconfig*, *.gitconfig and the domain map's identity_files), decide which identity every repository on this machine commits and pushes as, so no session writes them, from any directory. Set a value for this repository alone with git config --local, or ask the user to make the change. To turn the guard off, set block_cross_domain_enabled to false."
  bcd::emit_tel identity-write-deny blocked
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$reason"'"}'"$BCD_NOTICE_JSON"'}'
  exit 0
}

bcd::classify_cwd() {
  local cwd r i best=0
  [[ -n "$BCD_CWD_RAW" ]] || return 0
  bcd::norm_to cwd "$BCD_CWD_RAW"
  for ((i = 0; i < ${#BCD_ROOT[@]}; i++)); do
    r=${BCD_ROOT[i]}
    if ((${#r} > best)) && [[ "$cwd" == "$r" || "$cwd" == "$r"/* ]]; then
      best=${#r}
      BCD_CWD_DOMAIN=${BCD_ROOT_DOMAIN[i]}
    fi
  done
}

[[ -n "${HOME:-}" ]] && bcd::norm_to BCD_HOME "$HOME"
[[ -n "$BCD_HOME" ]] && bcd::fold_to BCD_HOME_FOLD "$BCD_HOME"
[[ -z "$BCD_MAP" ]] || bcd::load
[[ "${BCD_RECORDS[0]-}" == invalid"$BCD_TAB"* ]] && bcd::malformed "${BCD_RECORDS[0]#invalid"$BCD_TAB"}"

for BCD_REC in ${BCD_RECORDS[@]+"${BCD_RECORDS[@]}"}; do
  BCD_KIND=${BCD_REC%%"$BCD_TAB"*}
  BCD_REC=${BCD_REC#*"$BCD_TAB"}
  BCD_DOM=${BCD_REC%%"$BCD_TAB"*}
  BCD_VAL=${BCD_REC#*"$BCD_TAB"}
  case "$BCD_KIND" in
  root | owner) bcd::add_root "$BCD_DOM" "$BCD_VAL" ;;
  shared) bcd::add_root "$BCD_DOM" "${BCD_VAL#*"$BCD_TAB"}" "${BCD_VAL%%"$BCD_TAB"*}" ;;
  legacy) BCD_GRANTS_NOTHING+=("shared_exceptions[$BCD_VAL] grants nothing: it is a plain path, the earlier shape") ;;
  outside) BCD_GRANTS_NOTHING+=("shared_exceptions[$BCD_VAL] grants nothing: its path is not a path of its to domain, '$BCD_DOM', on this host") ;;
  marker)
    bcd::fold_to BCD_VAL "$BCD_VAL"
    bcd::add_needle "$BCD_DOM" "$BCD_VAL" 0
    ;;
  gh | az)
    BCD_CONF_KIND+=("$BCD_KIND")
    BCD_CONF_DOMAIN+=("$BCD_DOM")
    BCD_CONF_RAW+=("$BCD_VAL")
    bcd::dir_to BCD_VAL "$BCD_VAL"
    BCD_CONF_DIR+=("$BCD_VAL")
    ;;
  idfile)
    bcd::dir_to BCD_VAL "$BCD_VAL"
    BCD_IDFILES+=("$BCD_VAL")
    BCD_IDFILE_NAMES+=("${BCD_VAL##*/}")
    ;;
  *) ;; # a kind a newer guard writes: CACHE is keyed by BCD_FORMAT, so none reaches here
  esac
done

bcd::classify_cwd
((${#BCD_GRANTS_NOTHING[@]})) && bcd::grants_nothing

bcd::fold_to BCD_SUBJECT "$COMMAND"
BCD_SUBJECT=${BCD_SUBJECT//[\"\']/}
BCD_DOTS=${COMMAND//[\\\"\']/}
[[ "$BCD_DOTS" == *..* ]] && BCD_DOTDOT=1
bcd::names "$BCD_SUBJECT"
[[ "$BCD_NAMED" == " " ]] || BCD_PATHS=1
if [[ -n "$BCD_CWD_DOMAIN" ]] && ((${#BCD_CONF_KIND[@]})); then
  case " $BCD_SUBJECT " in
  *[!a-z0-9_-]gh[!a-z0-9_-]* | *[!a-z0-9_-]az[!a-z0-9_-]*) BCD_CONFIG=1 ;;
  *) ;;
  esac
  # AUTH SWITCHES: only from a domain with a gh config directory.
  for ((BCD_I = 0; BCD_I < ${#BCD_CONF_KIND[@]}; BCD_I++)); do
    [[ "${BCD_CONF_KIND[BCD_I]}" == gh && "${BCD_CONF_DOMAIN[BCD_I]}" == "$BCD_CWD_DOMAIN" ]] || continue
    case " $BCD_SUBJECT " in
    *[!a-z0-9_-]gh[!a-z0-9_-]* | *gh_token*) BCD_AUTH=1 ;;
    *) ;;
    esac
    break
  done
fi
bcd::write_prefilter && BCD_WRITES=1
if ((BCD_PATHS == 0 && BCD_CONFIG == 0 && BCD_AUTH == 0 && BCD_WRITES == 0)); then
  # With no map this is nearly every call on every host: it leaves untraced.
  [[ -n "$BCD_MAP" ]] || exit 0
  bcd::trace prefilter-miss
  bcd::emit_tel prefilter-miss
  bcd::allow
fi
((BCD_PATHS)) && bcd::trace prefilter-hit
((BCD_CONFIG)) && bcd::trace config-hit
((BCD_AUTH)) && bcd::trace auth-hit
((BCD_WRITES)) && bcd::trace write-hit

# Identity positions are read only from a cwd in a domain, and only when the
# text names another domain's marker.
if [[ -n "$BCD_CWD_DOMAIN" ]] && ((BCD_FOREIGN_MARKER)); then
  BCD_IDENTITY=1
  for ((BCD_I = 0; BCD_I < ${#BCD_NEEDLE[@]}; BCD_I++)); do
    if ((BCD_NEEDLE_PATH[BCD_I] == 0)) && [[ "${BCD_NEEDLE_DOMAIN[BCD_I]}" == "$BCD_CWD_DOMAIN" ]]; then
      BCD_OWN_MARKERS+="${BCD_NEEDLE[BCD_I]}"$'\n'
    fi
  done
fi

if [[ "$TOOL_NAME" == Bash ]]; then
  bcd::trace parse
  BCD_NAMED=" "
  BCD_DENY=()
  hook::bash_parse_segments "$COMMAND" bcd::segment
elif ((BCD_IDENTITY || BCD_CONFIG || BCD_AUTH || BCD_WRITES)); then
  bcd::trace identity-parse
  BCD_PATHS=0
  hook::bash_parse_segments "${COMMAND//\\//}" bcd::segment
fi
((BCD_WRITES)) && bcd::text_redirs
((${#BCD_WRITE_DENY[@]})) && bcd::write_deny
((${#BCD_IDENTITY_DENY[@]})) && bcd::identity_deny
((${#BCD_AUTH_DENY[@]})) && bcd::auth_deny
((${#BCD_CONFIG_DENY[@]})) && bcd::config_deny

if [[ "$BCD_NAMED" == " " ]]; then
  BCD_FORM=not-named
elif [[ "$BCD_NAMED" == " $BCD_CWD_DOMAIN " ]]; then
  BCD_FORM=own-domain
else
  BCD_FORM=other-domain
fi
if ((${#BCD_DENY[@]})); then
  bcd::trace deny
  bcd::deny
  bcd::emit_tel "$BCD_FORM" blocked
else
  bcd::emit_tel "$BCD_FORM"
  bcd::allow
fi
exit 0
