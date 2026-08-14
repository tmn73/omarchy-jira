// Pure logic for the Jira widget: grouping, searching, and formatting.
//
// Everything here is Qt-free so it can be unit tested under node
// (tests/model.test.js). The QML side owns rendering and scheduling; this file
// owns what the payload means.
//
// The single rule worth repeating: nothing keys off a status name. Every Jira
// site names its own statuses, so "In Review" is a label, never a signal. The
// only portable signal is the status category, which Jira guarantees to be one
// of new, indeterminate, or done.

var CATEGORY_WAITING = "indeterminate"
var CATEGORY_DONE = "done"

var ISSUE_KEY_PATTERN = /^[A-Za-z][A-Za-z0-9_]*-[0-9]+$/

var MINUTE = 60
var HOUR = 3600
var DAY = 86400
var MONTH = 2592000

function asArray(value) {
  return Array.isArray(value) ? value : []
}

function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

// Splits tickets into what the user has to act on and what is merely assigned.
//
// An unrecognised category lands in `assigned` rather than being dropped. A Jira
// site that invents a category is a reason to show work in a slightly wrong
// group, never a reason to hide it.
function groupTickets(tickets) {
  var waiting = []
  var assigned = []
  var list = asArray(tickets)

  for (var i = 0; i < list.length; i++) {
    var ticket = list[i]
    var category = text(ticket && ticket.statusCategory)
    if (category === CATEGORY_DONE)
      continue
    if (category === CATEGORY_WAITING)
      waiting.push(ticket)
    else
      assigned.push(ticket)
  }

  return { waiting: waiting, assigned: assigned }
}

function looksLikeIssueKey(value) {
  return ISSUE_KEY_PATTERN.test(text(value).trim())
}

// Returns the canonical form of an issue key, or an empty string when the input
// is not one. Callers use the empty string to decide they are dealing with free
// text instead.
function normalizeIssueKey(value) {
  var trimmed = text(value).trim()
  return ISSUE_KEY_PATTERN.test(trimmed) ? trimmed.toUpperCase() : ""
}

function relativeTime(value, nowMs) {
  var then = Date.parse(text(value))
  if (!isFinite(then))
    return ""

  var now = isFinite(nowMs) ? nowMs : Date.now()
  var seconds = Math.floor((now - then) / 1000)
  if (seconds < MINUTE)
    return "just now"
  if (seconds < HOUR)
    return Math.floor(seconds / MINUTE) + "m ago"
  if (seconds < DAY)
    return Math.floor(seconds / HOUR) + "h ago"
  if (seconds < MONTH)
    return Math.floor(seconds / DAY) + "d ago"
  return Math.floor(seconds / MONTH) + "mo ago"
}

// Matches a query against the key and the summary. This runs on every keystroke
// against tickets already in memory, which is what makes the search feel
// instant while the remote query is still in flight.
function filterTickets(tickets, query) {
  var list = asArray(tickets)
  var needle = text(query).trim().toLowerCase()
  if (needle === "")
    return list.slice()

  var matches = []
  for (var i = 0; i < list.length; i++) {
    var ticket = list[i]
    var key = text(ticket && ticket.key).toLowerCase()
    var summary = text(ticket && ticket.summary).toLowerCase()
    if (key.indexOf(needle) !== -1 || summary.indexOf(needle) !== -1)
      matches.push(ticket)
  }
  return matches
}

