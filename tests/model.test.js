const test = require('node:test')
const assert = require('node:assert')
const Model = require('../Model.js')

const TICKETS = [
  { key: 'DEMO-12', summary: 'Card limit is not refreshed', status: 'In Progress', statusCategory: 'indeterminate', projectKey: 'DEMO', updated: '2026-08-14T06:24:20.095-0500' },
  { key: 'DEMO-8', summary: 'Retry failed supplier payments', status: 'In Review', statusCategory: 'indeterminate', projectKey: 'DEMO', updated: '2026-08-12T11:02:00.000-0500' },
  { key: 'DEMO-3', summary: 'Freeze lock files', status: 'Draft', statusCategory: 'new', projectKey: 'DEMO', updated: '2026-06-12T16:29:09.632-0500' },
  { key: 'OPS-5', summary: 'Duplicate group members', status: 'To Do', statusCategory: 'new', projectKey: 'OPS', updated: '2026-05-02T09:15:00.000-0500' },
  { key: 'DEMO-1', summary: 'Traveler names', status: "Won't Do", statusCategory: 'done', projectKey: 'DEMO', updated: '2026-02-09T14:27:44.440-0600' }
]

// ---- groupTickets

test('groupTickets puts in-progress work in waiting and to-do work in assigned', () => {
  const groups = Model.groupTickets(TICKETS)
  assert.deepEqual(groups.waiting.map(t => t.key), ['DEMO-12', 'DEMO-8'])
  assert.deepEqual(groups.assigned.map(t => t.key), ['DEMO-3', 'OPS-5'])
})

test('groupTickets drops the done category', () => {
  const groups = Model.groupTickets(TICKETS)
  const keys = groups.waiting.concat(groups.assigned).map(t => t.key)
  assert.equal(keys.indexOf('DEMO-1'), -1)
})

test('groupTickets keys off the category, never the status name', () => {
  // "In Review" is not a category, and other Jira sites call it other things.
  // It has to land in waiting purely because its category is indeterminate.
  const groups = Model.groupTickets([
    { key: 'X-1', status: 'Peer Review', statusCategory: 'indeterminate' },
    { key: 'X-2', status: 'In Progress', statusCategory: 'new' }
  ])
  assert.deepEqual(groups.waiting.map(t => t.key), ['X-1'])
  assert.deepEqual(groups.assigned.map(t => t.key), ['X-2'])
})

test('groupTickets preserves incoming order inside each group', () => {
  const reversed = TICKETS.slice().reverse()
  const groups = Model.groupTickets(reversed)
  assert.deepEqual(groups.waiting.map(t => t.key), ['DEMO-8', 'DEMO-12'])
})

test('groupTickets treats an unknown category as assigned rather than hiding it', () => {
  const groups = Model.groupTickets([{ key: 'X-1', statusCategory: 'something-new' }])
  assert.deepEqual(groups.assigned.map(t => t.key), ['X-1'])
})

test('groupTickets tolerates null and empty input', () => {
  assert.deepEqual(Model.groupTickets(null), { waiting: [], assigned: [] })
  assert.deepEqual(Model.groupTickets([]), { waiting: [], assigned: [] })
})

// ---- looksLikeIssueKey

test('looksLikeIssueKey accepts real key shapes', () => {
  assert.equal(Model.looksLikeIssueKey('DEMO-12'), true)
  assert.equal(Model.looksLikeIssueKey('demo-12'), true)
  assert.equal(Model.looksLikeIssueKey('ABC1-20'), true)
  assert.equal(Model.looksLikeIssueKey('  DS-849  '), true)
})

test('looksLikeIssueKey rejects everything else', () => {
  assert.equal(Model.looksLikeIssueKey('DEMO'), false)
  assert.equal(Model.looksLikeIssueKey('849'), false)
  assert.equal(Model.looksLikeIssueKey('DEMO-'), false)
  assert.equal(Model.looksLikeIssueKey('-12'), false)
  assert.equal(Model.looksLikeIssueKey('card limit'), false)
  assert.equal(Model.looksLikeIssueKey(''), false)
  assert.equal(Model.looksLikeIssueKey(null), false)
})

test('normalizeIssueKey uppercases and trims', () => {
  assert.equal(Model.normalizeIssueKey('  demo-12 '), 'DEMO-12')
  assert.equal(Model.normalizeIssueKey('not a key'), '')
})

// ---- relativeTime

