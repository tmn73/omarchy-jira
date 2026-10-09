import QtQuick
import qs.Commons

// The settings toggle in the panel header.
//
// Sized as a button rather than as a glyph: a target the size of its own icon
// is a target people miss.
Rectangle {
  id: root

  property bool active: false
  property color foreground: "white"
  property string fontFamily: ""

  signal toggled()

  width: Style.space(16)
  height: Style.space(16)
  radius: Style.cornerRadius
  color: hover.hovered || active
    ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.1)
    : "transparent"

  HoverHandler { id: hover }
  TapHandler { onTapped: root.toggled() }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    // A gear going in, an arrow coming back.
    text: root.active ? "\uf053" : "\uf013"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
