import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry point for the Jira widget.
//
// This file owns layout, keyboard focus, and which component renders what. It
// deliberately draws no ticket row and interprets no payload field of its own:
// rows belong to TicketRow, payload meaning belongs to Model.js, and scheduling
// belongs to Service.qml. That split is what keeps this file readable as the
// widget grows.
Panel {
  id: root

  moduleName: "tmn73.jira"
  ipcTarget: "tmn73.jira"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string highlightedKey: ""
  property string confirmedKey: ""
  property string confirmation: ""
  property bool showSettings: false

  readonly property var followedProjects: jira.followedProjects

  // Recomputed on the clock as well as on new data, so the time bar keeps
  // creeping forward on a panel left open.
  property int sprintTick: 0
  readonly property var sprintBars: {
    sprintTick
    return Model.sprintBars(jira.sprint, jira.sprintBarChoice, Date.now(), jira.doneStatuses)
  }

  // Writes one widget setting back to shell.json.
  //
  // The value is applied locally first so the panel reacts on the click, and
  // the shell write comes back through the bar as the same value. This is the
  // only place in the plugin that persists anything.
  function setSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) {
      if (key !== "id")
        entry[key] = root.settings[key]
    }
    entry[name] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function allProjectKeys() {
    var keys = []
    for (var i = 0; i < jira.projects.length; i++)
      keys.push(String(jira.projects[i].key || ""))
    return keys
  }

  function toggleDoneStatus(name) {
    setSetting("doneStatuses", Model.toggleDoneStatus(jira.doneStatuses, name, Model.defaultDoneStatuses(jira.sprint)))
  }

  function toggleSprintBar(id) {
    var chosen = jira.sprintBarChoice.slice()
    var at = chosen.indexOf(id.toUpperCase())
    if (at === -1)
      chosen.push(id)
    else
      chosen.splice(at, 1)
    setSetting("sprintBars", chosen)
    jira.refresh()
  }

  function toggleProject(key) {
    setSetting("followedProjects", Model.toggleFollowedProject(followedProjects, key, allProjectKeys()))
    jira.refresh()
  }

  // The local filter follows the field itself, so matches among the tickets
  // already in memory appear on the keystroke. The remote results arrive later,
  // after the field's debounce, and merge into the same list.
  readonly property bool searchActive: searchField.query.trim() !== ""

  // Searching means exactly one thing: what is on screen does not yet answer
  // what is typed. That covers the debounce, the request, and every instant in
  // between, with no flag to raise or lower at the right moment.
  readonly property string trimmedQuery: searchField.query.trim()
  readonly property bool searching: searchActive && jira.answeredQuery !== trimmedQuery

  onSearchActiveChanged: highlightedKey = ""

  // One flat list of every visible row, in display order. Keyboard navigation
  // walks this rather than the groups, so j and k cross a section boundary the
  // same way they cross a row.
  readonly property var visibleTickets: {
    if (searchActive)
      return Model.filterByProject(
        Model.mergeSearchResults(Model.filterTickets(jira.tickets, searchField.query), jira.searchResults),
        root.followedProjects)
    var groups = Model.groupTickets(jira.tickets)
    return Model.limit(groups.waiting, jira.maxDisplayedTickets)
      .concat(Model.limit(groups.assigned, jira.maxDisplayedTickets))
  }
  readonly property var waitingRows: searchActive ? [] : Model.decorateRows(Model.limit(Model.groupTickets(jira.tickets).waiting, jira.maxDisplayedTickets), Date.now())
  readonly property var assignedRows: searchActive ? [] : Model.decorateRows(Model.limit(Model.groupTickets(jira.tickets).assigned, jira.maxDisplayedTickets), Date.now())
  readonly property var searchRows: !searchActive ? [] : Model.decorateRows(visibleTickets, Date.now())

  function ticketAt(key) {
    for (var i = 0; i < visibleTickets.length; i++) {
      if (String(visibleTickets[i].key || "") === key)
        return visibleTickets[i]
    }
    return null
  }

  function moveHighlight(delta) {
    highlightedKey = Model.nextKey(visibleTickets, highlightedKey, delta)
  }

  function openTicket(key) {
    var ticket = ticketAt(key)
    if (!ticket)
      return
    var url = String(ticket.url || "")
    if (url !== "")
      Qt.openUrlExternally(url)
  }

  function copyKey(key) {
    if (key === "")
      return
    clipboard.put(key)
    confirmedKey = key
    confirmation = qsTr("Copied ") + key
    confirmationTimer.restart()
  }

  function activateHighlighted() {
    if (highlightedKey !== "")
      openTicket(highlightedKey)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      highlightedKey = ""
      showSettings = false
      searchField.clear()
      jira.clearSearch()
      jira.refresh()
      if (panelFlick)
        panelFlick.contentY = 0
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: jira

    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { jira.refresh(); return "ok" }
    function status(): string { return jira.state }
    // Exposed so the widget can be driven from a script or a keybinding, and
    // so the search path can be exercised without a keyboard.
    function search(query: string): string {
      root.open()
      root.showSettings = false
      searchField.setQuery(query)
      return "ok"
    }
    function settings(): string {
      root.open()
      root.showSettings = true
      return "ok"
    }
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.sprintTick++
  }

  Timer {
    id: confirmationTimer

    interval: 1500
    repeat: false
    onTriggered: {
      root.confirmedKey = ""
      root.confirmation = ""
    }
  }

  Clipboard { id: clipboard }

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    // The glyph alone, with no count. A number next to the icon would widen the
    // button and throw off the optical centring BarIconButton does for a single
    // glyph, and having work in progress is the normal state of a working day,
    // not something to announce in the bar.
    text: "\ue75c"
    // Red is reserved for the widget being unable to do its job: an expired
    // token, a locked keyring, an unreachable Jira. Having tickets is not an
    // alarm, and an icon that is always lit stops meaning anything.
    active: jira.needsAttention
    tooltipText: jira.tooltip
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton)
        jira.refresh()
      else
        root.toggle()
    }
  }

  KeyboardPanel {
    id: panel

    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher

      anchors.fill: parent
      blocked: searchField.inputFocused
      onMoveRequested: function (dx, dy) { if (dy !== 0) root.moveHighlight(dy) }
      onActivateRequested: root.activateHighlighted()
      onCloseRequested: root.close()
      onTabRequested: Qt.callLater(function () { searchField.focusInput() })
      onTextKey: function (character) {
        var key = String(character || "").toLowerCase()
        if (key === "r")
          jira.refresh()
        else if (key === "/")
          Qt.callLater(function () { searchField.focusInput() })
        else if (key === "y")
          root.copyKey(root.highlightedKey)
        else if (key === ",")
          root.showSettings = !root.showSettings
      }

      Flickable {
        id: panelFlick

        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content

          width: panelFlick.width
          spacing: Style.space(14)

          PanelHeader {
            width: parent.width
            showingSettings: root.showSettings
            loading: jira.loading
            hasData: jira.hasData
            state: jira.state
            message: jira.message
            site: jira.site
            inProgressCount: jira.waitingCount
            todoCount: jira.assignedCount
            foreground: root.foreground
            fontFamily: root.fontFamily
            onSettingsToggled: root.showSettings = !root.showSettings
          }

          SprintBars {
            width: parent.width
            visible: !root.showSettings
            sprint: jira.sprint
            bars: root.sprintBars
            timeLeft: Model.sprintTimeLeft(jira.sprint, Date.now())
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          JiraSearchField {
            id: searchField

            width: parent.width
            visible: !root.showSettings
            busy: root.searching
            foreground: root.foreground
            fontFamily: root.fontFamily
            onQuerySubmitted: function (value) { jira.search(String(value).trim()) }
            onMoveRequested: function (delta) { root.moveHighlight(delta) }
            // Enter opens the highlighted row if there is one. With nothing
            // highlighted it means "search now", which is what someone who just
            // pasted a key is asking for.
            onActivated: {
              if (root.highlightedKey !== "")
                root.openTicket(root.highlightedKey)
              else
                jira.search(root.trimmedQuery)
            }
            onDismissed: {
              jira.clearSearch()
              keyCatcher.forceActiveFocus()
            }
          }

          TicketSections {
            width: parent.width
            visible: !root.showSettings
            waitingRows: root.waitingRows
            assignedRows: root.assignedRows
            searchRows: root.searchRows
            searchActive: root.searchActive
            highlightedKey: root.highlightedKey
            confirmedKey: root.confirmedKey
            confirmation: root.confirmation
            foreground: root.foreground
            fontFamily: root.fontFamily
            onTicketActivated: function (key) { root.openTicket(key) }
            onTicketKeyRequested: function (key) { root.copyKey(key) }
          }

          StateNotice {
            width: parent.width
            visible: !root.showSettings && root.visibleTickets.length === 0
            state: {
              if (root.searching)
                return "searching"
              if (jira.loading && !jira.hasData)
                return "loading"
              return jira.state
            }
            message: root.searching ? "" : jira.message
            fetchedAt: jira.fetchedAt
            hasStaleData: jira.hasData && jira.state !== "ok"
            searchActive: root.searchActive
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          SettingsView {
            width: parent.width
            visible: root.showSettings
            projects: jira.projects
            followedProjects: root.followedProjects
            site: jira.site
            account: jira.account
            state: jira.state
            foreground: root.foreground
            fontFamily: root.fontFamily
            sprint: jira.sprint
            sprintState: jira.sprintState
            sprintBars: jira.sprintBarChoice
            estimateCoverage: Model.estimateCoverage(jira.sprint)
            doneStatuses: jira.doneStatuses.length > 0 ? jira.doneStatuses : Model.defaultDoneStatuses(jira.sprint)
            onProjectToggled: function (key) { root.toggleProject(key) }
            onSprintBarToggled: function (id) { root.toggleSprintBar(id) }
            onDoneStatusToggled: function (name) { root.toggleDoneStatus(name) }
            onAllProjectsCleared: {
              root.setSetting("followedProjects", [])
              jira.refresh()
            }
          }
        }
      }
    }
  }
}
