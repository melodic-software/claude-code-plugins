#!/usr/bin/env bash
# Generate a work-item-tracker adapter from an adapter spec.
#
# This is the DETERMINISTIC half of /work-items:onboard-adapter
# (/discipline:script-the-deterministic-work). Everything here is mechanical: given a
# validated spec, the security skeleton, the capabilities manifest, the verb
# scaffolds, the conformance binding, and the README follow by construction. The
# judgement — which verbs the provider can honestly support, what its fields mean,
# what a live instance actually returns — happens in the skill, before this runs, and
# lands in the spec.
#
# Two things this script deliberately does that a template expander would not:
#   1. It REFUSES an incoherent spec (verbs claiming features the manifest denies),
#      because the manifest is a promise the core routes on. See check_coherence.
#   2. It stamps the generated manifest with the SEAM's own contract version, read
#      from lib/json.sh — never a value the spec supplies. A generated adapter that
#      declared its own version could be born already skewed from the engine that
#      will dispatch it (CONTRACT.md "Contract-version handshake").
#
# Usage:
#   generate-adapter.sh --spec <file> [--out-root <dir>] [--force] [--dry-run]
#
#   --spec      the adapter spec JSON (see reference/adapter-spec.md)
#   --out-root  repo root to generate into; default $CLAUDE_PROJECT_DIR, else the
#               git toplevel. Files land under <out-root>/tools/work-item-tracker/.
#   --force     overwrite existing generated files (refuses without it)
#   --dry-run   report what would be written, write nothing
#
# shellcheck disable=SC2034  # the @@KEY@@ substitution values are read by name via ${!k} in render(); ShellCheck cannot see indirect expansion
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
# The seam this adapter is generated against. Relative by default (the skill ships
# inside the same plugin as the seam); WIT_SEAM_DIR overrides for tests.
SEAM_DIR="${WIT_SEAM_DIR:-$SCRIPT_DIR/../../../tools/work-item-tracker}"

readonly EX_USAGE=2
readonly EX_SPEC=3

# The shebang the GENERATED scripts carry. It is substituted rather than written
# literally in the templates for a reason that is not cosmetic: a template is not a
# script, and a file that opens with a shebang is treated as one by tooling that
# discovers scripts rather than being told about them. Left literal, the templates sat
# in a contradiction between two repo gates — the exec-bit check flags a shebang file
# recorded non-executable, and making them executable then fed them to the repo's
# ShellCheck lane, which cannot parse a file full of @@PLACEHOLDER@@ tokens. Templates
# carry no shebang, so neither gate claims them; the generated output gets one here,
# and `emit` marks it executable. Two templates already opened with
# `# shellcheck shell=bash` instead — this makes the whole set consistent.
SHEBANG='#!/usr/bin/env bash'

# The adapter verb surface (CONTRACT.md "Adapter contract"): the core public set
# minus list-frontier (core-derived), plus list-items.
readonly ADAPTER_VERBS=(
  create-item get-item claim renew-lease reclaim link-blocks
  add-sub-item list-items list-sub-items capabilities
)
readonly FEATURE_KEYS=(cross_repo_edges sub_items leases labels)
readonly LIMIT_KEYS=(sub_items_per_parent sub_item_depth dependencies_per_type list_items_max)

die_usage() {
  printf 'generate-adapter.sh: %s\n' "$1" >&2
  printf 'usage: generate-adapter.sh --spec <file> [--out-root <dir>] [--force] [--dry-run]\n' >&2
  exit "$EX_USAGE"
}

die_spec() {
  printf 'generate-adapter.sh: invalid spec: %s\n' "$1" >&2
  exit "$EX_SPEC"
}

# --- arguments ---

