import QtQuick
import qs.Commons

// The active sprint: its name, how long is left, and one bar per measure.
//
// Two decisions drive the layout.
//
// The bars share a left edge and a width, because their only job is to be
// compared to each other. Time is drawn first and dimmed: it is the ruler the
// others are read against, not a result of its own.
//
// Whether the work is keeping up with the clock is shown by a mark, never by a
// colour. A theme is free to define its accent and its alert colour as the same
// hue, and several do, so a red-means-late scheme would silently say nothing on
// those themes while still implying a distinction on the others. The mark works
// everywhere, and colour is left to do what it does in every other widget:
// follow the theme.
Column {
  id: root

  property var sprint: null
  property var bars: []
  property string timeLeft: ""
  property color foreground: "white"
  property string fontFamily: ""

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 2.1)
  readonly property bool hasSprint: sprint !== null && sprint !== undefined
  // Measured rather than guessed, so the columns fit whatever the labels turn
  // out to be, in any font or translation.
  readonly property real labelWidth: labelMetrics.width + Style.space(6)
  readonly property real detailWidth: detailMetrics.width + Style.space(4)

  TextMetrics {
    id: labelMetrics

    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "tickets"
  }

  TextMetrics {
    id: detailMetrics

    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "000/000"
  }

  width: parent ? parent.width : 0
  spacing: Style.space(5)
  visible: hasSprint && bars.length > 0

  // The sprint name and what is left of it, on one line. The remaining time is
  // a fact about the sprint rather than a measure of progress, so it belongs
  // here instead of being tacked onto the end of a bar.
  Item {
    width: parent.width
    height: Math.max(sprintName.height, timeLabel.height)

    Text {
      id: sprintName

      anchors.left: parent.left
      anchors.right: timeLabel.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: root.hasSprint ? String(root.sprint.name || "") : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      id: timeLabel

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.timeLeft
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: root.bars

      Item {
        id: barRow

        required property var modelData

        readonly property bool isReference: modelData.id === "time"

        width: parent ? parent.width : 0
        height: Math.max(barLabel.height, track.height)

        Text {
          id: barLabel

          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: root.labelWidth
          text: barRow.modelData.label
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Rectangle {
          id: track

          anchors.left: barLabel.right
          anchors.right: parent.right
          anchors.rightMargin: barRow.modelData.detail !== "" ? root.detailWidth : 0
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(4)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

          Rectangle {
            width: parent.width * Math.max(0, Math.min(100, barRow.modelData.percent)) / 100
            height: parent.height
            radius: parent.radius
            color: barRow.isReference
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
              : Color.accent

            Behavior on width {
              NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
          }

          // Where the clock stands on this bar.
          //
          // The colour already says whether the work is keeping up, but colour
          // alone is not a signal: this user's theme paints its alert colour
          // green, and plenty of people cannot separate the two hues anyway.
          // A mark to be ahead of or behind works in any theme and any eyes.
          Rectangle {
            visible: barRow.modelData.mark !== null && barRow.modelData.mark !== undefined
            x: parent.width * Math.max(0, Math.min(100, barRow.modelData.mark || 0)) / 100
            width: Math.max(1, Style.spacing.hairline)
            height: parent.height + Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            opacity: 0.55
          }
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: barRow.modelData.detail !== ""
          text: barRow.modelData.detail
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }
}
