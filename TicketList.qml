import QtQuick
import qs.Commons
import qs.Ui

// A titled group of ticket rows.
//
// Renders nothing at all when it has no tickets, so an empty group leaves no
// orphan heading behind. That is what lets the panel declare every group up
// front and let the data decide which ones exist.
Column {
  id: root

  property string title: ""
  property var tickets: []
  property string highlightedKey: ""
  property string confirmedKey: ""
  property string confirmation: ""
  property color foreground: "white"
  property string fontFamily: ""

  signal ticketActivated(string key)
  signal ticketKeyRequested(string key)

  readonly property int count: tickets ? tickets.length : 0

  width: parent ? parent.width : 0
  spacing: Style.space(2)
  visible: count > 0

  PanelSectionHeader {
    width: parent.width
    text: root.title + "  " + root.count
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.tickets

    TicketRow {
      required property var modelData

      ticket: modelData
      highlighted: root.highlightedKey !== "" && root.highlightedKey === String(modelData.key || "")
      confirmation: root.confirmedKey !== "" && root.confirmedKey === String(modelData.key || "")
        ? root.confirmation
        : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
      onActivated: root.ticketActivated(String(modelData.key || ""))
      onKeyRequested: root.ticketKeyRequested(String(modelData.key || ""))
    }
  }
}
