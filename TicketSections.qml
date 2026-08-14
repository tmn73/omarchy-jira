import QtQuick
import qs.Commons

// The three ticket groups, and the rules about which of them exist at once.
//
// Search replaces the two dashboard groups rather than adding to them: while
// someone is looking for a specific ticket, their own backlog is noise. Each
// group hides itself when empty, so the panel never shows a heading with
// nothing under it.
Column {
  id: root

  property var waitingRows: []
  property var assignedRows: []
  property var searchRows: []
  property bool searchActive: false
  property string highlightedKey: ""
  property string confirmedKey: ""
  property string confirmation: ""
  property color foreground: "white"
  property string fontFamily: ""

  signal ticketActivated(string key)
  signal ticketKeyRequested(string key)

  width: parent ? parent.width : 0
  spacing: Style.space(10)

  component Section: TicketList {
    width: root.width
    highlightedKey: root.highlightedKey
    confirmedKey: root.confirmedKey
    confirmation: root.confirmation
    foreground: root.foreground
    fontFamily: root.fontFamily
    onTicketActivated: function (key) { root.ticketActivated(key) }
    onTicketKeyRequested: function (key) { root.ticketKeyRequested(key) }
  }

  Section {
    title: qsTr("IN PROGRESS")
    tickets: root.searchActive ? [] : root.waitingRows
  }

  Section {
    title: qsTr("TO DO")
    tickets: root.searchActive ? [] : root.assignedRows
  }

  Section {
    title: qsTr("RESULTS")
    tickets: root.searchActive ? root.searchRows : []
  }
}
