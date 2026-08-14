import QtQuick

// Puts text on the system clipboard.
//
// Qt exposes no clipboard API outside QtQuick.Controls' desktop widgets, so an
// off-screen TextEdit is the usual way to reach it from a shell. It exists only
// to be copied from, and is never shown or focused.
TextEdit {
  id: root

  function put(value) {
    root.text = String(value || "")
    root.selectAll()
    root.copy()
  }

  visible: false
  width: 0
  height: 0
}
