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

  function toggleProject(key) {
    setSetting("followedProjects", Model.toggleFollowedProject(followedProjects, key, allProjectKeys()))
    jira.refresh()
  }

  // The local filter follows the field itself, so matches among the tickets
  // already in memory appear on the keystroke. The remote results arrive later,
  // after the field's debounce, and merge into the same list.
  readonly property bool searchActive: searchField.query.trim() !== ""

  // The panel is searching from the first keystroke until the remote answer
  // lands, covering the debounce as well as the request. Without this the empty
  // state claims there is nothing to find while the query is still in flight.
  readonly property bool searching: searchActive && (searchField.pending || jira.searching)

  onSearchActiveChanged: highlightedKey = ""

  // One flat list of every visible row, in display order. Keyboard navigation
  // walks this rather than the groups, so j and k cross a section boundary the
  // same way they cross a row.
  readonly property var visibleTickets: {
    if (searchActive)
      return Model.rankByProject(
        Model.mergeSearchResults(Model.filterTickets(jira.tickets, searchField.query), jira.searchResults),
        root.followedProjects)
    var groups = Model.groupTickets(jira.tickets)
    return Model.limit(groups.waiting, jira.maxDisplayedTickets)
      .concat(Model.limit(groups.assigned, jira.maxDisplayedTickets))
  }
  readonly property var waitingRows: (showSettings || searchActive) ? [] : decorate(Model.limit(Model.groupTickets(jira.tickets).waiting, jira.maxDisplayedTickets))
  readonly property var assignedRows: (showSettings || searchActive) ? [] : decorate(Model.limit(Model.groupTickets(jira.tickets).assigned, jira.maxDisplayedTickets))
  readonly property var searchRows: (showSettings || !searchActive) ? [] : decorate(visibleTickets)

  // Relative ages are computed once per render pass rather than per row, and
  // stamped onto the copies the rows receive. Rows stay free of clock access.
  function decorate(rows) {
    var now = Date.now()
    var decorated = []
    for (var i = 0; i < rows.length; i++) {
      var source = rows[i]
      var copy = {}
      for (var name in source) {
        if (Object.prototype.hasOwnProperty.call(source, name))
          copy[name] = source[name]
      }
      copy.age = Model.relativeTime(source.updated, now)
      decorated.push(copy)
    }
    return decorated
  }

  function ticketAt(key) {
    for (var i = 0; i < visibleTickets.length; i++) {
      if (String(visibleTickets[i].key || "") === key)
        return visibleTickets[i]
    }
    return null
  }

  function moveHighlight(delta) {
    if (visibleTickets.length === 0)
      return
    var index = -1
    for (var i = 0; i < visibleTickets.length; i++) {
      if (String(visibleTickets[i].key || "") === highlightedKey) {
        index = i
        break
      }
    }
    index = index === -1 ? (delta > 0 ? 0 : visibleTickets.length - 1) : index + delta
    index = Math.max(0, Math.min(visibleTickets.length - 1, index))
    highlightedKey = String(visibleTickets[index].key || "")
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
    clipboard.text = key
    clipboard.selectAll()
    clipboard.copy()
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
    id: confirmationTimer

    interval: 1500
    repeat: false
    onTriggered: {
      root.confirmedKey = ""
      root.confirmation = ""
    }
  }

  // Qt has no clipboard API outside Widgets, so an off-screen TextEdit is the
  // usual way to reach it from a shell. It is never shown or focused.
  TextEdit {
    id: clipboard

    visible: false
    width: 0
    height: 0
  }

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
          spacing: Style.space(8)

          PanelHero {
            width: parent.width
            title: jira.site !== "" ? "Jira · " + jira.site : "Jira"
            foreground: root.foreground
            fontFamily: root.fontFamily
            meta: {
              if (root.showSettings)
                return qsTr("Settings")
              if (jira.loading && !jira.hasData)
                return qsTr("Loading")
              if (jira.state !== "ok")
                return jira.message
              return jira.waitingCount + qsTr(" in progress · ") + jira.assignedCount + qsTr(" to do")
            }

            // A gear to reach the settings page, and a back arrow to leave it.
            // The comma key does the same thing without the mouse.
            trailingControl: Component {
              Rectangle {
                // Sized as a button rather than as a glyph: the previous box
                // was the size of the icon itself, which is a hard target to
                // hit with a mouse.
                width: Style.space(16)
                height: Style.space(16)
                radius: Style.cornerRadius
                color: gearHover.hovered || root.showSettings
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                  : "transparent"

                HoverHandler { id: gearHover }
                TapHandler { onTapped: root.showSettings = !root.showSettings }

                Text {
                  id: gearLabel

                  anchors.centerIn: parent
                  text: root.showSettings ? "\uf053" : "\uf013"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }

          JiraSearchField {
            id: searchField

            width: parent.width
            visible: !root.showSettings
            busy: jira.searching
            foreground: root.foreground
            fontFamily: root.fontFamily
            onQuerySubmitted: function (value) { jira.search(value) }
            onMoveRequested: function (delta) { root.moveHighlight(delta) }
            // Enter opens the highlighted row if there is one. With nothing
            // highlighted it means "search now", which is what someone who just
            // pasted a key is asking for.
            onActivated: {
              if (root.highlightedKey !== "")
                root.openTicket(root.highlightedKey)
              else
                jira.search(searchField.query)
            }
            onDismissed: {
              jira.clearSearch()
              keyCatcher.forceActiveFocus()
            }
          }

          TicketList {
            width: parent.width
            title: qsTr("IN PROGRESS")
            tickets: root.waitingRows
            highlightedKey: root.highlightedKey
            confirmedKey: root.confirmedKey
            confirmation: root.confirmation
            foreground: root.foreground
            fontFamily: root.fontFamily
            onTicketActivated: function (key) { root.openTicket(key) }
            onTicketKeyRequested: function (key) { root.copyKey(key) }
          }

          TicketList {
            width: parent.width
            title: qsTr("TO DO")
            tickets: root.assignedRows
            highlightedKey: root.highlightedKey
            confirmedKey: root.confirmedKey
            confirmation: root.confirmation
            foreground: root.foreground
            fontFamily: root.fontFamily
            onTicketActivated: function (key) { root.openTicket(key) }
            onTicketKeyRequested: function (key) { root.copyKey(key) }
          }

          TicketList {
            width: parent.width
            title: qsTr("RESULTS")
            tickets: root.searchRows
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
            onProjectToggled: function (key) { root.toggleProject(key) }
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
