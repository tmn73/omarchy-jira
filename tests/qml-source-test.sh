#!/usr/bin/env bash
# Source-level checks on the QML.
#
# A running shell cannot be driven headlessly, so these assert the properties
# that would otherwise only be caught by someone noticing the widget looks wrong
# a week later: the contract Panel.qml relies on, the states it must render, and
# the size limit that keeps it readable.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

has() {
  local file="$1" pattern="$2" label="$3"
  grep -qE "$pattern" "$ROOT/$file" || fail "$label"
}

hasnt() {
  local file="$1" pattern="$2" label="$3"
  grep -qE "$pattern" "$ROOT/$file" && fail "$label" || true
}

# ---- Every QML file parses
#
# A diagnostic is a real problem; a silent non zero exit is not. qmllint aborts
# without a word on the typed function signatures Quickshell requires for IPC
# handlers ("function search(query: string): string"), which the shell itself
# loads happily. So the output decides, not the exit code.

for file in "$ROOT"/*.qml; do
  output=$(qmllint "$file" 2>&1 || true)
  if [[ -n $output ]]; then
    fail "$(basename "$file"): $output"
  fi
done

# ---- Service exposes what the panel binds to
#
# These are the names Panel.qml reads. Renaming one without the other produces
# a silently empty panel rather than an error, which is exactly the failure a
# source test is for.

for property in loading state message site account fetchedAt tickets projects \
  searchResults searchQuery answeredQuery sprint sprintState followedProjects \
  sprintBarChoice doneStatuses waitingCount assignedCount hasData; do
  has "Service.qml" "property.* $property\b" "Service.qml no longer exposes $property"
done

for method in refresh search clearSearch; do
  has "Service.qml" "function $method\(" "Service.qml no longer has $method()"
done

# The helper is resolved relative to the plugin, never from an absolute path,
# so a checkout in any directory works.
has "Service.qml" "Qt\.resolvedUrl" "Service.qml does not resolve the helper relatively"
hasnt "Service.qml" "/home/|/usr/local/" "Service.qml contains an absolute path"

# Clamped so a hand-edited shell.json cannot ask Jira for a refresh every second.
has "Service.qml" "intSetting\(\"refreshIntervalSec\", 900, 60, 3600\)" \
  "the refresh interval is no longer clamped"

# ---- The panel renders every state the helper can report
#
# The helper promises six states. A panel that silently ignores one leaves the
# user staring at an empty popup with no idea why.

for state in unconfigured keyring-unavailable unauthorized forbidden network-error searching; do
  has "StateNotice.qml" "\"$state\"" "StateNotice.qml does not handle the $state state"
done

# Only the states someone can act on name a command.
has "StateNotice.qml" "omarchy-jira-auth" "StateNotice.qml never names the setup command"

# ---- The keyboard contract

for key in '"r"' '"y"' '"/"' '","' ; do
  has "Panel.qml" "key === $key" "Panel.qml no longer handles $key"
done
has "Panel.qml" "onMoveRequested" "Panel.qml no longer moves the cursor"
has "Panel.qml" "onActivateRequested" "Panel.qml no longer opens the highlighted row"
has "Panel.qml" "onCloseRequested" "Panel.qml no longer closes on escape"
has "JiraSearchField.qml" "Keys\.onUpPressed" "the search field swallows the up arrow again"
has "JiraSearchField.qml" "Keys\.onDownPressed" "the search field swallows the down arrow again"

# ---- The panel assembles, it does not draw
#
# Row rendering belongs to TicketRow and payload meaning to Model.js. The line
# limit is the guard that keeps that true: both plugins this one is modelled on
# ended up with panels of 700 and 1200 lines.

hasnt "Panel.qml" "elide: Text\.ElideRight" \
  "Panel.qml is drawing text rows again instead of delegating to TicketRow"

lines=$(wc -l <"$ROOT/Panel.qml")
if ((lines > 400)); then
  fail "Panel.qml is $lines lines, over the 400 line limit"
fi

# ---- Result

if ((failures > 0)); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "qml-source-test: all checks passed"
