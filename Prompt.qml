import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Omarchy Secrets password prompt. rbw runs bin/pinentry-omarchy whenever it
// needs the master password; that asks this service over IPC to show the same
// card Omarchy uses for polkit, and gets the answer back through a private FIFO
// it created in $XDG_RUNTIME_DIR. The password never touches disk, a command
// line, or the environment.
//
// The card stays up while rbw checks the password: a wrong one comes straight
// back as the next request (red, shake, "attempt 2 of 3"), a right one unlocks
// rbw and the card closes.
Item {
  id: root

  // Omarchy's authentication look, from the [polkit] section of the theme.
  property string fontFamily: Style.font.menuFamily
  property color accent: Color.polkit.accent
  property color background: Color.polkit.background
  property color foreground: Color.polkit.text
  property color border: Color.polkit.border
  property color borderError: Color.polkit.borderError
  property var borderSpec: Border.surfaceSpec("polkit", errorFlash ? "border-error" : "border", errorFlash ? borderError : border, Math.max(1, Style.space(2)), "border-alpha")
  property color scrim: Color.polkit.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int fieldHeight: Math.max(Style.space(42), Style.spacing.controlHeight)
  readonly property int cardHeight: fieldHeight + contentMargin * 2
  readonly property int cardWidth: Math.min(Style.space(312), Math.max(Style.space(260), panel.width - Style.gapsOut * 2))

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""

  // The FIFO of the pinentry waiting for an answer; empty when none is.
  property string replyPath: ""
  property string label: ""
  property string placeholder: "Enter password"
  property bool responseVisible: false
  property bool submitted: false
  property bool closing: false
  property bool errorFlash: false
  property int shakeOffset: 0
  property var targetScreen: null
  property int checks: 0

  readonly property bool dialogVisible: replyPath !== "" || submitted || closing

  function validReplyPath(path) {
    var prefix = runtimeDir + "/secrets-pinentry."
    return runtimeDir !== "" && path.indexOf(prefix) === 0 && /^[A-Za-z0-9]+\/reply$/.test(path.slice(prefix.length))
  }

  function focusedScreen() {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return null
  }

  function labelFor(prompt, description, error) {
    var text = /master password/i.test(prompt) ? "Unlock Bitwarden secrets" : (prompt || description || "Bitwarden")
    var attempt = /attempt (\d+)\/(\d+)/.exec(error || "")
    return attempt ? text + " · attempt " + attempt[1] + " of " + attempt[2] : text
  }

  function ask(path, prompt, description, error) {
    if (!validReplyPath(path)) return false
    if (replyPath !== "" && replyPath !== path) reply(replyPath, "cancel")

    closeTimer.stop()
    checkTimer.stop()
    closing = false
    submitted = false
    passwordInput.text = ""
    if (!panel.visible) targetScreen = focusedScreen()

    replyPath = path
    label = labelFor(prompt, description, error)
    // Passwords are masked; one-time codes (rbw login's 2FA) are shown.
    responseVisible = !/password|passphrase|secret|pin\b/i.test(prompt)
    placeholder = responseVisible ? "Enter code" : "Enter password"

    if (error) triggerFailureFeedback()
    else Qt.callLater(refocus)
    return true
  }

  function refocus() {
    if (!dialogVisible) return
    if (replyPath !== "") passwordInput.forceActiveFocus()
    else keyCatcher.forceActiveFocus()
  }

  function submitResponse() {
    if (replyPath === "") return
    reply(replyPath, "ok:" + passwordInput.text)
    replyPath = ""
    passwordInput.text = ""
    submitted = true
    errorFlash = false
    keyCatcher.forceActiveFocus()
    checks = 0
    checkTimer.restart()
  }

  function cancelRequest() {
    if (replyPath !== "") reply(replyPath, "cancel")
    replyPath = ""
    close()
  }

  // The pinentry gave up (rbw stopped waiting, or it timed out).
  function dismiss(path) {
    if (path !== replyPath) return
    replyPath = ""
    close()
  }

  function close() {
    passwordInput.text = ""
    submitted = false
    checkTimer.stop()
    closing = true
    closeTimer.restart()
  }

  function triggerFailureFeedback() {
    errorFlash = true
    errorTimer.restart()
    shakeAnimation.restart()
    Qt.callLater(refocus)
  }

  function reply(path, message) {
    if (!validReplyPath(path)) return
    var writer = replyWriter.createObject(root, {
      payload: message,
      command: ["sh", "-c", "[ -p \"$1\" ] && exec cat > \"$1\"", "sh", path]
    })
    writer.running = true
  }

  // One short-lived writer per answer: the text goes in on stdin, never argv.
  Component {
    id: replyWriter

    Process {
      property string payload: ""
      stdinEnabled: true
      onStarted: {
        write(payload + "\n")
        payload = ""
        stdinEnabled = false
      }
      onExited: destroy()
    }
  }

  // After an answer: close once rbw is unlocked. A wrong password arrives as a
  // new request before this gives up.
  Timer {
    id: checkTimer
    interval: 250
    repeat: true
    onTriggered: {
      root.checks += 1
      if (root.checks > 32) root.close()
      else if (!unlockedProcess.running) unlockedProcess.running = true
    }
  }

  Process {
    id: unlockedProcess
    command: ["rbw", "unlocked"]
    onExited: function(exitCode) {
      if (exitCode === 0 && root.submitted) root.close()
    }
  }

  Timer {
    id: closeTimer
    interval: 300
    onTriggered: root.closing = false
  }

  Timer {
    id: errorTimer
    interval: 1200
    onTriggered: root.errorFlash = false
  }

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
  }

  IpcHandler {
    target: "chickymonkeys.secrets"

    function ask(reply: string, prompt: string, description: string, error: string): string {
      return root.ask(reply, prompt, description, error) ? "ok" : "refused"
    }

    function pending(reply: string): string {
      return reply !== "" && reply === root.replyPath ? "yes" : "no"
    }

    function dismiss(reply: string): void {
      root.dismiss(reply)
    }
  }

  PanelWindow {
    id: panel
    visible: root.dialogVisible
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-secrets"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.refocus()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.shakeOffset
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.cancelRequest()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submitResponse()
            event.accepted = true
          }
        }
      }

      Row {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(14)

        Text {
          text: "󰌆"
          color: root.errorFlash ? Color.polkit.textError : root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
          width: Style.space(26)
          height: root.fieldHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Item {
          width: parent.width - Style.space(40)
          height: root.fieldHeight

          TextInput {
            id: passwordInput
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            activeFocusOnPress: true
            clip: true
            selectionColor: Util.alpha(root.accent, 0.45)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
            echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
            passwordCharacter: "•"
            color: root.errorFlash ? Color.polkit.textError : root.foreground
            cursorVisible: activeFocus && !root.submitted && !root.errorFlash
            readOnly: root.submitted || root.replyPath === ""
            enabled: root.dialogVisible
            onAccepted: root.submitResponse()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelRequest()
                event.accepted = true
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.errorFlash ? "Wrong" : (root.submitted ? "Checking..." : root.placeholder)
            color: root.errorFlash ? Color.polkit.textError : root.foreground
            opacity: root.errorFlash ? 1 : 0.36
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
            elide: Text.ElideRight
            visible: passwordInput.text.length === 0
          }

          Rectangle {
            width: Math.max(1, Style.space(2))
            height: Style.space(24)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: root.errorFlash ? Color.polkit.textError : root.foreground
            visible: passwordInput.activeFocus && passwordInput.text.length === 0 && !root.submitted && !root.errorFlash
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: passwordInput.forceActiveFocus()
          }
        }
      }
    }

    Rectangle {
      width: Math.min(labelText.implicitWidth + Style.space(24), panel.width - Style.gapsOut * 2)
      height: Style.space(28)
      anchors.horizontalCenter: card.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: Style.space(10)
      radius: root.cornerRadius
      color: root.background

      Text {
        id: labelText
        textFormat: Text.PlainText
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
      }
    }
  }
}
