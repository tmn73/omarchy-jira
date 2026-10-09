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

  // Typing and choosing a result happen without leaving the field, the way a
  // command palette works. The field forwards the keys it has no use for
  // instead of swallowing them, which is what makes the arrows keep working
  // once someone has started typing.
  signal moveRequested(int delta)
  signal activated()

  // The panel decides when a search is outstanding, since only it knows whether
  // what is displayed answers what is typed. The field just shows it.
  readonly property bool working: busy

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

  // Sets the field as if it had been typed into, debounce and all, so a caller
  // driving the widget from outside takes exactly the same path as a keystroke.
  function setQuery(value) {
    input.text = String(value || "")
    input.forceActiveFocus()
  }

  // Empties the field without emitting a query, for when the panel closes.
  function clear() {
    debounce.stop()
    input.text = ""
    root.query = ""
  }

  function submitOrActivate() {
    debounce.stop()
    root.activated()
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

  // The leading glyph is the search state: a magnifier at rest, a spinning
  // marker while a query is on its way. A still spinner would read as a frozen
  // panel, so it only exists while it turns.
  Text {
    id: prompt
    textFormat: Text.PlainText

    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    text: root.working ? "\uf110" : "\uf002"
    color: root.working ? root.muted : root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall

    RotationAnimation on rotation {
      running: root.working
      from: 0
      to: 360
      duration: 900
      loops: Animation.Infinite
      onStopped: prompt.rotation = 0
    }
  }

  // The shortcut hint. A keyboard affordance nobody can see is a keyboard
  // affordance nobody uses, and it withdraws once the field is in use so it
  // never competes with what is being typed.
  Rectangle {
    id: shortcutHint

    anchors.right: parent.right
    anchors.rightMargin: Style.space(3)
    anchors.verticalCenter: parent.verticalCenter
    visible: !input.activeFocus && input.text === ""
    width: hintLabel.width + Style.space(4)
    height: hintLabel.height + Style.space(2)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

    Text {
      id: hintLabel
      textFormat: Text.PlainText

      anchors.centerIn: parent
      text: "/"
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  TextInput {
    id: input

    anchors.left: prompt.right
    anchors.right: shortcutHint.visible ? shortcutHint.left : parent.right
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

    // Up and down belong to the result list, not to a single line of text where
    // they would do nothing at all.
    Keys.onUpPressed: root.moveRequested(-1)
    Keys.onDownPressed: root.moveRequested(1)

    // Enter opens the highlighted result when there is one, and otherwise skips
    // the debounce: someone who just pasted an issue key should not sit through
    // a wait they did not ask for. The panel decides which case applies.
    Keys.onReturnPressed: root.submitOrActivate()
    Keys.onEnterPressed: root.submitOrActivate()

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
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: input.text === "" && !input.activeFocus
      text: qsTr("Search any ticket by key or title")
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
