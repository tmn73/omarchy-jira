import QtQuick
import qs.Commons

// The search input.
//
// Typing filters what is already loaded immediately, and a remote query fires
// only after a short pause. The pause exists because a keystroke costs an API
// call otherwise, and because the local matches already give instant feedback
// while it runs.
Rectangle {
  id: root

  property string query: ""
  property bool busy: false
  property color foreground: "white"
  property string fontFamily: ""
  property int debounceMs: 300

  // No queryChanged signal is declared here: `property string query` already
  // generates one, and redeclaring it invalidates every signal on the
  // component. Consumers bind to `query` for per-keystroke work and listen to
  // querySubmitted for the debounced remote call.
  signal querySubmitted(string value)
  signal dismissed()

  // The focus that matters is the input's, not the container's, and the panel
  // needs it to know when to stop treating letters as shortcuts.
  readonly property alias inputFocused: input.activeFocus
  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.9)

  // Not named forceActiveFocus: that is already a method of Item, and
  // redeclaring it silently invalidates other members of this component.
  // Focusing the container would also be useless here, since the focus that
  // matters belongs to the input inside it.
  function focusInput() {
    input.forceActiveFocus()
  }

  width: parent ? parent.width : 0
  height: input.implicitHeight + Style.space(6)
  radius: Style.cornerRadius
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, input.activeFocus ? 0.1 : 0.05)

  Timer {
    id: debounce

    interval: root.debounceMs
    repeat: false
    onTriggered: root.querySubmitted(root.query)
  }

  Text {
    id: prompt

    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    text: root.busy ? "\uf110" : "\uf002"
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  TextInput {
    id: input

    anchors.left: prompt.right
    anchors.right: parent.right
    anchors.leftMargin: Style.space(3)
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    selectByMouse: true
    clip: true

    onTextChanged: {
      root.query = text
      if (text.trim() === "") {
        debounce.stop()
        root.querySubmitted("")
      } else {
        debounce.restart()
      }
    }

    // Enter skips the wait. Someone who just pasted an issue key should not sit
    // through a debounce they did not ask for.
    Keys.onReturnPressed: {
      debounce.stop()
      root.querySubmitted(root.query)
    }
    Keys.onEnterPressed: {
      debounce.stop()
      root.querySubmitted(root.query)
    }

    // Escape clears a non empty field before it gives up focus, so the first
    // press never closes the panel out from under someone mid-search.
    Keys.onEscapePressed: function (event) {
      if (input.text !== "") {
        input.text = ""
        event.accepted = true
        return
      }
      root.dismissed()
      event.accepted = true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: input.text === "" && !input.activeFocus
      text: qsTr("Search any ticket by key or title")
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