test('relativeTime renders each scale', () => {
  const now = Date.parse('2026-08-14T12:00:00Z')
  assert.equal(Model.relativeTime('2026-08-14T11:59:30Z', now), 'just now')
  assert.equal(Model.relativeTime('2026-08-14T11:45:00Z', now), '15m ago')
  assert.equal(Model.relativeTime('2026-08-14T09:00:00Z', now), '3h ago')
  assert.equal(Model.relativeTime('2026-08-12T12:00:00Z', now), '2d ago')
  assert.equal(Model.relativeTime('2026-06-14T12:00:00Z', now), '2mo ago')
})

test('relativeTime returns an empty string for unusable input', () => {
  const now = Date.parse('2026-08-14T12:00:00Z')
  assert.equal(Model.relativeTime('', now), '')
  assert.equal(Model.relativeTime('not a date', now), '')
  assert.equal(Model.relativeTime(null, now), '')
})

test('relativeTime never renders a negative age', () => {
  const now = Date.parse('2026-08-14T12:00:00Z')
  assert.equal(Model.relativeTime('2026-08-14T13:00:00Z', now), 'just now')
})

// ---- filterTickets

test('filterTickets matches on key and on summary, case insensitively', () => {
  assert.deepEqual(Model.filterTickets(TICKETS, 'demo-8').map(t => t.key), ['DEMO-8'])
  assert.deepEqual(Model.filterTickets(TICKETS, 'LOCK').map(t => t.key), ['DEMO-3'])
  assert.deepEqual(Model.filterTickets(TICKETS, 'supplier').map(t => t.key), ['DEMO-8'])
})

test('filterTickets returns everything for an empty query', () => {
  assert.equal(Model.filterTickets(TICKETS, '').length, TICKETS.length)
  assert.equal(Model.filterTickets(TICKETS, '   ').length, TICKETS.length)
})

test('filterTickets tolerates null input', () => {
  assert.deepEqual(Model.filterTickets(null, 'x'), [])
})

// ---- mergeSearchResults

test('mergeSearchResults keeps local results first and marks remote ones', () => {
  const local = [{ key: 'DEMO-8' }]
  const remote = [{ key: 'DEMO-8' }, { key: 'OTHER-3' }]
  const merged = Model.mergeSearchResults(local, remote)
  assert.deepEqual(merged.map(t => t.key), ['DEMO-8', 'OTHER-3'])
  assert.equal(merged[0].remote, false)
  assert.equal(merged[1].remote, true)
})

test('mergeSearchResults does not mutate its inputs', () => {
  const local = [{ key: 'DEMO-8' }]
  const remote = [{ key: 'OTHER-3' }]
  Model.mergeSearchResults(local, remote)
  assert.equal(local[0].remote, undefined)
  assert.equal(remote[0].remote, undefined)
})

test('mergeSearchResults tolerates missing sides', () => {
  assert.deepEqual(Model.mergeSearchResults(null, null), [])
  assert.equal(Model.mergeSearchResults([{ key: 'A-1' }], null).length, 1)
  assert.equal(Model.mergeSearchResults(null, [{ key: 'A-1' }]).length, 1)
})

// ---- projectList

test('projectList accepts a list', () => {
  assert.deepEqual(Model.projectList(['DS', 'HUB']), ['DS', 'HUB'])
})

test('projectList accepts a comma separated string', () => {
  // This is the shape `omarchy bar set` writes.
  assert.deepEqual(Model.projectList('DS,HUB'), ['DS', 'HUB'])
  assert.deepEqual(Model.projectList('DS, HUB'), ['DS', 'HUB'])
  assert.deepEqual(Model.projectList('DS'), ['DS'])
})

test('projectList normalises case and drops blanks and duplicates', () => {
  assert.deepEqual(Model.projectList('ds, ,DS,hub'), ['DS', 'HUB'])
  assert.deepEqual(Model.projectList(['', '  ']), [])
})

test('projectList treats nothing as no filter', () => {
  assert.deepEqual(Model.projectList(null), [])
  assert.deepEqual(Model.projectList(''), [])
  assert.deepEqual(Model.projectList([]), [])
})

// ---- toggleFollowedProject

const ALL = ['ADMIN', 'DS', 'HUB', 'OPS']

test('unticking one box from the default keeps every other project', () => {
  // Nothing followed means everything is shown and every box is drawn ticked,
  // so the first click has to read as "not this one".
  assert.deepEqual(Model.toggleFollowedProject([], 'ADMIN', ALL), ['DS', 'HUB', 'OPS'])
})

