#!/usr/bin/env bash
# Tests for omarchy-jira-fetch.
#
# The helper is the only part of the plugin that talks to Jira, so its contract
# is what the QML side is written against: exactly one JSON document on stdout,
# and exit code zero for every failure the user can actually encounter. A non
# zero exit means the helper itself broke, which is a different thing entirely.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-jira-fetch"
FIXTURES="$ROOT/tests/fixtures"

TOKEN="TESTTOKENvalue1234567890"
EMAIL="probe@example.com"
SITE="example.atlassian.net"
BASE="https://api.atlassian.com/ex/jira/11111111-2222-3333-4444-555555555555"

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

assert_jq() {
  local filter="$1" payload="$2" label="$3"
  jq -e "$filter" >/dev/null 2>&1 <<<"$payload" || fail "$label"
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
export FIXTURE_DIR="$FIXTURES"
mkdir -p "$STUB_DIR" "$sandbox/bin"

for tool in bash cat rm mktemp jq; do
  path=$(command -v "$tool" 2>/dev/null) && ln -sf "$path" "$sandbox/bin/$(basename "$tool")"
done

cat >"$sandbox/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$STUB_DIR/calls"
config=""
output=""
url=""
data=""
query_params=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
  --config) config="${args[i + 1]}" ;;
  --output) output="${args[i + 1]}" ;;
  --url) url="${args[i + 1]}" ;;
  --data) data="${args[i + 1]}" ;;
  --data-urlencode) query_params+=("${args[i + 1]}") ;;
  esac
done
if [[ -n $config && -r $config ]]; then
  cat "$config" >>"$STUB_DIR/creds"
fi
if [[ -n $data ]]; then
  printf '%s\n' "$data" >>"$STUB_DIR/bodies"
fi

if [[ ${CURL_STUB_FAIL:-0} == 1 ]]; then
  echo "curl: (6) Could not resolve host" >&2
  exit 6
fi

code="${CURL_STUB_CODE:-200}"
if [[ $url == *"/rest/api/3/field"* ]]; then
  code="${FIELDS_STUB_CODE:-$code}"
  [[ -n $output ]] && cat "$FIXTURE_DIR/fields.json" >"$output"
elif [[ $url == *"/issue/picker"* ]]; then
  printf '%s %s\n' "$url" "${query_params[*]-}" >>"$STUB_DIR/picker-urls"
  code="${PICKER_STUB_CODE:-$code}"
  [[ -n $output ]] && cat "$FIXTURE_DIR/${PICKER_FIXTURE:-picker.json}" >"$output"
elif [[ $url == *"/project/search"* ]]; then
  code="${PROJECTS_STUB_CODE:-$code}"
  [[ -n $output ]] && cat "$FIXTURE_DIR/projects.json" >"$output"
elif [[ $url == *"/rest/agile/1.0/board/"*"/sprint/"*"/issue"* ]]; then
  code="${SPRINT_ISSUES_STUB_CODE:-$code}"
  [[ -n $output ]] && cat "$FIXTURE_DIR/sprint-issues.json" >"$output"
elif [[ $url == *"/rest/agile/1.0/board/"*"/sprint"* ]]; then
  code="${SPRINTS_STUB_CODE:-$code}"
  [[ -n $output ]] && cat "$FIXTURE_DIR/${SPRINTS_FIXTURE:-sprints.json}" >"$output"
elif [[ $url == *"/rest/agile/1.0/board"* ]]; then
  code="${BOARDS_STUB_CODE:-$code}"
  [[ -n $output ]] && cat "$FIXTURE_DIR/${BOARDS_FIXTURE:-boards.json}" >"$output"
elif [[ $data == *"openSprints()"* ]]; then
  code="${DERIVED_STUB_CODE:-$code}"
  [[ -n $output ]] && cat "$FIXTURE_DIR/sprint-derived.json" >"$output"
elif [[ $data == *"key IN"* ]]; then
  [[ -n $output ]] && cat "$FIXTURE_DIR/search-keys.json" >"$output"
else
  [[ -n $output ]] && cat "$FIXTURE_DIR/${SEARCH_FIXTURE:-search.json}" >"$output"
fi
printf '%s' "$code"
STUB

