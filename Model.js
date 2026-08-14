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

var MINUTE = 60
var HOUR = 3600
var DAY = 86400
var MONTH = 2592000
var MS_PER_DAY = 86400000

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

// Stamps a relative age onto each row.
//
// Lives here rather than in the panel so rows never reach for a clock, and so
// the whole list is dated from one instant instead of each row reading the
// time as it renders.
function decorateRows(rows, nowMs) {
  var list = asArray(rows)
  var now = isFinite(nowMs) ? nowMs : Date.now()
  var decorated = []
  for (var i = 0; i < list.length; i++) {
    var copy = {}
    for (var name in list[i]) {
      if (Object.prototype.hasOwnProperty.call(list[i], name))
        copy[name] = list[i][name]
    }
    copy.age = relativeTime(list[i].updated, now)
    decorated.push(copy)
  }
  return decorated
}

// The key the cursor lands on after a move.
//
// Keyboard navigation walks one flat list, so crossing from the last row of a
// section into the first of the next is the same step as any other. Moving from
// nowhere lands on an end rather than doing nothing, which is what makes the
// first arrow press useful.
function nextKey(tickets, currentKey, delta) {
  var list = asArray(tickets)
  if (list.length === 0)
    return ""

  var index = -1
  for (var i = 0; i < list.length; i++) {
    if (text(list[i].key) === text(currentKey)) {
      index = i
      break
    }
  }

  if (index === -1)
    index = delta > 0 ? 0 : list.length - 1
  else
    index = Math.max(0, Math.min(list.length - 1, index + delta))

  return text(list[index].key)
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

// Applies one click on a done-status checkbox.
//
// The first click has to start from what is drawn, which is Jira's own idea of
// done, otherwise ticking one status would silently unmark every other.
function toggleDoneStatus(current, name, defaults) {
  var selection = asArray(current)
  if (selection.length === 0)
    selection = asArray(defaults)

  var wanted = text(name)
  if (wanted === "")
    return selection.slice()

  var lowered = wanted.toLowerCase()
  var next = []
  var found = false
  for (var i = 0; i < selection.length; i++) {
    if (text(selection[i]).toLowerCase() === lowered)
      found = true
    else
      next.push(selection[i])
  }
  if (!found)
    next.push(wanted)
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

var SPRINT_BAR_TIME = "time"
var SPRINT_BAR_TICKETS = "tickets"
var SPRINT_BAR_POINTS = "points"

// Decides what "done" means for a sprint, and counts accordingly.
//
// Jira's status categories are the only portable default, but they are not the
// team's opinion. A status like "Ready to Merge" sits in the In Progress
// category while the team considers that work finished, and a sprint bar that
// disagrees with the people reading it is worse than no bar.
//
// So: a status counts as finished if the user said so, and failing that if Jira
// puts it in the done category. The setting names statuses, because that is
// what people recognise on their own board.
function sprintTotals(sprint, doneStatuses) {
  var totals = { total: 0, done: 0, points: { total: 0, done: 0 } }
  if (!sprint)
    return totals

  var statuses = asArray(sprint.statuses)
  var chosen = []
  var explicit = asArray(doneStatuses)
  for (var c = 0; c < explicit.length; c++)
    chosen.push(text(explicit[c]).toLowerCase())

  for (var i = 0; i < statuses.length; i++) {
    var entry = statuses[i]
    var count = Number(entry.count) || 0
    var points = Number(entry.points) || 0
    var finished = chosen.length > 0
      ? chosen.indexOf(text(entry.name).toLowerCase()) !== -1
      : text(entry.category) === CATEGORY_DONE

    totals.total += count
    totals.points.total += points
    if (finished) {
      totals.done += count
      totals.points.done += points
    }
  }
  return totals
}

// The statuses Jira would call finished, used as the starting selection so the
// pane opens on something sensible rather than on nothing ticked.
function defaultDoneStatuses(sprint) {
  var names = []
  var statuses = asArray(sprint && sprint.statuses)
  for (var i = 0; i < statuses.length; i++) {
    if (text(statuses[i].category) === CATEGORY_DONE)
      names.push(text(statuses[i].name))
  }
  return names
}

// Turns the raw sprint counts into the bars the panel draws.
//
// The percentages are kept next to each other on purpose: a completion bar
// alone says nothing, and it is the gap between work done and time spent that
// tells you whether a sprint is on track.
//
// Nothing here invents a number. A sprint with no estimated ticket reports zero
// points rather than falling back to counting tickets and calling them points.
function sprintBars(sprint, wanted, nowMs, doneStatuses) {
  if (!sprint)
    return []

  var chosen = projectList(wanted)
  var bars = []
  var now = isFinite(nowMs) ? nowMs : Date.now()
  var totals = sprintTotals(sprint, doneStatuses)
  var elapsedPercent = timePercent(sprint, now)

  if (chosen.indexOf(SPRINT_BAR_TIME.toUpperCase()) !== -1 && elapsedPercent !== null) {
    bars.push({
      id: SPRINT_BAR_TIME,
      label: "time",
      percent: elapsedPercent,
      detail: "",
      mark: null
    })
  }

  if (chosen.indexOf(SPRINT_BAR_TICKETS.toUpperCase()) !== -1) {
    var ticketPercent = totals.total > 0 ? Math.round((totals.done / totals.total) * 100) : 0
    bars.push({
      id: SPRINT_BAR_TICKETS,
      label: "tickets",
      percent: ticketPercent,
      detail: totals.done + "/" + totals.total,
      mark: elapsedPercent
    })
  }

  if (chosen.indexOf(SPRINT_BAR_POINTS.toUpperCase()) !== -1) {
    var pointPercent = totals.points.total > 0
      ? Math.round((totals.points.done / totals.points.total) * 100)
      : 0
    bars.push({
      id: SPRINT_BAR_POINTS,
      label: "points",
      percent: pointPercent,
      detail: totals.points.done + "/" + totals.points.total,
      mark: elapsedPercent
    })
  }

  return bars
}

// How much of the sprint has elapsed, or null when its dates cannot say.
function timePercent(sprint, nowMs) {
  var start = Date.parse(text(sprint && sprint.startDate))
  var end = Date.parse(text(sprint && sprint.endDate))
  if (!isFinite(start) || !isFinite(end) || end <= start)
    return null
  var elapsed = Math.min(Math.max(nowMs - start, 0), end - start)
  return Math.round((elapsed / (end - start)) * 100)
}

// The headline figure for the sprint, shown next to its name rather than on a
// bar: it is a fact about the sprint, not a measure of progress.
function sprintTimeLeft(sprint, nowMs) {
  var end = Date.parse(text(sprint && sprint.endDate))
  if (!isFinite(end))
    return ""
  return daysLeftLabel(end, isFinite(nowMs) ? nowMs : Date.now())
}

function daysLeftLabel(endMs, nowMs) {
  var remaining = endMs - nowMs
  if (remaining <= 0)
    return "ended"
  var days = Math.ceil(remaining / MS_PER_DAY)
  if (days === 1)
    return "1d left"
  return days + "d left"
}

// How much of a sprint carries an estimate, as a sentence the settings pane can
// show. Counting points is misleading when most tickets have none, and the only
// honest way to offer that choice is to say so where it is made.
function estimateCoverage(sprint) {
  if (!sprint)
    return ""
  var total = Number(sprint.total) || 0
  var estimated = Number(sprint.estimated) || 0
  if (total === 0)
    return ""
  if (estimated === total)
    return "every ticket is estimated"
  return estimated + " of " + total + " tickets estimated"
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
    relativeTime: relativeTime,
    decorateRows: decorateRows,
    nextKey: nextKey,
    filterTickets: filterTickets,
    mergeSearchResults: mergeSearchResults,
    filterByProject: filterByProject,
    sprintBars: sprintBars,
    sprintTotals: sprintTotals,
    sprintTimeLeft: sprintTimeLeft,
    defaultDoneStatuses: defaultDoneStatuses,
    toggleDoneStatus: toggleDoneStatus,
    estimateCoverage: estimateCoverage,
    projectList: projectList,
    toggleFollowedProject: toggleFollowedProject,
    limit: limit
  }
}
