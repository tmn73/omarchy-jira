import QtQuick
import qs.Commons

// The active sprint: its name, and one bar per measure the user asked for.
//
// The bars are stacked and share a common left edge and width, because their
// only real job is to be compared to each other. Time running ahead of work is
// the whole reason this section exists, and that is only legible when the bars
// line up.
Column {
  id: root

  property var sprint: null
  property var bars: []
  property string sprintState: "off"
  property color foreground: "white"
  property string fontFamily: ""

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.9)
  readonly property bool hasSprint: sprint !== null && sprint !== undefined
  // Measured rather than guessed, so the column fits whatever the labels turn
  // out to be, in any font or translation.
  readonly property real labelWidth: labelMetrics.width + Style.space(4)

  TextMetrics {
    id: labelMetrics

    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "tickets"
  }

  width: parent ? parent.width : 0
  spacing: Style.space(2)
  visible: hasSprint && bars.length > 0

  Text {
    width: parent.width
    text: root.hasSprint ? String(root.sprint.name || "") : ""
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    elide: Text.ElideRight
  }

  Repeater {
    model: root.bars

    Row {
      id: barRow

      required property var modelData

      width: parent ? parent.width : 0
      spacing: Style.space(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: root.labelWidth
        text: barRow.modelData.label
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: barRow.width - root.labelWidth - detail.width - Style.space(6)
        height: Style.space(3)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

        Rectangle {
          width: parent.width * Math.max(0, Math.min(100, barRow.modelData.percent)) / 100
          height: parent.height
          radius: parent.radius
          // Time is drawn dimmer than work: it is the reference the other bars
          // are read against, not a result of its own.
          color: barRow.modelData.id === "time"
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
            : root.foreground

          Behavior on width {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }
        }
      }

      Text {
        id: detail

        anchors.verticalCenter: parent.verticalCenter
        text: barRow.modelData.detail
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

}
