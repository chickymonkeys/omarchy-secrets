import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omarchy Secrets: a variables indicator ((x), "secrets in your environment")
// that behaves like Omarchy's own (Stay Awake):
// shown while secrets are on, hidden while off until the bar's center section
// is hovered, then dimmed and clickable. It pulses while Bitwarden waits for
// the password. All logic lives in the `secrets` command, so the bar and the
// terminal always agree.
BarWidget {
  id: root
  moduleName: "chickymonkeys.secrets"

  // The `secrets` command ships inside this plugin, so the widget works
  // without anything on PATH.
  readonly property string cli: decodeURIComponent(Qt.resolvedUrl("bin/secrets").toString().replace(/^file:\/\//, ""))
  property bool enabled: false
  property bool unlocked: false
  property bool busy: false
  property string pendingAction: ""
  readonly property bool shown: enabled || busy || revealHost.revealInactiveIndicators

  // Plugins can't reach omarchy.indicators, so mirror its reveal rule: the
  // bar's center-section hover, held while the pointer is on this indicator.
  QtObject {
    id: revealHost

    property bool itemHovered: false
    readonly property bool revealInactiveIndicators: itemHovered
      || (root.bar && root.bar.centerSectionRevealHeld === true && root.bar.centerHoverRevealSuppressed !== true)

    function setIndicatorItemHovered(hovered) {
      if (hovered) {
        hideTimer.stop()
        itemHovered = true
      } else {
        hideTimer.restart()
      }
    }
  }

  Timer {
    id: hideTimer
    interval: 120
    onTriggered: revealHost.itemHovered = false
  }

  implicitWidth: shown ? indicator.implicitWidth : 0
  implicitHeight: indicator.implicitHeight
  clip: true

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function runAction(args) {
    if (busy) return
    busy = true
    pendingAction = args[0]
    actionProcess.command = [cli].concat(args)
    actionProcess.running = true
  }

  function toggle() {
    runAction([enabled ? "off" : "on"])
  }

  Process {
    id: statusProcess
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var state = JSON.parse(text)
          root.enabled = state.enabled === true
          root.unlocked = state.unlocked === true
        } catch (error) {
          return
        }
        // Bitwarden locked itself (timeout, or `rbw lock` elsewhere): turn the
        // toggle off too, so no shell asks for the password unprompted.
        if (root.enabled && !root.unlocked) root.runAction(["off", "--expired"])
      }
    }
  }

  Process {
    id: actionProcess
    onExited: {
      root.busy = false
      root.pendingAction = ""
      root.refresh()
    }
  }

  // Catches changes made from a terminal (`secrets on|off`) and lock timeouts.
  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIndicator {
    id: indicator
    anchors.verticalCenter: parent.verticalCenter
    bar: root.bar
    indicatorHost: revealHost
    maintainIndicatorReveal: true
    active: root.enabled || root.pendingAction === "on"
    activeText: "󰫧"
    activeTooltipText: root.pendingAction === "on" ? "Waiting for your Bitwarden password…" : "Lock Secrets"
    inactiveTooltipText: root.pendingAction === "off" ? "Locking secrets…" : "Unlock Secrets"
    onPressed: function() { root.toggle() }

    SequentialAnimation on scale {
      running: root.busy
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.82; duration: 450; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
    }
  }
}