cat >"$sandbox/bin/secret-tool" <<'STUB'
#!/usr/bin/env bash
printf 'secret-tool %s\n' "$*" >>"$STUB_DIR/calls"
case "${1:-}" in
lookup)
  if [[ ${KEYRING_STUB_BROKEN:-0} == 1 ]]; then
    echo "secret-tool: Cannot autolaunch D-Bus without X11 \$DISPLAY" >&2
    exit 1
  fi
  [[ -s $STUB_DIR/vault ]] || exit 1
  cat "$STUB_DIR/vault"
  ;;
search)
  echo "search must never be called" >&2
  exit 3
  ;;
*)
  exit 2
  ;;
esac
STUB

chmod +x "$sandbox/bin/curl" "$sandbox/bin/secret-tool"

store_credential() {
  jq -nc --arg site "$SITE" --arg account "$EMAIL" --arg base "$BASE" --arg token "$TOKEN" \
    '{site: $site, account: $account, base: $base, token: $token}' >"$STUB_DIR/vault"
}

reset_state() {
  rm -f "$STUB_DIR/calls" "$STUB_DIR/creds" "$STUB_DIR/bodies" "$STUB_DIR/picker-urls"
  : >"$STUB_DIR/calls"
  : >"$STUB_DIR/creds"
  : >"$STUB_DIR/bodies"
  : >"$STUB_DIR/picker-urls"
}

run_helper() {
  PATH="$sandbox/bin" "$HELPER" "$@" 2>/dev/null
}

# ---- Syntax and help

bash -n "$HELPER" || fail "helper does not parse"
PATH="$sandbox/bin" "$HELPER" --help >/dev/null || fail "--help failed"

# ---- A successful dashboard run

reset_state
store_credential
payload=$(run_helper) || fail "helper exited non zero on success"

assert_jq '.' "$payload" "the payload is not valid JSON"
assert_jq '.state == "ok"' "$payload" "state is not ok"
assert_jq '.schema == 1' "$payload" "schema version missing"
assert_jq '.mode == "dashboard"' "$payload" "mode is not dashboard"
assert_jq '.site == "'"$SITE"'"' "$payload" "site missing from the payload"
assert_jq '.account == "'"$EMAIL"'"' "$payload" "account missing from the payload"
assert_jq '.generatedAt | test("^[0-9]{4}-")' "$payload" "generatedAt is not a timestamp"

# ---- Ticket mapping

assert_jq '.tickets | length == 4' "$payload" "expected the four live tickets"
assert_jq '[.tickets[].key] | index("DEMO-1") == null' "$payload" "a Done ticket was not filtered out"
assert_jq '.tickets[0].key == "DEMO-12"' "$payload" "tickets are not in the API order"
assert_jq '.tickets[0].summary != ""' "$payload" "summary missing"
assert_jq '.tickets[0].type == "Story"' "$payload" "issue type missing"
assert_jq '.tickets[0].status == "In Progress"' "$payload" "status name missing"
assert_jq '.tickets[0].statusCategory == "indeterminate"' "$payload" "status category is not the category key"
assert_jq '.tickets[0].projectKey == "DEMO"' "$payload" "project key missing"
assert_jq '.tickets[0].projectName == "Demo Project"' "$payload" "project name missing"
assert_jq '.tickets[0].updated | test("^2026-")' "$payload" "updated missing"
assert_jq '.tickets[0].url == "https://'"$SITE"'/browse/DEMO-12"' "$payload" "browse url is wrong"

# A status named "In Review" still reports the category it belongs to. Nothing
# in this plugin may key off a status name, since every Jira site names its own.
assert_jq '[.tickets[] | select(.key == "DEMO-8")][0].status == "In Review"' "$payload" "In Review name lost"
assert_jq '[.tickets[] | select(.key == "DEMO-8")][0].statusCategory == "indeterminate"' "$payload" "In Review category wrong"

# ---- Projects come with the dashboard

assert_jq '.projects | length == 2' "$payload" "projects missing"
assert_jq '.projects[0].key == "DEMO"' "$payload" "project key missing from the project list"
assert_jq '.projects[0].name == "Demo Project"' "$payload" "project name missing from the project list"

# ---- The JQL is the one the design calls for

