#!/usr/bin/env bash
# Tests for omarchy-jira-auth.
#
# Every external command the script touches is stubbed inside a sandbox that
# takes over PATH, so no real network call is made and no real keyring entry is
# written. The stubs record every argument vector they are invoked with, which
# is what lets the last test assert the property that matters most: the API
# token never reaches a command line, where any local process could read it out
# of ps.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/omarchy-jira-auth"

TOKEN="TESTTOKENvalue1234567890"
EMAIL="probe@example.com"
SITE="example.atlassian.net"
CLOUD_ID="11111111-2222-3333-4444-555555555555"
API_BASE="https://api.atlassian.com/ex/jira/$CLOUD_ID"

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  [[ $haystack == *"$needle"* ]] || fail "$label (expected to find \"$needle\")"
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  [[ $haystack != *"$needle"* ]] || fail "$label (unexpectedly found \"$needle\")"
}

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

export STUB_DIR="$sandbox/state"
mkdir -p "$STUB_DIR" "$sandbox/bin"

# Keep the interpreters the stubs and the script need, and nothing else, so an
# accidental call to a real binary fails loudly instead of silently working.
for tool in bash cat rm mktemp grep sed jq; do
  path=$(command -v "$tool" 2>/dev/null) && ln -sf "$path" "$sandbox/bin/$(basename "$tool")"
done

cat >"$sandbox/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$STUB_DIR/calls"
config=""
output=""
url=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
  --config) config="${args[i + 1]}" ;;
  --output) output="${args[i + 1]}" ;;
  --url) url="${args[i + 1]}" ;;
  esac
done
# Recording what curl was actually given as credentials proves the token
# travelled through the config channel rather than through argv.
if [[ -n $config && -r $config ]]; then
  cat "$config" >>"$STUB_DIR/creds"
fi

# The public tenant lookup carries no credential and answers before any
# authentication happens, so it is stubbed separately from the API calls.
if [[ $url == *"/_edge/tenant_info" ]]; then
  if [[ ${TENANT_STUB_FAIL:-0} == 1 ]]; then
    echo "curl: (6) Could not resolve host" >&2
    exit 6
  fi
  printf '{"cloudId":"%s"}' "${TENANT_STUB_CLOUD_ID:-11111111-2222-3333-4444-555555555555}"
  exit 0
fi

if [[ ${CURL_STUB_FAIL:-0} == 1 ]]; then
  echo "curl: (6) Could not resolve host" >&2
  exit 6
fi
if [[ -n $output ]]; then
  printf '%s' "${CURL_STUB_BODY:-{\"displayName\":\"Test User\",\"accountId\":\"abc\"}}" >"$output"
fi
if [[ $url == https://api.atlassian.com/* ]]; then
  printf '%s' "${CURL_STUB_CODE_API:-${CURL_STUB_CODE:-200}}"
else
  printf '%s' "${CURL_STUB_CODE_SITE:-${CURL_STUB_CODE:-200}}"
fi
STUB

cat >"$sandbox/bin/secret-tool" <<'STUB'
#!/usr/bin/env bash
printf 'secret-tool %s\n' "$*" >>"$STUB_DIR/calls"
action="${1:-}"
shift || true
case "$action" in
store)
  cat >"$STUB_DIR/vault"
  label=""
  attrs=()
  while (($# > 0)); do
    case "$1" in
    --label=*)
      label="${1#--label=}"
      shift
      ;;
    --label)
      label="$2"
      shift 2
      ;;
    *)
      attrs+=("$1" "$2")
      shift 2
      ;;
    esac
  done
  {
    printf '[/org/freedesktop/secrets/collection/login/1]\n'
    printf 'label = %s\n' "$label"
    for ((i = 0; i < ${#attrs[@]}; i += 2)); do
      printf 'attribute.%s = %s\n' "${attrs[i]}" "${attrs[i + 1]}"
    done
  } >"$STUB_DIR/vault-attrs"
  ;;
lookup)
  [[ -s $STUB_DIR/vault ]] || exit 1
  cat "$STUB_DIR/vault"
  ;;
search)
  [[ -s $STUB_DIR/vault-attrs ]] || exit 1
  cat "$STUB_DIR/vault-attrs"
  ;;
clear)
  rm -f "$STUB_DIR/vault" "$STUB_DIR/vault-attrs"
  ;;
*)
  exit 2
  ;;
esac
STUB

chmod +x "$sandbox/bin/curl" "$sandbox/bin/secret-tool"

reset_state() {
  rm -f "$STUB_DIR/calls" "$STUB_DIR/creds" "$STUB_DIR/vault" "$STUB_DIR/vault-attrs"
  : >"$STUB_DIR/calls"
  : >"$STUB_DIR/creds"
}

run_setup() {
  # Feeds the three interactive answers on stdin.
  printf '%s\n%s\n%s\n' "$1" "$2" "$3" | PATH="$sandbox/bin" "$SCRIPT" 2>&1
}

run_flag() {
  PATH="$sandbox/bin" "$SCRIPT" "$@" 2>&1
}

# ---- Syntax and help

bash -n "$SCRIPT" || fail "script does not parse"
PATH="$sandbox/bin" "$SCRIPT" --help >/dev/null || fail "--help failed"

# ---- A valid token is stored, with the site and email as attributes

