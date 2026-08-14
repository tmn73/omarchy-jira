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

  // The local filter follows the field itself, so matches among the tickets
  // already in memory appear on the keystroke. The remote results arrive later,
  // after the field's debounce, and merge into the same list.
  readonly property bool searchActive: search.query.trim() !== ""

  // One flat list of every visible row, in display order. Keyboard navigation
  // walks this rather than the groups, so j and k cross a section boundary the
  // same way they cross a row.
  readonly property var visibleTickets: {
    if (searchActive)
      return Model.mergeSearchResults(Model.filterTickets(jira.tickets, search.query), jira.searchResults)
    var groups = Model.groupTickets(jira.tickets)
    return Model.limit(groups.waiting, jira.maxDisplayedTickets)
      .concat(Model.limit(groups.assigned, jira.maxDisplayedTickets))
  }
  readonly property var waitingRows: searchActive ? [] : decorate(Model.limit(Model.groupTickets(jira.tickets).waiting, jira.maxDisplayedTickets))
  readonly property var assignedRows: searchActive ? [] : decorate(Model.limit(Model.groupTickets(jira.tickets).assigned, jira.maxDisplayedTickets))
  readonly property var searchRows: searchActive ? decorate(visibleTickets) : []

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
    // The count goes in the button's own text rather than in a child item:
    // WidgetButton renders its glyph from `text`, and an added child covers it.
    // Hidden at zero, so a quiet day leaves a quiet bar.
    text: jira.barCount > 0 ? "\ue75c " + jira.barCount : "\ue75c"
    active: jira.barCount > 0
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
      blocked: search.inputFocused
      onMoveRequested: function (dx, dy) { if (dy !== 0) root.moveHighlight(dy) }
      onActivateRequested: root.activateHighlighted()
      onCloseRequested: root.close()
      onTabRequested: Qt.callLater(function () { search.focusInput() })
      onTextKey: function (character) {
        var key = String(character || "").toLowerCase()
        if (key === "r")
          jira.refresh()
        else if (key === "/")
          Qt.callLater(function () { search.focusInput() })
        else if (key === "y")
          root.copyKey(root.highlightedKey)
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
              if (jira.loading && !jira.hasData)
                return qsTr("Loading")
              if (jira.state !== "ok")
                return jira.message
              return jira.waitingCount + qsTr(" waiting · ") + jira.assignedCount + qsTr(" assigned")
            }
          }

          JiraSearchField {
            id: search

            width: parent.width
            busy: jira.searching
            foreground: root.foreground
            fontFamily: root.fontFamily
            onQuerySubmitted: function (value) { jira.search(value) }
            onDismissed: {
              jira.clearSearch()
              keyCatcher.forceActiveFocus()
            }
          }

          TicketList {
            width: parent.width
            title: qsTr("WAITING ON YOU")
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
            title: qsTr("ASSIGNED")
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
            visible: root.visibleTickets.length === 0
            state: jira.loading && !jira.hasData ? "loading" : jira.state
            message: jira.message
            fetchedAt: jira.fetchedAt
            hasStaleData: jira.hasData && jira.state !== "ok"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }
      }
    }
  }
}