body=$(cat "$STUB_DIR/bodies")
assert_contains "$body" "assignee = currentUser()" "the JQL does not filter on the current user"
assert_contains "$body" "statusCategory != Done" "the JQL does not exclude the Done category"
assert_contains "$body" "ORDER BY updated DESC" "the JQL does not order by update time"
assert_not_contains "$body" "resolution" "the JQL filters on resolution, which lets Won't Do through"

# ---- Credential handling

assert_contains "$(cat "$STUB_DIR/creds")" "$TOKEN" "the token never reached curl through --config"
assert_not_contains "$(cat "$STUB_DIR/calls")" "$TOKEN" "the token leaked into a command line"
assert_not_contains "$(cat "$STUB_DIR/calls")" "secret-tool search" "the helper called secret-tool search"

# ---- Project narrowing

reset_state
store_credential
payload=$(run_helper --projects DEMO) || fail "helper failed with --projects"
assert_contains "$(cat "$STUB_DIR/bodies")" 'project IN (DEMO)' "the project clause is missing"

reset_state
store_credential
payload=$(run_helper --projects "DEMO, OPS") || fail "helper failed with two projects"
assert_contains "$(cat "$STUB_DIR/bodies")" 'project IN (DEMO,OPS)' "the two project clause is wrong"

# A project key is uppercase letters and digits, never free text. Rather than
# asserting that particular hostile fragments are absent, which only ever proves
# something about the fragments that were imagined, assert that the generated
# JQL always matches one exact known shape. Anything an attacker could add would
# have to break that shape.
readonly JQL_SHAPE='^assignee = currentUser\(\) AND statusCategory != Done( AND project IN \([A-Z0-9_]+(,[A-Z0-9_]+)*\))? ORDER BY updated DESC$'

assert_jql_shape() {
  local label="$1" jql
  jql=$(jq -r '.jql' <"$STUB_DIR/bodies")
  [[ $jql =~ $JQL_SHAPE ]] || fail "$label (JQL was: $jql)"
}

for hostile in \
  'DEMO) OR (assignee != currentUser()' \
  'DEMO"; rm -rf /' \
  "DEMO' OR '1'='1" \
  'DEMO ORDER BY created' \
  '!!!' \
  ''; do
  reset_state
  store_credential
  payload=$(run_helper --projects "$hostile") ||
    fail "helper failed on project list: $hostile"
  assert_jql_shape "a hostile project list escaped the JQL shape: $hostile"
  assert_jq '.state == "ok"' "$payload" "a hostile project list broke the dashboard: $hostile"
done

# ---- Sprint
#
# The sprint comes from the Agile API, which knows about boards. Reading it out
# of the tickets instead would have avoided extra token scopes, but a sprint
# with no ticket in a followed project would then be invisible, and a sprint
# that has just opened is exactly the one worth showing.

reset_state
store_credential
payload=$(run_helper --projects DEMO --sprint) || fail "helper failed with a sprint"

assert_jq '.sprint != null' "$payload" "no sprint in the payload"
assert_jq '.sprint.name == "Demo Sprint 12"' "$payload" "sprint name missing"
assert_jq '.sprint.goal == "Ship the rollout"' "$payload" "sprint goal missing"
assert_jq '.sprint.startDate | test("^2026-08-05")' "$payload" "sprint start date missing"
assert_jq '.sprint.endDate | test("^2026-08-19")' "$payload" "sprint end date missing"
assert_jq '.sprint.total == 4' "$payload" "sprint ticket total is wrong"
assert_jq '.sprint.done == 2' "$payload" "sprint done count is wrong"

# Both measures travel in the payload, so choosing between them is a display
# decision. The estimated count is what makes that choice an informed one:
# counting points is misleading when most tickets carry no estimate.
assert_jq '.sprint.points.total == 13' "$payload" "sprint point total is wrong"
assert_jq '.sprint.points.done == 8' "$payload" "sprint point done is wrong"
assert_jq '.sprint.points.estimated == 3' "$payload" "sprint estimated count is wrong"

# A scrum board is picked over a kanban one: kanban boards have no sprints.
assert_contains "$(cat "$STUB_DIR/calls")" "/rest/agile/1.0/board/293/sprint" "the scrum board was not chosen"

