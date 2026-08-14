import QtQuick
import qs.Commons

// The widget's settings page, shown in place of the ticket lists.
//
// It lives here rather than in the manifest schema because its options are not
// knowable in advance: the list of projects comes from the connected Jira site
// and differs for every user. Everything that is knowable in advance, like the
// refresh interval, stays declarative in manifest.json and is rendered by the
// shell itself.
//
// This component reads state and emits intent. It never writes shell.json.
Column {
  id: root

  property color foreground: "white"
  property string fontFamily: ""

  property var projects: []
  property var followedProjects: []
  property string site: ""
  property string account: ""
  property string state: "ok"

  signal projectToggled(string key)
  signal allProjectsCleared()

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.9)
  readonly property bool followingAll: !followedProjects || followedProjects.length === 0

  function isFollowed(key) {
    if (followingAll)
      return true
    return followedProjects.indexOf(key) !== -1
  }

  spacing: Style.space(8)

  component SectionTitle: Text {
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    font.bold: true
  }

  // A row that reads as a checkbox without pulling in a control library the
  // rest of this plugin does not use.
  component ToggleRow: Rectangle {
    id: toggle

    property string label: ""
    property string hint: ""
    property bool checked: false

    signal activated()

    width: parent ? parent.width : 0
    height: toggleBody.height + Style.space(4)
    radius: Style.cornerRadius
    color: hovered.hovered
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      : "transparent"

    HoverHandler { id: hovered }
    TapHandler { onTapped: toggle.activated() }

    Row {
      id: toggleBody

      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(3)
      anchors.rightMargin: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8)
        text: toggle.checked ? "\uf14a" : "\uf096"
        color: toggle.checked ? root.foreground : root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: toggleBody.width - Style.space(14)
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: toggle.label
          color: toggle.checked ? root.foreground : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: toggle.hint !== ""
          text: toggle.hint
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // ---- Projects

  SectionTitle { text: qsTr("PROJECTS") }

  Text {
    width: parent.width
    text: root.followingAll
      ? qsTr("Every project is included. Untick the ones you do not care about.")
      : qsTr("Ticked projects feed your lists and lead your search results. The others stay searchable.")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    width: parent.width
    visible: !root.projects || root.projects.length === 0
    text: qsTr("No projects loaded yet.")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.projects

    ToggleRow {
      required property var modelData

      label: String(modelData.key || "")
      hint: String(modelData.name || "")
      checked: root.isFollowed(String(modelData.key || ""))
      onActivated: root.projectToggled(String(modelData.key || ""))
    }
  }

  ToggleRow {
    visible: !root.followingAll
    label: qsTr("Include every project")
    hint: qsTr("Clears the selection above")
    checked: false
    onActivated: root.allProjectsCleared()
  }

  // ---- Connection. Read-only on purpose: changing the account means typing a
  //      secret, which belongs in a terminal and not in a bar popup. What
  //      belongs here is knowing whether it works.

  SectionTitle { text: qsTr("CONNECTION") }

  Text {
    width: parent.width
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    text: {
      if (root.state === "unconfigured")
        return qsTr("Not connected. Run omarchy-jira-auth in a terminal.")
      if (root.state === "unauthorized")
        return qsTr("The stored token was rejected. Run omarchy-jira-auth again.")
      if (root.site === "")
        return qsTr("Not connected.")
      return root.site + "\n" + root.account
    }
  }
}