test('ticking and unticking a box from a real selection', () => {
  assert.deepEqual(Model.toggleFollowedProject(['DS'], 'HUB', ALL), ['DS', 'HUB'])
  assert.deepEqual(Model.toggleFollowedProject(['DS', 'HUB'], 'DS', ALL), ['HUB'])
})

test('unticking the last box falls back to showing everything', () => {
  // A widget configured to show nothing is never what someone meant.
  assert.deepEqual(Model.toggleFollowedProject(['DS'], 'DS', ALL), [])
})

test('ticking the last missing box is stored as no filter', () => {
  assert.deepEqual(Model.toggleFollowedProject(['DS', 'HUB', 'OPS'], 'ADMIN', ALL), [])
})

test('toggleFollowedProject normalises case and ignores a blank key', () => {
  assert.deepEqual(Model.toggleFollowedProject(['DS'], 'hub', ALL), ['DS', 'HUB'])
  assert.deepEqual(Model.toggleFollowedProject(['DS'], '', ALL), ['DS'])
})

// ---- filterByProject

test('filterByProject drops projects that are not followed', () => {
  const results = [
    { key: 'DES-1069', projectKey: 'DES' },
    { key: 'DS-1069', projectKey: 'DS' },
    { key: 'HUB-3', projectKey: 'HUB' }
  ]
  assert.deepEqual(Model.filterByProject(results, ['DS']).map(t => t.key), ['DS-1069'])
  assert.deepEqual(Model.filterByProject(results, ['DS', 'HUB']).map(t => t.key), ['DS-1069', 'HUB-3'])
})

test('filterByProject keeps order', () => {
  const results = [
    { key: 'DS-2', projectKey: 'DS' },
    { key: 'DES-1', projectKey: 'DES' },
    { key: 'DS-4', projectKey: 'DS' }
  ]
  assert.deepEqual(Model.filterByProject(results, ['DS']).map(t => t.key), ['DS-2', 'DS-4'])
})

test('filterByProject leaves the list alone when nothing is followed', () => {
  const results = [{ key: 'B-1', projectKey: 'B' }, { key: 'A-1', projectKey: 'A' }]
  assert.deepEqual(Model.filterByProject(results, []).map(t => t.key), ['B-1', 'A-1'])
  assert.deepEqual(Model.filterByProject(results, null).map(t => t.key), ['B-1', 'A-1'])
})

test('filterByProject tolerates null tickets', () => {
  assert.deepEqual(Model.filterByProject(null, ['DS']), [])
})

// ---- sprintBars

// Modelled on a real sprint: three statuses Jira calls done, and one the team
// calls done while Jira does not.
const SPRINT = {
  name: 'Demo Sprint 12',
  startDate: '2026-08-05T00:00:00.000Z',
  endDate: '2026-08-19T00:00:00.000Z',
  total: 41,
  estimated: 13,
  statuses: [
    { name: 'Released', category: 'done', count: 15, points: 16 },
    { name: 'In Progress', category: 'indeterminate', count: 13, points: 26 },
    { name: 'Done - Ready to Release', category: 'done', count: 5, points: 3 },
    { name: 'Done - No Release', category: 'done', count: 4, points: 1 },
    { name: 'Blocked', category: 'indeterminate', count: 2, points: 0 },
    { name: 'Ready to Merge', category: 'indeterminate', count: 2, points: 3 }
  ]
}

// Day 7 of a 14 day sprint.
const MIDPOINT = Date.parse('2026-08-12T00:00:00.000Z')

test('sprintBars reports time and work side by side', () => {
  const bars = Model.sprintBars(SPRINT, ['time', 'tickets'], MIDPOINT)
  assert.deepEqual(bars.map(b => b.id), ['time', 'tickets'])
  assert.equal(bars[0].percent, 50)
  assert.equal(bars[0].detail, '7d left')
  // 15 + 5 + 4 tickets in the done category.
  assert.equal(bars[1].percent, 59)
  assert.equal(bars[1].detail, '24/41')
})

test('sprintBars can show points too', () => {
  const bars = Model.sprintBars(SPRINT, ['time', 'tickets', 'points'], MIDPOINT)
  assert.deepEqual(bars.map(b => b.id), ['time', 'tickets', 'points'])
  // 16 + 3 + 1 points done out of 49.
  assert.equal(bars[2].percent, 41)
  assert.equal(bars[2].detail, '20/49')
})

// ---- sprintTotals

test('sprintTotals falls back to what Jira calls done', () => {
  const totals = Model.sprintTotals(SPRINT, [])
  assert.equal(totals.total, 41)
  assert.equal(totals.done, 24)
  assert.equal(totals.points.total, 49)
  assert.equal(totals.points.done, 20)
})