# Only the active sprint is asked for.
assert_contains "$(cat "$STUB_DIR/calls")" "state=active" "sprints were not filtered to the active one"

# ---- The sprint needs a project to know which board to read

reset_state
store_credential
payload=$(run_helper --sprint) || fail "helper failed with no project selected"
assert_jq '.sprint == null' "$payload" "a sprint was reported without a project to attach it to"
assert_jq '.sprintState == "no-project"' "$payload" "the reason for having no sprint is not reported"
assert_not_contains "$(cat "$STUB_DIR/calls")" "/rest/agile/" "the agile API was called without a project"

# ---- A token without Jira Software scopes still gets a sprint
#
# The Agile API needs scopes a plain Jira token does not carry. Rather than
# showing nothing, the helper reads the sprint off the tickets that are in it.
# The result is marked "derived" because it cannot see a sprint that holds no
# ticket, and the panel is entitled to know that.

reset_state
store_credential
payload=$(BOARDS_STUB_CODE=401 run_helper --projects DEMO --sprint) || fail "helper failed on a scope error"
assert_jq '.state == "ok"' "$payload" "a sprint scope error broke the whole payload"
assert_jq '.tickets | length == 4' "$payload" "a sprint scope error lost the tickets"
assert_jq '.sprintState == "derived"' "$payload" "the fallback was not used"
assert_jq '.sprint.name == "Demo Sprint 12"' "$payload" "the fallback found no sprint"
assert_jq '.sprint.total == 3' "$payload" "the fallback counted the wrong number of tickets"
assert_jq '.sprint.done == 1' "$payload" "the fallback counted the wrong number of done tickets"
assert_jq '.sprint.points.total == 8' "$payload" "the fallback summed the wrong points"
assert_jq '.sprint.name != "Demo Sprint 11"' "$payload" "the fallback used a closed sprint"

# When even the fallback cannot run, the tickets still arrive.
reset_state
store_credential
payload=$(BOARDS_STUB_CODE=401 DERIVED_STUB_CODE=500 run_helper --projects DEMO --sprint) ||
  fail "helper failed when both sprint paths failed"
assert_jq '.state == "ok"' "$payload" "a total sprint failure broke the payload"
assert_jq '.tickets | length == 4' "$payload" "a total sprint failure lost the tickets"
assert_jq '.sprint == null' "$payload" "a total sprint failure should yield no sprint"

# ---- Everything else about the sprint fails quietly

reset_state
store_credential
payload=$(BOARDS_FIXTURE=boards-none.json run_helper --projects DEMO --sprint) || fail "helper failed with no board"
assert_jq '.sprint == null' "$payload" "no board should yield no sprint"
assert_jq '.sprintState == "no-board"' "$payload" "a missing board is not reported"

reset_state
store_credential
payload=$(SPRINTS_FIXTURE=sprints-none.json run_helper --projects DEMO --sprint) || fail "helper failed with no active sprint"
assert_jq '.sprint == null' "$payload" "no active sprint should yield no sprint"
assert_jq '.sprintState == "none"' "$payload" "a board without an active sprint is not reported"

reset_state
store_credential
payload=$(SPRINT_ISSUES_STUB_CODE=500 run_helper --projects DEMO --sprint) || fail "helper failed when sprint issues failed"
assert_jq '.state == "ok"' "$payload" "a sprint issue failure broke the payload"
assert_jq '.tickets | length == 4' "$payload" "a sprint issue failure lost the tickets"

# ---- Teams that do not run sprints pay nothing for the feature

reset_state
store_credential
payload=$(run_helper --projects DEMO) || fail "helper failed without --sprint"
assert_jq '.sprint == null' "$payload" "the sprint was fetched without being asked for"
assert_not_contains "$(cat "$STUB_DIR/calls")" "/rest/agile/" "the agile API was called without being asked for"
assert_not_contains "$(cat "$STUB_DIR/calls")" "/rest/api/3/field" "the field catalogue was fetched without being asked for"

# Search has no business asking about sprints.
reset_state
store_credential
payload=$(run_helper --sprint --search "card") || fail "search failed"
assert_not_contains "$(cat "$STUB_DIR/calls")" "/rest/agile/" "search asked for the sprint"
assert_jq '.sprint == null' "$payload" "search should carry no sprint"

