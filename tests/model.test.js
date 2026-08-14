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
