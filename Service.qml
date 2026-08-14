import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Jira data service. The helper owns every API call and every credential
// access; this item schedules it and exposes one stable model to the panel.
//
// The rule that shapes this file: a failed refresh never discards a good
// payload. Tickets and their timestamp are replaced only when a run comes back
// ok. Everything else updates the state and the message and leaves the data
// alone, which is what lets a dropped network show the last known tickets with
// an honest "as of" time instead of an empty panel.
Item {
  id: root

  property var settings: ({})

  property bool loading: false
  property string state: "loading"
  property string message: qsTr("Loading Jira")
  property string site: ""
  property string account: ""
  property string fetchedAt: ""
  property var tickets: []
  property var projects: []
  property var sprint: null
  property string sprintState: "off"

  property var searchResults: []
  property string searchQuery: ""

  // The query the current searchResults actually answer. The panel compares it
  // with what is typed to decide whether it is still searching, which is more
  // truthful than a flag: a flag has to be lowered at some exact instant, and
  // every ordering of "lower the flag" and "post the results" leaves a frame
  // where the panel would claim there is nothing to find.
  property string answeredQuery: ""

  property bool refreshQueued: false
  property string _stdout: ""
  property string _searchStdout: ""

  readonly property var groups: Model.groupTickets(tickets)
  readonly property int waitingCount: groups.waiting.length
  readonly property int assignedCount: groups.assigned.length
  // The bar asks two questions of this service and no more: is something wrong,
  // and what should the tooltip say.
  readonly property bool needsAttention: state !== "ok" && state !== "loading"
  readonly property string tooltip: {
    if (state === "loading")
      return qsTr("Jira")
    if (state !== "ok")
      return message !== "" ? message : qsTr("Jira is unavailable")
    return waitingCount + qsTr(" in progress, ") + assignedCount + qsTr(" to do")
  }
  readonly property int maxDisplayedTickets: intSetting("maxDisplayedTickets", 25, 5, 100)
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 900, 60, 3600)
  readonly property bool connected: state === "ok"
  readonly property bool hasData: tickets.length > 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value))
      value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function helperPath() {
    return Qt.resolvedUrl("omarchy-jira-fetch").toString().replace(/^file:\/\//, "")
  }

  // Bound rather than computed on call: a binding that goes through a function
  // does not reliably re-evaluate when `settings` is replaced, which is how the
  // settings pane ended up drawing a selection the fetch had already moved past.
  readonly property var followedProjects: Model.projectList(setting("followedProjects", []))

  // Which sprint bars to draw. Empty means the section is off entirely, and the
  // helper is then never asked for a sprint, so teams that do not run sprints
  // pay nothing for the feature.
  readonly property var sprintBarChoice: Model.projectList(setting("sprintBars", ["time", "tickets"]))
  readonly property bool wantSprint: sprintBarChoice.length > 0

  // Which statuses this team calls finished. Empty means "whatever Jira calls
  // done", which is the only sensible default before anyone has looked.
  readonly property var doneStatuses: {
    var stored = setting("doneStatuses", [])
    return Array.isArray(stored) ? stored : Model.projectList(stored)
  }

  function dashboardCommand() {
    var command = [helperPath(), "--max", String(maxDisplayedTickets * 2)]
    var followed = followedProjects
    if (followed.length > 0)
      command.push("--projects", followed.join(","))
    if (wantSprint)
      command.push("--sprint")
    return command
  }

  function refresh() {
    if (fetchProcess.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    loading = true
    _stdout = ""
    fetchProcess.command = dashboardCommand()
    fetchProcess.running = true
  }

  function apply(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      state = "error"
      message = qsTr("Jira returned a response this widget could not read.")
      return
    }

    state = String(data.state || "error")
    message = String(data.message || "")

    if (String(data.site || "") !== "")
      site = String(data.site)
    if (String(data.account || "") !== "")
      account = String(data.account)

    if (state !== "ok")
      return

    tickets = Array.isArray(data.tickets) ? data.tickets : []
    projects = Array.isArray(data.projects) ? data.projects : []
    sprint = data.sprint || null
    sprintState = String(data.sprintState || "off")
    fetchedAt = String(data.generatedAt || "")
  }

  // A ticket the widget has never heard of has no local match, so search always
  // asks the helper as well. The panel merges both sides.
  function search(query) {
    searchQuery = String(query || "")
    if (searchQuery.trim() === "") {
      clearSearch()
      return
    }
    if (searchProcess.running)
      searchProcess.running = false
    _searchStdout = ""
    var command = [helperPath(), "--search", searchQuery]
    if (followedProjects.length > 0)
      command.push("--projects", followedProjects.join(","))
    searchProcess.command = command
    searchProcess.running = true
  }

  function clearSearch() {
    searchQuery = ""
    searchResults = []
    answeredQuery = ""
    if (searchProcess.running)
      searchProcess.running = false
  }

  // The results are posted before the query they answer, so there is no moment
  // where answeredQuery matches the input but the list is still the old one.
  function applySearch(raw, query) {
    try {
      var data = JSON.parse(String(raw || ""))
      searchResults = (String(data.state || "") === "ok" && Array.isArray(data.tickets)) ? data.tickets : []
    } catch (error) {
      searchResults = []
    }
    answeredQuery = String(query || "")
  }

  visible: false

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProcess

    running: false
    command: []
    onExited: function (exitCode) {
      root.loading = false
      var output = String(collector.text || root._stdout || "")
      if (output.trim() !== "") {
        root.apply(output)
      } else {
        root.state = "error"
        root.message = qsTr("The Jira helper produced no output.")
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }

    stdout: StdioCollector {
      id: collector

      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
  }

  Process {
    id: searchProcess

    running: false
    command: []
    onExited: function (exitCode) {
      root.applySearch(String(searchCollector.text || root._searchStdout || ""), root.searchQuery)
    }

    stdout: StdioCollector {
      id: searchCollector

      waitForEnd: true
      onStreamFinished: root._searchStdout = text
    }
  }
}