reset_state
output=$(run_setup "$SITE" "$EMAIL" "$TOKEN") || fail "setup failed on a valid token: $output"
[[ $(cat "$STUB_DIR/vault") == "$TOKEN" ]] || fail "the stored secret is not the token"
attrs=$(cat "$STUB_DIR/vault-attrs")
assert_contains "$attrs" "attribute.service = omarchy-jira" "service attribute missing"
assert_contains "$attrs" "attribute.account = $EMAIL" "account attribute missing"
assert_contains "$attrs" "attribute.site = $SITE" "site attribute missing"

# ---- Scoped tokens only work against api.atlassian.com with a cloud id, so
#      that is the base the setup must discover, verify, and store.

assert_contains "$(cat "$STUB_DIR/calls")" "https://$SITE/_edge/tenant_info" "the cloud id was never looked up"
assert_contains "$(cat "$STUB_DIR/calls")" "$API_BASE/rest/api/3/myself" "validation did not go through api.atlassian.com"
assert_contains "$attrs" "attribute.base = $API_BASE" "the working base URL was not stored"

# The token has to reach curl somehow. It must be through the config channel.
assert_contains "$(cat "$STUB_DIR/creds")" "$TOKEN" "the token never reached curl through --config"

# ---- The token never appears in a command line

assert_not_contains "$(cat "$STUB_DIR/calls")" "$TOKEN" "the token leaked into a command line"

# ---- A site typed as a full URL is normalised

reset_state
output=$(run_setup "https://$SITE/" "$EMAIL" "$TOKEN") || fail "setup failed on a URL-shaped site: $output"
assert_contains "$(cat "$STUB_DIR/vault-attrs")" "attribute.site = $SITE" "site was not normalised"
assert_contains "$(cat "$STUB_DIR/calls")" "https://$SITE/_edge/tenant_info" "the normalised host was not used for the tenant lookup"
assert_not_contains "$(cat "$STUB_DIR/calls")" "https://https://" "a URL-shaped answer produced a doubled scheme"

# ---- A classic unscoped token is rejected by api.atlassian.com but accepted by
#      the site itself, and must still connect. Without this fallback the plugin
#      would only work for people holding the newer scoped tokens.

reset_state
output=$(CURL_STUB_CODE_API=401 CURL_STUB_CODE_SITE=200 run_setup "$SITE" "$EMAIL" "$TOKEN") ||
  fail "setup failed for a classic token: $output"
assert_contains "$(cat "$STUB_DIR/vault-attrs")" "attribute.base = https://$SITE" "the classic token did not fall back to the site base"

# ---- When the tenant lookup fails there is no cloud id, and the site base is
#      the only candidate left

reset_state
output=$(TENANT_STUB_FAIL=1 run_setup "$SITE" "$EMAIL" "$TOKEN") ||
  fail "setup failed when the tenant lookup was unavailable: $output"
assert_contains "$(cat "$STUB_DIR/vault-attrs")" "attribute.base = https://$SITE" "no fallback base after a failed tenant lookup"

# ---- 401 everywhere stores nothing

reset_state
if CURL_STUB_CODE=401 run_setup "$SITE" "$EMAIL" "$TOKEN" >/dev/null 2>&1; then
  fail "setup succeeded despite a 401"
fi
[[ ! -s "$STUB_DIR/vault" ]] || fail "a rejected token was stored anyway"

# ---- An unreachable host stores nothing

reset_state
if CURL_STUB_FAIL=1 run_setup "$SITE" "$EMAIL" "$TOKEN" >/dev/null 2>&1; then
  fail "setup succeeded despite a transport failure"
fi
[[ ! -s "$STUB_DIR/vault" ]] || fail "a token was stored despite a transport failure"

# ---- Empty answers are refused

reset_state
if run_setup "" "$EMAIL" "$TOKEN" >/dev/null 2>&1; then fail "an empty site was accepted"; fi
reset_state
if run_setup "$SITE" "" "$TOKEN" >/dev/null 2>&1; then fail "an empty email was accepted"; fi
reset_state
if run_setup "$SITE" "$EMAIL" "" >/dev/null 2>&1; then fail "an empty token was accepted"; fi

# ---- --status with nothing connected

reset_state
if run_flag --status >/dev/null 2>&1; then
  fail "--status succeeded with no credential stored"
fi
output=$(run_flag --status 2>&1 || true)
assert_contains "$output" "omarchy-jira-auth" "--status does not point at the setup command"

# ---- --status with a credential, and never the token

reset_state
run_setup "$SITE" "$EMAIL" "$TOKEN" >/dev/null || fail "setup failed before the status check"
output=$(run_flag --status) || fail "--status failed with a credential stored"
assert_contains "$output" "$SITE" "--status does not show the site"
assert_contains "$output" "$EMAIL" "--status does not show the account"
assert_not_contains "$output" "$TOKEN" "--status printed the token"

# ---- --clear removes the entry

run_flag --clear >/dev/null || fail "--clear failed"
[[ ! -s "$STUB_DIR/vault" ]] || fail "--clear left the secret behind"
assert_contains "$(cat "$STUB_DIR/calls")" "secret-tool clear service omarchy-jira" "--clear did not call secret-tool clear"

# ---- Result

if ((failures > 0)); then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "auth-test: all checks passed"