SPEC=""
OUT_ROOT=""
FORCE=0
DRY_RUN=0

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '/^# Usage:/,/^#   --dry-run/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
  # An EMPTY value is rejected, not just a missing one. `--out-root ""` would
  # otherwise be indistinguishable from "no --out-root given" and fall through to
  # the repo-root default — so a caller whose variable failed to expand would
  # generate into the current repository instead of where it meant to.
  --spec)
    [[ $# -ge 2 && -n "$2" ]] || die_usage "--spec needs a non-empty value"
    SPEC="$2"
    shift 2
    ;;
  --out-root)
    [[ $# -ge 2 && -n "$2" ]] || die_usage "--out-root needs a non-empty value"
    OUT_ROOT="$2"
    shift 2
    ;;
  --force)
    FORCE=1
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  *)
    die_usage "unknown argument: $1"
    ;;
  esac
done

[[ -n "$SPEC" ]] || die_usage "--spec is required"
[[ -f "$SPEC" ]] || die_usage "spec not found: $SPEC"
command -v jq >/dev/null 2>&1 || die_usage "prerequisite missing: jq"

if [[ -z "$OUT_ROOT" ]]; then
  OUT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
fi
[[ -n "$OUT_ROOT" ]] || die_usage "no --out-root and no repo root to anchor at (set CLAUDE_PROJECT_DIR or run inside a git repo)"
[[ -d "$OUT_ROOT" ]] || die_usage "--out-root is not a directory: $OUT_ROOT"

SPEC_JSON="$(jq -c . "$SPEC" 2>/dev/null)" || die_spec "not valid JSON"

# --- spec validation ---

# sget <jq-path> — a raw string field, empty when absent.
sget() { jq -r "$1 // empty" <<<"$SPEC_JSON"; }

SPEC_VERSION="$(sget '.spec_version')"
[[ "$SPEC_VERSION" == "1.0" ]] ||
  die_spec "spec_version must be \"1.0\" (found: ${SPEC_VERSION:-none})"

PROVIDER="$(sget '.provider')"
# The provider name becomes a directory name, a file path segment, a shell function
# name fragment, a jq object key, and part of every generated identifier. Constrain it
# ONCE, here, so nothing downstream has to escape it.
[[ "$PROVIDER" =~ ^[a-z][a-z0-9-]{0,31}$ ]] ||
  die_spec "provider must match ^[a-z][a-z0-9-]{0,31}\$ (found: ${PROVIDER:-none})"

# Derived spellings of the provider name, needed from here on. Hyphens are not legal
# in shell identifiers or in the jq object-key shorthand, so the function/variable/key
# spellings underscore them.
PROVIDER_FUNC="${PROVIDER//-/_}"
PROVIDER_UPPER="$(tr '[:lower:]' '[:upper:]' <<<"$PROVIDER_FUNC")"
CONFIG_KEY="$PROVIDER_FUNC"

DISPLAY_NAME="$(sget '.display_name')"
[[ -n "$DISPLAY_NAME" ]] || die_spec "display_name is required"
# Constrained here, with its neighbours, for the reason render() states: values are
# substituted LITERALLY and nothing downstream escapes them. display_name is the one
# free-prose key that reaches all three dangerous context classes in the templates —
# a single-quoted printf format (`common.sh.tmpl`), a DOUBLE-quoted `${VAR:?…}` where
# `$(…)` still expands with no quote to break (`conformance-binding.sh.tmpl`), and
# several `#` comment lines a newline would end. One anchored charset closes all three;
# a per-context escape would have to be right in every template forever.
[[ "$DISPLAY_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._/+-]*$ ]] ||
  die_spec "display_name must be letters, digits, spaces, and . _ / + - only, starting alphanumeric (found: $DISPLAY_NAME) — it is substituted literally into generated shell, including a double-quoted expansion where \$(…) would execute"

BASE_PATH="$(jq -r '.api.base_path // ""' <<<"$SPEC_JSON")"
[[ "$BASE_PATH" =~ ^(/[A-Za-z0-9._~-]+)*$ ]] ||
  die_spec "api.base_path must be empty or a slash-led path of [A-Za-z0-9._~-] segments (found: $BASE_PATH)"

HOST_SUFFIX="$(jq -r '.api.host_suffix // ""' <<<"$SPEC_JSON")"
if [[ -n "$HOST_SUFFIX" ]]; then
  [[ "$HOST_SUFFIX" =~ ^\.[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
    die_spec "api.host_suffix must be empty or a dot-led domain suffix (found: $HOST_SUFFIX)"
fi

AUTH_SCHEME="$(jq -r '.api.auth_scheme // ""' <<<"$SPEC_JSON")"
case "$AUTH_SCHEME" in
bearer | token | basic | raw) ;;
*) die_spec "api.auth_scheme must be one of: bearer, token, basic, raw (found: ${AUTH_SCHEME:-none})" ;;
esac

SCOPE_PATTERN="$(jq -r '.api.scope_pattern // "^[A-Za-z0-9][A-Za-z0-9._/-]*$"' <<<"$SPEC_JSON")"
# The pattern is baked into the generated guard, so an unanchored one would silently
# accept a conforming PREFIX of a hostile value — exactly the hole the guard exists to
# close. Refuse it rather than repair it.
[[ "$SCOPE_PATTERN" == ^* && "$SCOPE_PATTERN" == *\$ ]] ||
  die_spec "api.scope_pattern must be anchored at both ends (^…\$) — an unanchored pattern accepts a conforming prefix of a hostile value"

SAMPLE_SCOPE="$(sget '.api.sample_scope')"
[[ -n "$SAMPLE_SCOPE" ]] || die_spec "api.sample_scope is required (it seeds the generated fixtures)"
# TWO checks, for two different jobs, and neither substitutes for the other.
#
# The charset first. sample_scope is substituted LITERALLY into generated shell, and
# `common.test.sh.tmpl` puts it in a DOUBLE-quoted argument — where `$(…)` still
# executes and a `"` closes the string outright. quote_safe() below only refuses a
# single quote, so nothing else stood between the spec and live code in a file whose
# execution is step 1 of this script's own printed "Next:" instructions. This is the
# same treatment display_name got above, for the same reason stated there; sample_scope
# is the one value in this block that never received it, while SAMPLE_HOST, BASE_PATH,
# SAMPLE_ENV, SAMPLE_ID and PROVIDER all did.
#
# Honestly scoped: the spec comes from this skill's own interview, so this is a
# robustness and supply-chain gap (a hand-edited or shared spec file), not a path a
# remote attacker reaches. It is worth closing anyway because the generator's stated
# posture — render() and quote_safe() both say values are inserted literally and
# nothing downstream escapes them — was not actually true of this one key.
#
# The charset is deliberately wider than any shipped provider needs and still excludes
# every shell metacharacter: `owner/repo` (gitea `^[A-Za-z0-9][A-Za-z0-9._-]*/…$`,
# github), `<workspace>/<TEAMKEY>` (linear `^[a-z0-9][a-z0-9-]*/[A-Z][A-Z0-9]*$`), and
# bare jira project keys (`^[A-Za-z][A-Za-z0-9_]*$`) all fit inside it, as does this
# script's own default scope_pattern.
[[ "$SAMPLE_SCOPE" =~ ^[A-Za-z0-9][A-Za-z0-9._~/-]*$ ]] ||
  die_spec "api.sample_scope must be letters, digits, and . _ ~ / - only, starting alphanumeric (found: $SAMPLE_SCOPE) — it is substituted literally into generated shell, including a double-quoted argument where \$(…) would execute and a \" would break out"
# The pattern match second, and it is NOT redundant: the charset says the sample is
# inert, this says the sample is representative. A fixture that fails the provider's
# own scope guard would make the generated adapter fail its own tests on birth.
[[ "$SAMPLE_SCOPE" =~ $SCOPE_PATTERN ]] ||
  die_spec "api.sample_scope '$SAMPLE_SCOPE' does not match api.scope_pattern '$SCOPE_PATTERN'"

SAMPLE_ENV="$(jq -r --arg d "WIT_${PROVIDER_UPPER}_TOKEN" '.api.auth_env_example // $d' <<<"$SPEC_JSON")"
[[ "$SAMPLE_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
  die_spec "api.auth_env_example must be a valid env var name (found: $SAMPLE_ENV)"

if [[ -n "$HOST_SUFFIX" ]]; then
  SAMPLE_HOST="$(jq -r --arg d "example$HOST_SUFFIX" '.api.sample_host // $d' <<<"$SPEC_JSON")"
else
  SAMPLE_HOST="$(jq -r --arg d "tracker.example.com" '.api.sample_host // $d' <<<"$SPEC_JSON")"
fi
[[ "$SAMPLE_HOST" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
  die_spec "api.sample_host must be a bare hostname (found: $SAMPLE_HOST)"
if [[ -n "$HOST_SUFFIX" && "$SAMPLE_HOST" != *"$HOST_SUFFIX" ]]; then
  die_spec "api.sample_host '$SAMPLE_HOST' is not under api.host_suffix '$HOST_SUFFIX' — the generated fixture would fail its own guard"
fi

# Verbs: exactly the adapter surface, every value a boolean. A missing key is not
# defaulted to false — an unlisted verb means the spec was written against a different
# contract revision, and guessing would produce a manifest that lies.
for v in "${ADAPTER_VERBS[@]}"; do
  got="$(jq -r --arg v "$v" '.verbs[$v] | type' <<<"$SPEC_JSON" 2>/dev/null)"
  [[ "$got" == "boolean" ]] ||
    die_spec "verbs[\"$v\"] must be present and boolean (found: ${got:-absent})"
done
extra="$(jq -rc --argjson known "$(printf '%s\n' "${ADAPTER_VERBS[@]}" | jq -R . | jq -sc .)" \
  '[(.verbs // {} | keys[]) | select(. as $k | $known | index($k) | not)]' <<<"$SPEC_JSON")"
[[ "$extra" == "[]" ]] || die_spec "verbs carries keys outside the adapter surface: $extra"

[[ "$(jq -r '.verbs["capabilities"]' <<<"$SPEC_JSON")" == "true" ]] ||
  die_spec "verbs[\"capabilities\"] must be true — the core reads the manifest to decide whether any other verb is attempted"

for k in "${FEATURE_KEYS[@]}"; do
  got="$(jq -r --arg k "$k" '.features[$k] | type' <<<"$SPEC_JSON" 2>/dev/null)"
  [[ "$got" == "boolean" ]] || die_spec "features[\"$k\"] must be present and boolean (found: ${got:-absent})"
done
# A limit is a non-negative integer or null (CONTRACT.md "Capabilities manifest").
# The three values are distinct: n>0 is an enforced ceiling, 0 says the capability is
# unsupported, null says it is supported and unbounded. Presence is checked separately
# from the value, because jq's `//` would collapse an intentional null into "absent".
for k in "${LIMIT_KEYS[@]}"; do
  [[ "$(jq -r --arg k "$k" '.limits | has($k)' <<<"$SPEC_JSON" 2>/dev/null)" == "true" ]] ||
    die_spec "limits[\"$k\"] must be present (a non-negative integer, or null for no provider-enforced ceiling)"
  got="$(jq -r --arg k "$k" '.limits[$k] | if . == null then "ok" elif (type == "number" and . >= 0 and (floor == .)) then "ok" else "bad" end' <<<"$SPEC_JSON" 2>/dev/null)"
  [[ "$got" == "ok" ]] ||
    die_spec "limits[\"$k\"] must be a non-negative integer, or null for no provider-enforced ceiling"
done

[[ "$(jq -r '(.deferrals // []) | if type == "array" and (all(type == "string")) then "ok" else "bad" end' <<<"$SPEC_JSON")" == "ok" ]] ||
  die_spec "deferrals must be an array of strings"

# No spec-supplied value may carry the placeholder delimiter, or rendering would
# substitute into a value and produce something the spec never said.
if grep -q '@@' <<<"$SPEC_JSON"; then
  die_spec "spec contains the placeholder delimiter '@@' — remove it; it is reserved by the templates"
fi

# check_coherence — the manifest is a PROMISE the core routes on: it gates whether a
# verb is attempted at all, and callers branch on features/limits without re-probing.
# A spec that claims a verb while denying the feature it needs (or the reverse) yields
# a manifest that lies in a direction no runtime error will correct. Refuse it here,
# where the fix is one edit, rather than let it fail as a shape error mid-flow.
check_coherence() {
  local bad="" v
  vb() { jq -r --arg v "$1" '.verbs[$v]' <<<"$SPEC_JSON"; }
  ft() { jq -r --arg k "$1" '.features[$k]' <<<"$SPEC_JSON"; }
  lm() { jq -r --arg k "$1" '.limits[$k]' <<<"$SPEC_JSON"; }

  # Leases are the claim protocol; the three verbs stand or fall together, because a
  # claim that cannot be renewed or reclaimed strands the item at TTL expiry.
  for v in claim renew-lease reclaim; do
    if [[ "$(vb "$v")" == "true" && "$(ft leases)" != "true" ]]; then
      bad+=$'\n'"  verbs[\"$v\"]=true but features.leases=false"
    fi
  done
  if [[ "$(ft leases)" == "true" ]]; then
    for v in claim renew-lease reclaim; do
      [[ "$(vb "$v")" == "true" ]] ||
        bad+=$'\n'"  features.leases=true but verbs[\"$v\"]=false (the lease protocol needs all three)"
    done
  fi

  # Sub-item verbs and the sub_items feature likewise describe one capability.
  for v in add-sub-item list-sub-items; do
    if [[ "$(vb "$v")" == "true" && "$(ft sub_items)" != "true" ]]; then
      bad+=$'\n'"  verbs[\"$v\"]=true but features.sub_items=false"
    fi
  done
  # Limits are checked against 0 only. `null` means "supported, no provider-enforced
  # ceiling" and is compatible with the capability being ON — it is what a provider
  # that caps nothing declares instead of inventing a plausible number.
  if [[ "$(ft sub_items)" != "true" && "$(lm sub_items_per_parent)" != "0" ]]; then
    bad+=$'\n'"  features.sub_items=false but limits.sub_items_per_parent=$(lm sub_items_per_parent) (a ceiling on something declared unsupported; use 0)"
  fi
  if [[ "$(ft sub_items)" == "true" && "$(lm sub_items_per_parent)" == "0" ]]; then
    bad+=$'\n'"  features.sub_items=true but limits.sub_items_per_parent=0 (no container could hold a child; use null for no ceiling)"
  fi

  # list-items is what the core derives list-frontier from; without it the seam can
  # enumerate nothing, and its declared ceiling must be a real one.
  if [[ "$(vb list-items)" == "true" && "$(lm list_items_max)" == "0" ]]; then
    bad+=$'\n'"  verbs[\"list-items\"]=true but limits.list_items_max=0 (pagination must have a real ceiling; use null only if the provider truly returns everything)"
  fi
  if [[ "$(vb list-items)" != "true" && "$(lm list_items_max)" != "0" ]]; then
    bad+=$'\n'"  verbs[\"list-items\"]=false but limits.list_items_max=$(lm list_items_max) (use 0)"
  fi

  # link-blocks is how blocked_by edges are written; without cross_repo_edges the
  # ceiling on dependencies is still meaningful, so only the verb/limit pair is checked.
  if [[ "$(vb link-blocks)" == "true" && "$(lm dependencies_per_type)" == "0" ]]; then
    bad+=$'\n'"  verbs[\"link-blocks\"]=true but limits.dependencies_per_type=0 (use null when the provider enforces no ceiling)"
  fi
  if [[ "$(vb link-blocks)" != "true" && "$(lm dependencies_per_type)" != "0" ]]; then
    bad+=$'\n'"  verbs[\"link-blocks\"]=false but limits.dependencies_per_type=$(lm dependencies_per_type) (use 0)"
  fi

  if [[ -n "$bad" ]]; then
    printf 'generate-adapter.sh: incoherent spec — the manifest would misdescribe the adapter:%s\n' "$bad" >&2
    printf '  the capabilities manifest is what the core routes on; declare only what the provider can honestly do\n' >&2
    exit "$EX_SPEC"
  fi
}
check_coherence

# list-items false is coherent but leaves the seam unable to enumerate anything, so
# list-frontier — the verb every work-selection flow calls — can never succeed. That is
# a legitimate consume-only posture (the bundled jira adapter is one), but it is a
# consequence worth naming rather than discovering later.
if [[ "$(jq -r '.verbs["list-items"]' <<<"$SPEC_JSON")" != "true" ]]; then
  printf 'generate-adapter.sh: note: verbs["list-items"]=false, so list-frontier can never succeed for this provider (exit 6 at the capability gate). Intentional for a consume-only adapter.\n' >&2
fi

# --- derived values ---
# (PROVIDER_FUNC / PROVIDER_UPPER / CONFIG_KEY are derived above, where the provider
# name is validated — the auth-env default needs them during validation.)

# The contract version is the SEAM's, never the spec's — see the header.
SEAM_JSON_LIB="$SEAM_DIR/lib/json.sh"
[[ -f "$SEAM_JSON_LIB" ]] ||
  die_usage "seam lib not found: $SEAM_JSON_LIB (set WIT_SEAM_DIR)"
# shellcheck source=../../../tools/work-item-tracker/lib/json.sh
source "$SEAM_JSON_LIB"
SCHEMA_VERSION="$WIT_SCHEMA_VERSION"

# The ID grammar is likewise the seam's, sourced rather than restated — a second
# copy here would drift and the generated fixtures would validate against a grammar
# the engine no longer uses.
SEAM_ID_LIB="$SEAM_DIR/lib/id.sh"
[[ -f "$SEAM_ID_LIB" ]] ||
  die_usage "seam lib not found: $SEAM_ID_LIB (set WIT_SEAM_DIR)"
# shellcheck source=../../../tools/work-item-tracker/lib/id.sh
source "$SEAM_ID_LIB"

# A sample fully-qualified id seeds the generated fixtures. The grammar is
# <provider>:<owner>/<repo>#<n> — exactly two path segments — so it cannot simply be
# composed from host and scope: a scope like `acme/webapp` already carries the whole
# owner/repo pair, while one like `SW2` is a bare project key that needs the host in
# front of it. Default accordingly, and let the spec state it outright when neither
# shape fits.
if [[ "$SAMPLE_SCOPE" == */* && "$SAMPLE_SCOPE" != */*/* ]]; then
  default_sample_id="$PROVIDER:$SAMPLE_SCOPE#12"
else
  default_sample_id="$PROVIDER:$SAMPLE_HOST/$SAMPLE_SCOPE#12"
fi
SAMPLE_ID="$(jq -r --arg d "$default_sample_id" '.api.sample_id // $d' <<<"$SPEC_JSON")"
[[ "$SAMPLE_ID" =~ $WIT_ID_REGEX ]] ||
  die_spec "api.sample_id '$SAMPLE_ID' is not a well-formed id (<provider>:<owner>/<repo>#<n>) — set api.sample_id explicitly when neither host nor scope yields one"
[[ "${BASH_REMATCH[1]}" == "$PROVIDER" ]] ||
  die_spec "api.sample_id '$SAMPLE_ID' names provider '${BASH_REMATCH[1]}', not '$PROVIDER'"
# The generated test asserts the parsed number, so it has to come from the sample id
# rather than a constant.
SAMPLE_ID_NUMBER="${SAMPLE_ID##*#}"

# These are substitution VALUES, so they interpolate $DISPLAY_NAME directly rather than
# carrying an @@…@@ placeholder: render() walks its key list once, and a placeholder
# inserted by a later key is never revisited — it would reach the generated file
# verbatim.
if [[ -n "$HOST_SUFFIX" ]]; then
  HOST_SUFFIX_DOC="\`$HOST_SUFFIX\` (the provider's own domain)"
  HOST_PIN_POSTURE="pinned in code to \`$HOST_SUFFIX\`. A binding naming a host outside it is refused unless \`allow_custom_domain\` is set."
else
  HOST_SUFFIX_DOC="none — $DISPLAY_NAME is self-hosted, so there is no vendor domain to pin against"
  HOST_PIN_POSTURE="**no code-level pin.** $DISPLAY_NAME is self-hosted, so no vendor domain exists to pin against; the host is bare-hostname-validated and HTTPS-only, and the remaining defence is that \`host\` lives in a tracked, review-gated file. Set \`config.$CONFIG_KEY.host_suffix\` in your binding to pin it to your own instance — recommended."
fi

# --- auth scheme rendering ---
# Each scheme differs in exactly four places; keeping them together here beats a
# template per scheme.

AUTH_CONFIG_READ=""
AUTH_CONFIG_REQUIRE=""
AUTH_EXPORT_EXTRA=""
SAMPLE_AUTH_EXTRA=""
SAMPLE_AUTH_EXTRA_DOC=""
AUTH_DOC_ROW=""
# Extra conformance-binding wiring for schemes that need a config value beyond host,
# scope, and the credential env var. Empty for every scheme that does not.
AUTH_CONFORMANCE_REQUIRE=""
AUTH_CONFORMANCE_JQARG=""
CONFORMANCE_AUTH_EXTRA=""

case "$AUTH_SCHEME" in
raw)
  # Some providers take the credential as the bare Authorization value with no scheme
  # word at all — Linear's personal API keys are the case that added this. Modelled as
  # its own scheme rather than as an empty prefix, so the generated header cannot come
  # out with a stray leading space.
  AUTH_DESCRIPTION="a $DISPLAY_NAME API key sent as the bare \`Authorization\` value, with no scheme word"
  AUTH_HEADER_EXPECT="\"Authorization: \$SECRET\""
  AUTH_HELPERS="
# wit_${PROVIDER_FUNC}_auth_header — the Authorization header line. Built here and fed
# to curl through the stdin config, so the credential never reaches argv. This provider
# takes the key as the bare header value: no scheme word, and no leading space.
wit_${PROVIDER_FUNC}_auth_header() {
  local token
  token=\"\$(wit_${PROVIDER_FUNC}_token)\" || exit \"\$?\"
  printf 'Authorization: %s' \"\$token\"
}
"
  ;;
bearer | token)
  scheme_word="Bearer"
  [[ "$AUTH_SCHEME" == "token" ]] && scheme_word="token"
  AUTH_DESCRIPTION="a $DISPLAY_NAME API token sent as \`Authorization: $scheme_word <token>\`"
  AUTH_HEADER_EXPECT="\"Authorization: $scheme_word \$SECRET\""
  AUTH_HELPERS="
# wit_${PROVIDER_FUNC}_auth_header — the Authorization header line. Built here and fed
# to curl through the stdin config, so the credential never reaches argv.
wit_${PROVIDER_FUNC}_auth_header() {
  local token
  token=\"\$(wit_${PROVIDER_FUNC}_token)\" || exit \"\$?\"
  printf 'Authorization: $scheme_word %s' \"\$token\"
}
"
  ;;
basic)
  AUTH_DESCRIPTION="HTTP Basic — the account identity from \`config.$CONFIG_KEY.auth_user\` plus an API token"
  # Basic ENCODES the credential, so the generated test asserts on the encoded header
  # rather than the raw token — otherwise a leak of the encoded form into argv would
  # slip past a case looking only for the plaintext secret.
  AUTH_HEADER_EXPECT="\"Authorization: Basic \$(printf '%s' \"ci@example.invalid:\$SECRET\" | base64 | tr -d '\\n')\""
  AUTH_CONFIG_READ="  WIT_${PROVIDER_UPPER}_AUTH_USER=\"\$(jq -r '.config.$CONFIG_KEY.auth_user // empty' <<<\"\$ejson\")\""
  AUTH_CONFIG_REQUIRE="  [[ -n \"\$WIT_${PROVIDER_UPPER}_AUTH_USER\" ]] || missing+=\" config.$CONFIG_KEY.auth_user\""
  AUTH_EXPORT_EXTRA=" WIT_${PROVIDER_UPPER}_AUTH_USER"
  # The conformance binding takes the account identity from the environment, the same
  # way it takes host and scope. Baked as a literal placeholder it would authenticate
  # as `ci@example.invalid` against a real throwaway instance and 401 with nothing in
  # the generated file saying why — the one required value with no way to supply it.
  # Two different consumers, two different values. The offline test fixture wants a
  # literal (its binding is a temp file that never reaches a real instance), while the
  # conformance binding must take the identity from the environment — so they cannot
  # share one key, and collapsing them emitted `$au` into the test's single-quoted JSON.
  SAMPLE_AUTH_EXTRA=',"auth_user":"ci@example.invalid"'
  # shellcheck disable=SC2016  # $au is a jq variable bound by --arg in the generated
  # binding, not a shell expansion — it must survive into the emitted file unexpanded.
  CONFORMANCE_AUTH_EXTRA=',"auth_user":$au'
  # No apostrophe in this message: bash parses quotes inside ${VAR:?word}, so a lone
  # one opens a quoted region and the generated file stops parsing.
  AUTH_CONFORMANCE_REQUIRE="  local auth_user
  auth_user=\"\${WIT_CONFORMANCE_${PROVIDER_UPPER}_AUTH_USER:?set WIT_CONFORMANCE_${PROVIDER_UPPER}_AUTH_USER to the throwaway account identity for HTTP Basic; the token half stays in the credential env var}\"
"
  # shellcheck disable=SC2016  # emitted verbatim as the generated binding's own jq
  # invocation; $auth_user is that file's local, expanded when IT runs, not here.
  AUTH_CONFORMANCE_JQARG=' --arg au "$auth_user"'
  SAMPLE_AUTH_EXTRA_DOC=",
      \"auth_user\": \"you@example.com\""
  AUTH_DOC_ROW="
| \`auth_user\` | yes | Account identity for HTTP Basic. The token half stays in the env var above. |"
  AUTH_HELPERS="
# wit_${PROVIDER_FUNC}_b64 <text> — single-line base64, portable across coreutils
# (-w0) and BSD/macOS base64 (no -w flag).
wit_${PROVIDER_FUNC}_b64() {
  if printf '%s' \"\$1\" | base64 -w0 2>/dev/null; then return 0; fi
  printf '%s' \"\$1\" | base64 | tr -d '\\n'
}

# wit_${PROVIDER_FUNC}_auth_header — the Authorization header line. Built here and fed
# to curl through the stdin config, so the credential never reaches argv.
wit_${PROVIDER_FUNC}_auth_header() {
  local token
  token=\"\$(wit_${PROVIDER_FUNC}_token)\" || exit \"\$?\"
  printf 'Authorization: Basic %s' \"\$(wit_${PROVIDER_FUNC}_b64 \"\$WIT_${PROVIDER_UPPER}_AUTH_USER:\$token\")\"
}
"
  ;;
*)
  die_spec "unreachable auth scheme: $AUTH_SCHEME"
  ;;
esac

# --- per-verb argument parsing ---
# Contract-fixed and therefore generated in full (CONTRACT.md "Verbs"). Only the
# provider mapping is left to the human.

usage_args_for() {
  case "$1" in
  create-item) printf -- '--title <t> [--body <b>] [--labels a,b] [--type <name>] [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <o>/<r>]' ;;
  get-item) printf -- '<id>' ;;
  claim) printf -- '<id> [--ttl-hours <n>] [--session-id <s>]' ;;
  renew-lease) printf -- '<id> --lease-comment-id <n>' ;;
  reclaim) printf -- '<id>' ;;
  link-blocks) printf -- '<id> --blocked-by <id>' ;;
  add-sub-item) printf -- '<id> --parent <id>' ;;
  list-items) printf -- '[--state open|closed|all] [--repo <o>/<r>]' ;;
  list-sub-items) printf -- '<parent-id> [--state open|closed|all]' ;;
  *) printf -- '' ;;
  esac
}

mapping_note_for() {
  case "$1" in
  create-item) printf 'Create an item and emit the normalized item object. --type is the native type NAME; where the provider has no type registry, echo it back rather than inventing one. --blocked-by is comma-separated and each edge must actually be written, not silently dropped.' ;;
  get-item) printf 'Fetch one item and emit the normalized item object. This verb is AUTHORITATIVE for parent_id — list surfaces may omit parent linkage, this one may not.' ;;
  claim) printf 'Acquire the lease (CONTRACT.md "Lease protocol"): assignee PLUS a lease record. A lost race is exit 7, never a silent overwrite of another holder.' ;;
  renew-lease) printf 'Bump renewed_at on the lease identified by --lease-comment-id. A comment belonging to another item is exit 7.' ;;
  reclaim) printf 'Release a lease whose TTL has expired. Emit reclaimed=false with a reason when the lease is still live — reclaiming a live lease is the one thing this verb must never do.' ;;
  link-blocks) printf 'Write a blocked-by edge. Hitting the provider ceiling is exit 7 with the ceiling named on stderr.' ;;
  add-sub-item) printf 'Link the item as a child of --parent. Depth and per-parent ceilings are exit 7 with the ceiling named.' ;;
  list-items) printf 'Return RAW candidates in the {items:[…]} envelope. Pagination is explicit: fetch up to limits.list_items_max from capabilities.json, NEVER a client default — a silent truncation at some library default makes the frontier lie about what is available.' ;;
  list-sub-items) printf 'Return the RAW children of <parent-id> in the {items:[…]} envelope, each parent_id set to the container. Keep CLOSED children — the closed-children invariant check needs them. A parent with no children is an empty array, never an error.' ;;
  *) printf 'Emit this verb'"'"'s contract result shape.' ;;
  esac
}

# parse_block_for <verb> — the generated argument-parsing code for that verb.
parse_block_for() {
  local verb="$1"
  case "$verb" in
  get-item | reclaim)
    cat <<EOF
ID="\${1:-}"
[[ -n "\$ID" ]] || wit_usage_error "\$USAGE"
shift
[[ \$# -eq 0 ]] || wit_usage_error "unexpected argument: \$1"
wit_require_${PROVIDER_FUNC}_id "\$ID" || wit_usage_error "not a @@PROVIDER@@ item id: \$ID"
EOF
    ;;
  claim)
    cat <<EOF
ID="\${1:-}"
[[ -n "\$ID" ]] || wit_usage_error "\$USAGE"
shift
TTL_HOURS=""
SESSION_ID=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --ttl-hours)
    [[ \$# -ge 2 ]] || wit_usage_error "--ttl-hours needs a value"
    TTL_HOURS="\$2"
    shift 2
    ;;
  --session-id)
    [[ \$# -ge 2 ]] || wit_usage_error "--session-id needs a value"
    SESSION_ID="\$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: \$1" ;;
  esac
done
wit_require_${PROVIDER_FUNC}_id "\$ID" || wit_usage_error "not a @@PROVIDER@@ item id: \$ID"
[[ -z "\$TTL_HOURS" || "\$TTL_HOURS" =~ ^[0-9]+\$ ]] || wit_usage_error "--ttl-hours must be a non-negative integer"
EOF
    ;;
  renew-lease)
    cat <<EOF
ID="\${1:-}"
[[ -n "\$ID" ]] || wit_usage_error "\$USAGE"
shift
LEASE_COMMENT_ID=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --lease-comment-id)
    [[ \$# -ge 2 ]] || wit_usage_error "--lease-comment-id needs a value"
    LEASE_COMMENT_ID="\$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: \$1" ;;
  esac
done
wit_require_${PROVIDER_FUNC}_id "\$ID" || wit_usage_error "not a @@PROVIDER@@ item id: \$ID"
[[ "\$LEASE_COMMENT_ID" =~ ^[0-9]+\$ ]] || wit_usage_error "--lease-comment-id is required and must be numeric"
EOF
    ;;
  link-blocks)
    cat <<EOF
ID="\${1:-}"
[[ -n "\$ID" ]] || wit_usage_error "\$USAGE"
shift
BLOCKED_BY=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --blocked-by)
    [[ \$# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
    BLOCKED_BY="\$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: \$1" ;;
  esac
done
wit_require_${PROVIDER_FUNC}_id "\$ID" || wit_usage_error "not a @@PROVIDER@@ item id: \$ID"
[[ -n "\$BLOCKED_BY" ]] || wit_usage_error "--blocked-by is required"
wit_require_${PROVIDER_FUNC}_id "\$BLOCKED_BY" || wit_usage_error "not a @@PROVIDER@@ item id: \$BLOCKED_BY"
EOF
    ;;
  add-sub-item)
    cat <<EOF
ID="\${1:-}"
[[ -n "\$ID" ]] || wit_usage_error "\$USAGE"
shift
PARENT=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --parent)
    [[ \$# -ge 2 ]] || wit_usage_error "--parent needs a value"
    PARENT="\$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: \$1" ;;
  esac
done
wit_require_${PROVIDER_FUNC}_id "\$ID" || wit_usage_error "not a @@PROVIDER@@ item id: \$ID"
[[ -n "\$PARENT" ]] || wit_usage_error "--parent is required"
wit_require_${PROVIDER_FUNC}_id "\$PARENT" || wit_usage_error "not a @@PROVIDER@@ item id: \$PARENT"
EOF
    ;;
  create-item)
    cat <<EOF
TITLE=""
BODY=""
LABELS=""
TYPE=""
PARENT=""
BLOCKED_BY=""
REPO=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --title)
    [[ \$# -ge 2 ]] || wit_usage_error "--title needs a value"
    TITLE="\$2"
    shift 2
    ;;
  --body)
    [[ \$# -ge 2 ]] || wit_usage_error "--body needs a value"
    BODY="\$2"
    shift 2
    ;;
  --labels)
    [[ \$# -ge 2 ]] || wit_usage_error "--labels needs a value"
    LABELS="\$2"
    shift 2
    ;;
  --type)
    [[ \$# -ge 2 ]] || wit_usage_error "--type needs a value"
    TYPE="\$2"
    shift 2
    ;;
  --parent)
    [[ \$# -ge 2 ]] || wit_usage_error "--parent needs a value"
    PARENT="\$2"
    shift 2
    ;;
  --blocked-by)
    [[ \$# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
    BLOCKED_BY="\$2"
    shift 2
    ;;
  --repo)
    [[ \$# -ge 2 ]] || wit_usage_error "--repo needs a value"
    REPO="\$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: \$1" ;;
  esac
done
[[ -n "\$TITLE" ]] || wit_usage_error "--title is required"
[[ -z "\$PARENT" ]] || wit_require_${PROVIDER_FUNC}_id "\$PARENT" || wit_usage_error "not a @@PROVIDER@@ item id: \$PARENT"
EOF
    ;;
  list-items)
    cat <<EOF
STATE="open"
REPO=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --state)
    [[ \$# -ge 2 ]] || wit_usage_error "--state needs a value"
    STATE="\$2"
    shift 2
    ;;
  --repo)
    [[ \$# -ge 2 ]] || wit_usage_error "--repo needs a value"
    REPO="\$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: \$1" ;;
  esac
done
case "\$STATE" in
open | closed | all) ;;
*) wit_usage_error "--state must be one of: open, closed, all" ;;
esac
EOF
    ;;
  list-sub-items)
    cat <<EOF
PARENT_ID="\${1:-}"
[[ -n "\$PARENT_ID" ]] || wit_usage_error "\$USAGE"
shift
STATE="all"
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --state)
    [[ \$# -ge 2 ]] || wit_usage_error "--state needs a value"
    STATE="\$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: \$1" ;;
  esac
done
wit_require_${PROVIDER_FUNC}_id "\$PARENT_ID" || wit_usage_error "not a @@PROVIDER@@ item id: \$PARENT_ID"
case "\$STATE" in
open | closed | all) ;;
*) wit_usage_error "--state must be one of: open, closed, all" ;;
esac
EOF
    ;;
  *)
    printf '%s\n' "[[ \$# -eq 0 ]] || wit_usage_error \"unexpected argument: \$1\""
    ;;
  esac
}

# --- rendering ---

# render <template-file> [extra-key extra-value]… — substitute every @@KEY@@ with its
# value. Pure bash parameter expansion, so a value is inserted LITERALLY: there is no
# regex, no delimiter to collide with, and nothing a value can do to change which key
# is being replaced. Longest keys first so no key is a prefix of another's match.
# Keys whose value lands inside a SINGLE-QUOTED context in at least one template
# (`readonly …='@@SCOPE_PATTERN@@'`, `jq '.config.@@CONFIG_KEY@@…'`, and so on).
# Derived by grepping the template set for `'…@@KEY@@…'`; re-derive it when a
# template adds a quoted substitution.
QUOTED_CONTEXT_KEYS=" CONFIG_KEY DISPLAY_NAME HOST_SUFFIX PROVIDER PROVIDER_FUNC \
PROVIDER_UPPER SAMPLE_AUTH_EXTRA SAMPLE_HOST SAMPLE_SCOPE SCOPE_PATTERN USAGE_ARGS VERB "

# A single quote is the ONE character that can end such a context; everything after it
# is live shell in the generated file. Every one of these keys is now constrained to a
# safe character class upstream — `scope_pattern` is the last deliberately permissive
# one (it carries a regex, so it cannot be charset-bounded), and a future template may
# quote a key nobody re-audited. So the refusal stays here, at the single choke point
# every value passes through, as the backstop behind the per-key validators rather than
# as the only guard. It is NOT sufficient on its own: it sees only single quotes, so a
# key that reaches a DOUBLE-quoted context needs its own anchored charset upstream —
# which is what `display_name` and `sample_scope` have.
#
# Refuse rather than escape — the doctrine `common.sh.tmpl` states at its own scope
# guard: "an escaping bug is silent, a rejection is loud." No legitimate provider scope,
# host, or identifier contains a single quote.
quote_safe() {
  case "$QUOTED_CONTEXT_KEYS" in
  *" $1 "*)
    [[ "$2" != *\'* ]] ||
      die_spec "$1 must not contain a single quote — it is rendered inside a single-quoted shell string, and a quote there ends the string and makes the rest executable (value: $2)"
    ;;
  # A key that reaches no single-quoted context needs no check here. Spelled out
  # rather than left implicit: the repo's add-default-case rule is on precisely so a
  # silent fallthrough is never mistaken for a considered one.
  *) ;;
  esac
}

# The global substitution set, hoisted out of render() so the sweep below can walk it
# at TOP LEVEL. Longest keys first so no key is a prefix of another's match, and
# PROVIDER last so the `@@PROVIDER@@` tokens inside a caller-supplied PARSE_BLOCK are
# still reached.
readonly RENDER_KEYS=(
  SHEBANG
  PROVIDER_UPPER PROVIDER_FUNC DISPLAY_NAME CONFIG_KEY SCHEMA_VERSION
  HOST_SUFFIX_DOC HOST_PIN_POSTURE HOST_SUFFIX BASE_PATH SCOPE_PATTERN
  SAMPLE_AUTH_EXTRA_DOC SAMPLE_AUTH_EXTRA SAMPLE_SCOPE SAMPLE_HOST SAMPLE_ENV
  SAMPLE_ID_NUMBER SAMPLE_ID
  AUTH_CONFORMANCE_REQUIRE AUTH_CONFORMANCE_JQARG CONFORMANCE_AUTH_EXTRA
  AUTH_DESCRIPTION AUTH_CONFIG_READ AUTH_CONFIG_REQUIRE AUTH_EXPORT_EXTRA
  AUTH_HEADER_EXPECT AUTH_HELPERS AUTH_DOC_ROW PROVIDER
)

# Sweep every global value through quote_safe HERE, at top level, before the first
# emit — because a refusal raised from inside render() cannot stop this script. Every
# render() call is made as `$(render …)`, and `exit` inside a command substitution
# kills only that subshell. Left to render() alone, a spec whose scope_pattern carried
# a single quote printed the refusal once per template and then carried on to write a
# directory of EMPTY, chmod +x scripts, report "Wrote 9 file(s)", print the "Next:"
# instructions, and exit 0 — the loudest refusal in the script, delivered as success.
# render() keeps its own per-value call as the backstop for the caller-supplied pairs,
# which are generator constants; this sweep is the one that can actually abort.
for k in "${RENDER_KEYS[@]}"; do
  quote_safe "$k" "${!k-}"
done

render() {
  local file="$1"
  shift
  local text
  text="$(cat "$file")"
  local k v
  # Caller-supplied pairs first: they are per-file (verb name, tables) and never
  # collide with the global set above.
  while [[ $# -ge 2 ]]; do
    k="$1"
    v="$2"
    shift 2
    quote_safe "$k" "$v"
    text="${text//@@$k@@/$v}"
  done
  for k in "${RENDER_KEYS[@]}"; do
    v="${!k-}"
    quote_safe "$k" "$v"
    text="${text//@@$k@@/$v}"
  done
  printf '%s\n' "$text"
}

ADAPTER_DIR="$OUT_ROOT/tools/work-item-tracker/adapters/$PROVIDER"
BINDINGS_DIR="$OUT_ROOT/tools/work-item-tracker/conformance/bindings"

WRITTEN=()
SKIPPED=()

# emit <path> <content> [executable] — write one generated file, refusing to clobber
# without --force. Refusal is per-file and non-fatal: a regeneration that would only
# overwrite files the consumer has since edited should report exactly which, not
# abort halfway through with some files already replaced.
emit() {
  local path="$1" content="$2" exec_bit="${3:-}"
  if [[ -e "$path" && $FORCE -eq 0 ]]; then
    SKIPPED+=("$path")
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    WRITTEN+=("$path")
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  # Exactly one trailing newline: render()'s output goes through a command
  # substitution, which strips them, and a file with none fails both the repo's
  # editorconfig check and shfmt.
  printf '%s\n' "${content%$'\n'}" >"$path"
  [[ -n "$exec_bit" ]] && chmod +x "$path"
  WRITTEN+=("$path")
}

# capabilities.json — stamped with the SEAM's contract version, not the spec's.
MANIFEST="$(jq -S --arg sv "$SCHEMA_VERSION" --arg p "$PROVIDER" \
  '{schema_version: $sv, provider: $p, verbs: .verbs, features: .features, limits: .limits}' \
  <<<"$SPEC_JSON")"
emit "$ADAPTER_DIR/capabilities.json" "$MANIFEST"

emit "$ADAPTER_DIR/common.sh" "$(render "$TEMPLATE_DIR/common.sh.tmpl")"
emit "$ADAPTER_DIR/common.test.sh" "$(render "$TEMPLATE_DIR/common.test.sh.tmpl")" exec
emit "$ADAPTER_DIR/capabilities.sh" "$(render "$TEMPLATE_DIR/capabilities.sh.tmpl")" exec
emit "$ADAPTER_DIR/capabilities.test.sh" "$(render "$TEMPLATE_DIR/capabilities.test.sh.tmpl")" exec

for v in "${ADAPTER_VERBS[@]}"; do
  [[ "$v" == "capabilities" ]] && continue
  [[ "$(jq -r --arg v "$v" '.verbs[$v]' <<<"$SPEC_JSON")" == "true" ]] || continue
  emit "$ADAPTER_DIR/$v.sh" "$(render "$TEMPLATE_DIR/verb.sh.tmpl" \
    VERB "$v" \
    USAGE_ARGS "$(usage_args_for "$v")" \
    MAPPING_NOTE "$(mapping_note_for "$v")" \
    PARSE_BLOCK "$(parse_block_for "$v")")" exec
done

emit "$BINDINGS_DIR/$PROVIDER.sh" "$(render "$TEMPLATE_DIR/conformance-binding.sh.tmpl")"

# README: the verb table and the deferrals are derived from the spec, so the document
# cannot drift from the manifest it describes.
VERB_TABLE="| Verb | Declared | Status |"$'\n'"|---|---|---|"
for v in "${ADAPTER_VERBS[@]}"; do
  declared="$(jq -r --arg v "$v" '.verbs[$v]' <<<"$SPEC_JSON")"
  if [[ "$v" == "capabilities" ]]; then
    status="generated, complete"
  elif [[ "$declared" == "true" ]]; then
    status="scaffold — provider mapping to write"
  else
    status="exit \`6\` at the capability gate"
  fi
  VERB_TABLE+=$'\n'"| \`$v\` | \`$declared\` | $status |"
done

DEFERRALS_SECTION=""
if [[ "$(jq -r '(.deferrals // []) | length' <<<"$SPEC_JSON")" != "0" ]]; then
  DEFERRALS_SECTION="## Recorded deferrals"$'\n\n'"Facts this adapter was built without, each carrying a config override so the adapter does not depend on guessing them. Settle them against a live instance and record the answers here."$'\n'
  while IFS= read -r d; do
    DEFERRALS_SECTION+=$'\n'"- $d"
  done < <(jq -r '(.deferrals // [])[]' <<<"$SPEC_JSON")
  DEFERRALS_SECTION+=$'\n'
fi

emit "$ADAPTER_DIR/README.md" "$(render "$TEMPLATE_DIR/README.md.tmpl" \
  VERB_TABLE "$VERB_TABLE" \
  DEFERRALS_SECTION "$DEFERRALS_SECTION")"

# --- report ---

if [[ ${#WRITTEN[@]} -gt 0 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    printf 'Would write %d file(s):\n' "${#WRITTEN[@]}"
  else
    printf 'Wrote %d file(s):\n' "${#WRITTEN[@]}"
  fi
  printf '  %s\n' "${WRITTEN[@]}"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  printf 'Kept %d existing file(s) (re-run with --force to overwrite):\n' "${#SKIPPED[@]}" >&2
  printf '  %s\n' "${SKIPPED[@]}" >&2
fi

cat >&2 <<EOF

Next:
  1. bash $ADAPTER_DIR/common.test.sh
     The generated guards, already real and passing. Run them before editing anything.
  2. Fill in each PROVIDER MAPPING block, verb by verb, against your live instance.
     A verb you cannot map honestly gets verbs["<verb>"]=false in capabilities.json,
     not a partial implementation.
  3. bash $OUT_ROOT/tools/work-item-tracker/conformance/run-conformance.sh --binding $PROVIDER
     Needs a throwaway target — see $BINDINGS_DIR/$PROVIDER.sh.
EOF