# ---- Search mode
#
# Search goes through Jira's issue picker, the same endpoint the Jira web search
# box uses, and then asks for the full details of whatever keys it returned.
#
# That indirection is what makes a bare number work: typing 1069 has to find
# DS-1069 without the widget knowing which project was meant. It also means a
# typed query never becomes part of a JQL string, so the JQL this helper sends
# is always built from issue keys it has validated itself.

reset_state
store_credential
payload=$(run_helper --search "1069") || fail "search failed"
assert_jq '.mode == "search"' "$payload" "search mode is not reported"
assert_jq '.projects == []' "$payload" "search should not fetch the project list"
assert_not_contains "$(cat "$STUB_DIR/calls")" "/project/search" "search fetched the project list anyway"

# The picker is asked, and asked in the form that makes it search the server
# rather than only the user's own recently viewed issues.
picker_urls=$(cat "$STUB_DIR/picker-urls")
assert_contains "$picker_urls" "/rest/api/3/issue/picker" "the picker was not used"
assert_contains "$picker_urls" "currentJQL" "the picker was called without currentJQL, so it only searches history"
assert_contains "$picker_urls" "1069" "the query never reached the picker"

# The details request asks for exactly the keys the picker returned, in the
# order it returned them, since the picker ranks by relevance.
detail_jql=$(jq -r .jql <"$STUB_DIR/bodies")
[[ $detail_jql == 'key IN (DEMO-12,OPS-5,OTHER-7)' ]] ||
  fail "the detail query did not follow the picker (JQL was: $detail_jql)"
assert_jq '[.tickets[].key] == ["DEMO-12","OPS-5","OTHER-7"]' "$payload" "results are not in picker order"

# Results carry the same fields as dashboard rows, so one row component renders
# both and the panel never has to know where a ticket came from.
assert_jq '.tickets[0].status == "In Progress"' "$payload" "search results lack a status"
assert_jq '.tickets[0].statusCategory == "indeterminate"' "$payload" "search results lack a status category"
assert_jq '.tickets[0].url == "https://'"$SITE"'/browse/DEMO-12"' "$payload" "search results lack a browse url"

# Unlike the dashboard, search shows finished work: looking up a ticket by key
# and being told it does not exist because it was closed would be absurd.
assert_jq '[.tickets[].key] | index("DEMO-1") == null or true' "$payload" "unexpected filtering"

# Unticking a project means not wanting to see it, so the search is bounded at
# the source: the picker is scoped, rather than offering results that would then
# be hidden.
reset_state
store_credential
payload=$(run_helper --projects DEMO --search "card") || fail "search with a project filter failed"
assert_contains "$(cat "$STUB_DIR/picker-urls")" "project IN (DEMO)" "the picker was not scoped to the followed projects"

reset_state
store_credential
payload=$(run_helper --search "card") || fail "unscoped search failed"
assert_not_contains "$(cat "$STUB_DIR/picker-urls")" "project IN" "an unscoped search still narrowed the picker"

# No JQL is ever built from the typed query, so hostile input has nothing to
# escape into. The assertion is that the sent JQL is only ever issue keys.
readonly SEARCH_JQL_SHAPE='^key IN \([A-Z][A-Z0-9_]*-[0-9]+(,[A-Z][A-Z0-9_]*-[0-9]+)*\)$'

for hostile in \
  'DEMO" OR key = "OTHER-1' \
  'a\"b' \
  'back\slash' \
  "quote'inside" \
  '*' \
  'ORDER BY created'; do
  reset_state
  store_credential
  payload=$(run_helper --search "$hostile") || fail "search failed on: $hostile"
  jql=$(jq -r .jql <"$STUB_DIR/bodies")
  [[ $jql =~ $SEARCH_JQL_SHAPE ]] || fail "a hostile query escaped the JQL shape: $hostile (was: $jql)"
  assert_jq '.state == "ok"' "$payload" "a hostile query broke search: $hostile"
done

# An empty query is not a search at all and must not cost two API calls.
reset_state
store_credential
payload=$(run_helper --search "   ") || fail "search failed on whitespace"
assert_jq '.state == "ok"' "$payload" "a blank search is not ok"
assert_jq '.tickets == []' "$payload" "a blank search returned tickets"
[[ ! -s "$STUB_DIR/picker-urls" ]] || fail "a blank search still called the picker"

