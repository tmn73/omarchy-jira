import QtQuick
import qs.Commons

// The message shown when there are no rows to show.
//
// Six states, each with its own wording and its own next step. They are kept
// together here, rather than spread through the panel, because the difference
// between them is the whole point: telling someone their keyring is locked when
// their token actually expired sends them to fix the wrong thing.
Column {
  id: root

  property string state: "loading"
  property string message: ""
  property string fetchedAt: ""
  property bool hasStaleData: false
  property bool searchActive: false
  property color foreground: "white"
  property string fontFamily: ""

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.9)

  readonly property string headline: {
    switch (state) {
    case "loading":
      return qsTr("Loading")
    case "searching":
      return qsTr("Searching")
    case "ok":
      return searchActive ? qsTr("No results") : qsTr("Nothing on your plate")
    case "unconfigured":
      return qsTr("Not connected")
    case "keyring-unavailable":
      return qsTr("Keyring unavailable")
    case "unauthorized":
      return qsTr("Token rejected")
    case "forbidden":
      return qsTr("Not permitted")
    case "network-error":
      return qsTr("Jira unreachable")
    default:
      return qsTr("Something went wrong")
    }
  }

  readonly property string detail: {
    // While a query is in flight, saying nothing was found would be a claim the
    // panel cannot yet make.
    if (state === "searching")
      return qsTr("Asking Jira.")
    if (state === "ok" && searchActive)
      return qsTr("No ticket matches that search.")
    if (state === "ok")
      return qsTr("No tickets are assigned to you right now.")
    if (message !== "")
      return message
    return ""
  }

  // Only the states someone can act on get a command. Telling a user to run
  // something when the fix is "wait for the network" is noise.
  readonly property string command: {
    if (state === "unconfigured" || state === "unauthorized")
      return "omarchy-jira-auth"
    return ""
  }

  width: parent ? parent.width : 0
  spacing: Style.space(3)

  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: root.headline
    color: root.state === "ok" ? root.muted : root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    wrapMode: Text.WordWrap
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.detail !== ""
    text: root.detail
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Rectangle {
    visible: root.command !== ""
    width: commandLabel.width + Style.space(6)
    height: commandLabel.height + Style.space(3)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

    Text {
      id: commandLabel
      textFormat: Text.PlainText

      anchors.centerIn: parent
      text: root.command
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A dropped network keeps the last known tickets on screen, so this line is
  // what stops them from being mistaken for current ones.
  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.hasStaleData && root.fetchedAt !== ""
    text: qsTr("Showing the last successful refresh.")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
