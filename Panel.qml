import QtQuick
import qs.Commons
import qs.Ui

// Bar entry point for the Jira widget.
//
// This file owns layout, keyboard focus, and which component renders what. It
// deliberately draws no ticket row and interprets no payload field of its own:
// rows belong to TicketRow, payload meaning belongs to Model.js, and scheduling
// belongs to Service.qml. That split is what keeps this file readable as the
// widget grows.
Panel {
  id: root

  moduleName: "tmn73.jira"
  // The base Panel registers open, close, show, hide and toggle on this target
  // by itself. Declaring a second IpcHandler here would shadow it and log a
  // duplicate registration warning, so the widget only takes ipc over when it
  // has something of its own to expose.
  ipcTarget: "tmn73.jira"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    // nf-dev-jira
    text: ""
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel

    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher

      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content

        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Jira"
          meta: qsTr("Not connected yet")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