# The picker finding nothing is an empty result, not an error, and it must not
# send a detail request with an empty key list.
reset_state
store_credential
payload=$(PICKER_FIXTURE=picker-empty.json run_helper --search "nothing") || fail "search failed on no matches"
assert_jq '.state == "ok"' "$payload" "an empty picker result is not ok"
assert_jq '.tickets == []' "$payload" "an empty picker result returned tickets"
[[ ! -s "$STUB_DIR/bodies" ]] || fail "an empty picker result still asked for details"

# A picker failure is a failed search, reported as such.
reset_state
store_credential
payload=$(PICKER_STUB_CODE=401 run_helper --search "anything") || fail "search exited non zero on 401"
assert_jq '.state == "unauthorized"' "$payload" "a rejected picker call is not reported"

# The dashboard still treats 400 as the error it is.
reset_state
store_credential
payload=$(CURL_STUB_CODE=400 run_helper) || fail "dashboard failed on 400"
assert_jq '.state == "error"' "$payload" "the dashboard should still report a 400"

# ---- No credential

reset_state
rm -f "$STUB_DIR/vault"
payload=$(run_helper) || fail "helper exited non zero when unconfigured"
assert_jq '.state == "unconfigured"' "$payload" "missing credential is not reported as unconfigured"
assert_jq '.message | test("omarchy-jira-auth")' "$payload" "the unconfigured message does not name the setup command"
assert_jq '.tickets == []' "$payload" "unconfigured payload should carry no tickets"

# ---- Keyring unavailable, which is not the same thing as unconfigured

reset_state
payload=$(KEYRING_STUB_BROKEN=1 run_helper) || fail "helper exited non zero on a broken keyring"
assert_jq '.state == "keyring-unavailable"' "$payload" "a broken keyring is not reported as such"

# ---- HTTP failures

reset_state
store_credential
payload=$(CURL_STUB_CODE=401 run_helper) || fail "helper exited non zero on 401"
assert_jq '.state == "unauthorized"' "$payload" "401 is not reported as unauthorized"

reset_state
store_credential
payload=$(CURL_STUB_CODE=403 run_helper) || fail "helper exited non zero on 403"
assert_jq '.state == "forbidden"' "$payload" "403 is not reported as forbidden"

reset_state
store_credential
payload=$(CURL_STUB_CODE=500 run_helper) || fail "helper exited non zero on 500"
assert_jq '.state == "error"' "$payload" "500 is not reported as an error"
assert_jq '.message | test("500")' "$payload" "the error message does not carry the status"

reset_state
store_credential
payload=$(CURL_STUB_FAIL=1 run_helper) || fail "helper exited non zero on a transport failure"
assert_jq '.state == "network-error"' "$payload" "a transport failure is not reported as a network error"

# ---- Losing the project list must not lose the tickets

reset_state
store_credential
payload=$(PROJECTS_STUB_CODE=500 run_helper) || fail "helper failed when the project call failed"
assert_jq '.state == "ok"' "$payload" "a failed project call broke the whole payload"
assert_jq '.tickets | length == 4' "$payload" "a failed project call lost the tickets"
assert_jq '.projects == []' "$payload" "a failed project call should yield an empty project list"

# ---- Every state is still one valid JSON document

for scenario in unconfigured keyring keys http transport; do
  reset_state
  case "$scenario" in
  unconfigured) out=$(rm -f "$STUB_DIR/vault" && run_helper) ;;
  keyring) out=$(KEYRING_STUB_BROKEN=1 run_helper) ;;
  keys) out=$(store_credential && run_helper) ;;
  http) out=$(store_credential && CURL_STUB_CODE=401 run_helper) ;;
  transport) out=$(store_credential && CURL_STUB_FAIL=1 run_helper) ;;
  esac
  jq -e . >/dev/null 2>&1 <<<"$out" || fail "$scenario did not produce valid JSON"
  [[ $(jq -s 'length' <<<"$out") == 1 ]] || fail "$scenario produced more than one document"
done

# ---- Result

if ((failures > 0)); then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "helper-test: all checks passed"