// Produces one list from the instant local matches and the slower remote ones.
//
// Local results keep their position, remote duplicates are dropped, and what
// survives is flagged so the panel can mark results that came from outside the
// user's own tickets. Copies are returned so the caller's arrays, which are
// bound to the panel, are never mutated underneath it.
function mergeSearchResults(local, remote) {
  var merged = []
  var seen = {}
  var i
  var localList = asArray(local)
  var remoteList = asArray(remote)

  for (i = 0; i < localList.length; i++) {
    var here = localList[i]
    var localKey = text(here && here.key)
    if (localKey !== "" && seen[localKey])
      continue
    seen[localKey] = true
    merged.push(withRemoteFlag(here, false))
  }

  for (i = 0; i < remoteList.length; i++) {
    var there = remoteList[i]
    var remoteKey = text(there && there.key)
    if (remoteKey !== "" && seen[remoteKey])
      continue
    seen[remoteKey] = true
    merged.push(withRemoteFlag(there, true))
  }

  return merged
}

function withRemoteFlag(ticket, remote) {
  var copy = {}
  for (var name in ticket) {
    if (Object.prototype.hasOwnProperty.call(ticket, name))
      copy[name] = ticket[name]
  }
  copy.remote = remote
  return copy
}

// Normalises the followed-projects setting into a list of project keys.
//
// It accepts a list or a comma separated string, because the two ways of
// writing this setting produce different shapes: the settings pane stores a
// list, while `omarchy bar set tmn73.jira followedProjects DS` stores a string.
// A setting that only works when written one particular way is a trap.
function projectList(value) {
  var raw = []
  if (Array.isArray(value))
    raw = value
  else if (text(value) !== "")
    raw = text(value).split(",")

  var keys = []
  for (var i = 0; i < raw.length; i++) {
    var key = text(raw[i]).trim().toUpperCase()
    if (key !== "" && keys.indexOf(key) === -1)
      keys.push(key)
  }
  return keys
}

// Applies one click on a project checkbox and returns the new selection.
//
// An empty selection means "every project", which is what a fresh install shows
// and what the pane draws as every box ticked. Clicking a ticked box therefore
// has to unticket it, not restart the selection from that one project: the
// first click means "not this one", so it expands to every key except the one
// clicked.
//
// A selection that ends up empty, or that ends up holding every project, is
// stored as empty. Both mean the same thing, and a widget configured to show
// nothing at all is never what someone wanted.
function toggleFollowedProject(followed, key, allKeys) {
  var current = projectList(followed)
  var all = projectList(allKeys)
  var wanted = text(key).trim().toUpperCase()
  if (wanted === "")
    return current

  var next
  if (current.length === 0) {
    next = []
    for (var i = 0; i < all.length; i++) {
      if (all[i] !== wanted)
        next.push(all[i])
    }
  } else {
    var at = current.indexOf(wanted)
    next = current.slice()
    if (at === -1)
      next.push(wanted)
    else
      next.splice(at, 1)
  }

  if (next.length === 0 || (all.length > 0 && next.length === all.length))
    return []
  return next
}

// Drops results from projects the user is not following.
//
// This filters rather than ranks: unticking a project means not wanting to see
// it, and burying it at the bottom of the list is not the same thing.
function filterByProject(tickets, followed) {
  var list = asArray(tickets)
  var keys = asArray(followed)
  if (keys.length === 0 || list.length === 0)
    return list.slice()

  var kept = []
  for (var i = 0; i < list.length; i++) {
    if (keys.indexOf(text(list[i] && list[i].projectKey)) !== -1)
      kept.push(list[i])
  }
  return kept
}

// Caps a rendered list. A cap that is missing, zero, or negative returns the
// list untouched: a broken setting must never silently hide someone's work.
function limit(tickets, max) {
  var list = asArray(tickets)
  var cap = Number(max)
  if (!isFinite(cap) || cap < 1)
    return list.slice()
  return list.slice(0, cap)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    groupTickets: groupTickets,
    looksLikeIssueKey: looksLikeIssueKey,
    normalizeIssueKey: normalizeIssueKey,
    relativeTime: relativeTime,
    filterTickets: filterTickets,
    mergeSearchResults: mergeSearchResults,
    filterByProject: filterByProject,
    projectList: projectList,
    toggleFollowedProject: toggleFollowedProject,
    limit: limit
  }
}
