import QtQuick
import qs.Commons
import qs.Ui

// The panel header: where you are connected, what state the widget is in, and
// the way into the settings page.
//
// The subtitle is the one line that has to be true in every state, so it is
// written here in one place rather than being assembled at the call site.
PanelHero {
  id: root

  property bool showingSettings: false
  property bool loading: false
  property bool hasData: false
  property string state: "loading"
  property string message: ""
  property string site: ""
  property int inProgressCount: 0
  property int todoCount: 0

  signal settingsToggled()

  title: site !== "" ? "Jira · " + site : "Jira"

  meta: {
    if (showingSettings)
      return qsTr("Settings")
    if (loading && !hasData)
      return qsTr("Loading")
    if (state !== "ok")
      return message
    return inProgressCount + qsTr(" in progress · ") + todoCount + qsTr(" to do")
  }

  trailingControl: Component {
    GearButton {
      active: root.showingSettings
      foreground: root.foreground
      fontFamily: root.fontFamily
      onToggled: root.settingsToggled()
    }
  }
}
