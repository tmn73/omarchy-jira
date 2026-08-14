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

  property var sprint: null
  property string sprintState: "off"
  property var sprintBars: []
  property string estimateCoverage: ""
  property var doneStatuses: []

  signal projectToggled(string key)
  signal allProjectsCleared()
  signal sprintBarToggled(string id)
  signal doneStatusToggled(string name)

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.9)
  readonly property bool followingAll: !followedProjects || followedProjects.length === 0

  function countsAsDone(name) {
    for (var i = 0; i < doneStatuses.length; i++) {
      if (String(doneStatuses[i]).toLowerCase() === String(name).toLowerCase())
        return true
    }
    return false
  }

  function showsBar(id) {
    return sprintBars.indexOf(String(id).toLowerCase()) !== -1
  }

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

  // ---- Sprint

  SectionTitle { text: qsTr("SPRINT") }

  Text {
    width: parent.width
    text: qsTr("Which progress bars to show above your tickets. Untick them all to turn the section off and stop asking Jira for it.")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  ToggleRow {
    label: qsTr("Time")
    hint: qsTr("How much of the sprint has elapsed")
    checked: root.showsBar("time")
    onActivated: root.sprintBarToggled("time")
  }

  ToggleRow {
    label: qsTr("Tickets")
    hint: qsTr("Tickets finished out of the whole sprint")
    checked: root.showsBar("tickets")
    onActivated: root.sprintBarToggled("tickets")
  }

  ToggleRow {
    label: qsTr("Story points")
    // The coverage is the point of showing it here: counting points is
    // misleading on a sprint where most tickets carry no estimate, and this is
    // where someone decides whether to trust that bar.
    hint: root.estimateCoverage !== "" ? root.estimateCoverage : qsTr("Points finished out of the whole sprint")
    checked: root.showsBar("points")
    onActivated: root.sprintBarToggled("points")
  }

  Text {
    width: parent.width
    visible: root.sprintBars.length > 0
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    text: {
      if (root.sprintState === "no-project")
        return qsTr("Pick a project above to choose which board's sprint is shown.")
      if (root.sprintState === "none")
        return qsTr("That board has no sprint running.")
      if (root.sprintState === "no-board")
        return qsTr("That project has no board.")
      if (root.sprintState === "derived")
        return qsTr("Read from your tickets, because this token cannot read boards. A sprint holding no ticket stays hidden. Add the Jira Software scopes to your API token to read it directly.")
      if (root.sprintState === "partial")
        return qsTr("The sprint was found but its contents could not be counted.")
      if (root.sprintState === "unavailable")
        return qsTr("Jira did not answer for the sprint.")
      return ""
    }
  }

  // ---- What counts as finished
  //
  // Jira's own categories are only a starting point. A team that calls
  // "Ready to Merge" finished is right about its own board, and a progress bar
  // that disagrees with the people reading it is worse than no bar at all.

  SectionTitle {
    text: qsTr("COUNTS AS DONE")
    visible: root.sprint !== null && root.sprintBars.length > 0
  }

  Text {
    width: parent.width
    visible: root.sprint !== null && root.sprintBars.length > 0
    text: qsTr("The statuses in this sprint. Tick the ones your team treats as finished.")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: (root.sprint !== null && root.sprintBars.length > 0) ? (root.sprint.statuses || []) : []

    ToggleRow {
      required property var modelData

      label: String(modelData.name || "")
      hint: modelData.count + (modelData.count === 1 ? qsTr(" ticket") : qsTr(" tickets"))
      checked: root.countsAsDone(String(modelData.name || ""))
      onActivated: root.doneStatusToggled(String(modelData.name || ""))
    }
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