test("sprintTotals honours the team's own definition of done", () => {
  // Ready to Merge is finished as far as this team is concerned, even though
  // Jira files it under In Progress.
  const chosen = ['Released', 'Done - Ready to Release', 'Done - No Release', 'Ready to Merge']
  const totals = Model.sprintTotals(SPRINT, chosen)
  assert.equal(totals.done, 26)
  assert.equal(totals.points.done, 23)
})

test('sprintTotals matches status names case insensitively', () => {
  assert.equal(Model.sprintTotals(SPRINT, ['released']).done, 15)
})

test('sprintTotals tolerates no sprint', () => {
  assert.deepEqual(Model.sprintTotals(null, []), { total: 0, done: 0, points: { total: 0, done: 0 } })
})

test('sprintBars uses the chosen done statuses', () => {
  const bars = Model.sprintBars(SPRINT, ['tickets'], MIDPOINT, ['Released', 'Ready to Merge'])
  assert.equal(bars[0].detail, '17/41')
})

// ---- defaultDoneStatuses

test('defaultDoneStatuses starts from what Jira calls done', () => {
  assert.deepEqual(Model.defaultDoneStatuses(SPRINT),
    ['Released', 'Done - Ready to Release', 'Done - No Release'])
})

test('defaultDoneStatuses tolerates no sprint', () => {
  assert.deepEqual(Model.defaultDoneStatuses(null), [])
})

test('sprintBars shows nothing when nothing is asked for', () => {
  assert.deepEqual(Model.sprintBars(SPRINT, [], MIDPOINT), [])
  assert.deepEqual(Model.sprintBars(SPRINT, null, MIDPOINT), [])
})

test('sprintBars tolerates no sprint', () => {
  assert.deepEqual(Model.sprintBars(null, ['time'], MIDPOINT), [])
})

test('sprintBars never reports negative or overrun time', () => {
  const before = Date.parse('2026-08-01T00:00:00.000Z')
  const after = Date.parse('2026-09-01T00:00:00.000Z')
  assert.equal(Model.sprintBars(SPRINT, ['time'], before)[0].percent, 0)
  assert.equal(Model.sprintBars(SPRINT, ['time'], after)[0].percent, 100)
  assert.equal(Model.sprintBars(SPRINT, ['time'], after)[0].detail, 'ended')
})

test('sprintBars omits the time bar when the sprint has no usable dates', () => {
  const undated = Object.assign({}, SPRINT, { startDate: '', endDate: '' })
  assert.deepEqual(Model.sprintBars(undated, ['time', 'tickets'], MIDPOINT).map(b => b.id), ['tickets'])
})

test('sprintBars reports zero rather than inventing a denominator', () => {
  // A sprint where nobody estimated anything must not borrow the ticket count
  // and present it as points.
  const unestimated = Object.assign({}, SPRINT, {
    estimated: 0,
    statuses: SPRINT.statuses.map(s => Object.assign({}, s, { points: 0 }))
  })
  const bars = Model.sprintBars(unestimated, ['points'], MIDPOINT)
  assert.equal(bars[0].percent, 0)
  assert.equal(bars[0].detail, '0/0')
})

// ---- estimateCoverage

test('estimateCoverage says how much of the sprint is estimated', () => {
  assert.equal(Model.estimateCoverage(SPRINT), '13 of 41 tickets estimated')
})

test('estimateCoverage is plain when everything is estimated', () => {
  const full = Object.assign({}, SPRINT, { total: 41, estimated: 41 })
  assert.equal(Model.estimateCoverage(full), 'every ticket is estimated')
})

test('estimateCoverage says nothing without a sprint', () => {
  assert.equal(Model.estimateCoverage(null), '')
  assert.equal(Model.estimateCoverage({ total: 0 }), '')
})

// ---- limit

test('limit caps the list', () => {
  assert.equal(Model.limit(TICKETS, 2).length, 2)
  assert.equal(Model.limit(TICKETS, 99).length, TICKETS.length)
})

test('limit leaves the list alone when the cap is nonsense', () => {
  // A broken setting must never silently hide work.
  assert.equal(Model.limit(TICKETS, 0).length, TICKETS.length)
  assert.equal(Model.limit(TICKETS, -5).length, TICKETS.length)
  assert.equal(Model.limit(TICKETS, NaN).length, TICKETS.length)
})

test('limit tolerates null', () => {
  assert.deepEqual(Model.limit(null, 5), [])
})
