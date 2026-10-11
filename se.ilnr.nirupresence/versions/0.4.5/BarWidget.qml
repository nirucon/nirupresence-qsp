import QtQuick 6.11
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "se.ilnr.nirupresence"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() {
    if (panelLoader.item && typeof panelLoader.item.closeForPopoutSwitch === "function") panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font globe when available; harmless monochrome fallback in normal fonts.
    text: "󰖟"
    slotSize: Style.bar.statusSlot
    tooltipText: panelLoader.item ? panelLoader.item.barTooltip : "NIRUPRESENCE"
    onPressed: function(b) {
      if (!panelLoader.item) return
      if (b === Qt.MiddleButton) panelLoader.item.refresh()
      else panelLoader.item.toggle()
    }
  }
}
