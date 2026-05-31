import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

Item {
    id: root

    property var screen: root.QsWindow.window?.screen
    property var visualizerLevels: [0, 0, 0, 0, 0, 0, 0, 0]
    readonly property bool mediaPlaying: MprisController.activePlayer?.playbackState == MprisPlaybackState.Playing
    property var monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int activeWorkspaceId: monitor?.activeWorkspace?.id ?? 1

    // --- WORKSPACE STATE ---
    property bool showWorkspace: false
    property bool workspaceAutoHidePending: false
    property list<bool> workspaceOccupied: []
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((activeWorkspaceId - 1) / workspacesShown)
    property int lastShownWorkspaceId: -1

    function updateWorkspaceOccupied() {
        workspaceOccupied = Array.from({ length: workspacesShown }, (_, i) => {
            return Hyprland.workspaces.values.some(ws => ws.id === workspaceGroup * workspacesShown + i + 1);
        });
    }

    function triggerWorkspaceShow() {
        // Don't trigger before config is loaded
        if (!Config.ready) return;
        // Only show if workspace actually changed
        if (activeWorkspaceId === lastShownWorkspaceId && showWorkspace) return;
        lastShownWorkspaceId = activeWorkspaceId;
        showWorkspace = true;
        workspaceAutoHidePending = false;
        workspaceAutoHideTimer.restart();
    }

    Component.onCompleted: {
        updateWorkspaceOccupied();
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { updateWorkspaceOccupied(); }
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateWorkspaceOccupied();
            if (Config.options.island.showOnWorkspaceSwitch) {
                triggerWorkspaceShow();
            }
        }
    }

    Timer {
        id: workspaceAutoHideTimer
        interval: Config.options.island.autoHideTimeout
        repeat: false
        onTriggered: {
            if (!GlobalStates.superDown) {
                root.showWorkspace = false;
            } else {
                workspaceAutoHidePending = true;
            }
        }
    }

    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config.options.island.showOnSuperHold) return;
            if (GlobalStates.superDown) {
                root.showWorkspace = true;
                workspaceAutoHidePending = false;
                workspaceAutoHideTimer.stop();
            } else {
                // Super released — always start auto-hide timer
                workspaceAutoHidePending = false;
                workspaceAutoHideTimer.restart();
            }
        }
    }

    // --- OSD MODE ---
    readonly property bool osdActive: GlobalStates.osdVolumeOpen || GlobalStates.osdBrightnessOpen
    readonly property bool osdIsVolume: GlobalStates.osdVolumeOpen
    readonly property real osdBrightnessRaw: Brightness.getMonitorForScreen(screen)?.brightness ?? 0.5
    readonly property real osdGamma: Hyprsunset.gamma / 100
    readonly property real osdValue: osdIsVolume
        ? (Audio.sink?.audio.volume ?? 0)
        : (osdBrightnessRaw > 0
            ? (0.25 + osdBrightnessRaw * 0.75)
            : ((osdGamma - 0.25) / 0.75 * 0.25))
    readonly property string osdIcon: osdIsVolume
        ? (Audio.sink?.audio.muted ? "volume_off" : "volume_up")
        : "light_mode"
    readonly property string osdLabel: osdIsVolume ? Translation.tr("Volume") : Translation.tr("Brightness")

    // --- NOTIFICATION MODE ---
    property bool showNotification: false
    property var currentNotification: null
    property int notificationUnreadCount: 0

    Timer {
        id: notificationAutoHideTimer
        interval: 5000
        repeat: false
        onTriggered: {
            root.showNotification = false;
            root.currentNotification = null;
        }
    }

    function triggerNotificationShow() {
        if (!Config.ready) return;
        if (Notifications.popupList.length === 0) return;
        // Grab the latest popup notification
        var latestNotif = Notifications.popupList[Notifications.popupList.length - 1];
        if (latestNotif) {
            root.currentNotification = latestNotif;
            root.showNotification = true;
            notificationAutoHideTimer.restart();
        }
    }

    Connections {
        target: Notifications
        function onNotify(notif) {
            triggerNotificationShow();
        }
    }

    // --- SCREEN RECORDING DETECTION ---
    property bool isRecording: false
    property int recordingSeconds: 0
    property int recordingStartTimestamp: 0

    // --- SCREEN SHARING DETECTION ---
    property bool isScreenSharing: false

    Timer {
        id: recordingTimer
        interval: 1000
        repeat: true
        running: root.isRecording
        onTriggered: {
            root.recordingSeconds++;
        }
    }

    // Screen sharing detection: checks for active screencast consumers via PipeWire
    Process {
        id: screenShareCheckProc
        running: true
        command: ["bash", "/home/him/.config/quickshell/ii/scripts/detect-screenshare.sh"]
        stdout: SplitParser {
            onRead: function(data) {
                var val = parseInt(String(data).trim());
                if (isNaN(val)) return;
                root.isScreenSharing = (val > 0);
            }
        }
    }

    // Production recording detection
    Process {
        id: recordingCheckProc
        running: true
        command: ["bash", "-c", "while true; do count=$(pgrep -c wf-recorder 2>/dev/null); echo ${count:-0}; sleep 2; done"]
        stdout: SplitParser {
            onRead: function(data) {
                var count = parseInt(String(data).trim());
                if (isNaN(count)) return;
                var wasRecording = root.isRecording;
                root.isRecording = (count > 0);
                if (root.isRecording && !wasRecording) {
                    root.recordingStartTimestamp = Date.now();
                    root.recordingSeconds = 0;
                    recordingTimer.restart();
                } else if (!root.isRecording && wasRecording) {
                    recordingTimer.stop();
                    root.recordingSeconds = 0;
                }
            }
        }
    }

    function formatRecordingTime(secs) {
        var m = Math.floor(secs / 60);
        var s = secs % 60;
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
    }

    function setVisualizerLevels(line) {
        const points = String(line).trim().split(/[;\s]+/).map(p => parseFloat(p)).filter(p => !isNaN(p));
        if (points.length === 0)
            return;

        // CAVA ASCII outputs 0-7, normalize to 0-1 with fixed scale
        // Apply scaling + gentle curve for controlled dynamic range
        root.visualizerLevels = points.slice(0, 8).map(p => {
            const v = Math.max(0, Math.min(1, (p / 7) * 0.35)); // scale down to 35%
            return Math.pow(v, 0.5);
        });
    }

    Process {
        id: barVisualizerProc
        running: root.mediaPlaying
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => root.setVisualizerLevels(data)
        }
        onRunningChanged: {
            if (!barVisualizerProc.running)
                root.visualizerLevels = [0, 0, 0, 0, 0, 0, 0, 0];
        }
    }

    // Completely hide the original bar background
    Rectangle {
        id: barBackground
        visible: false
    }

    StyledRectangularShadow {
        target: islandShape
    }

    // Tide-like floating island: compact idle, soft stretched media pill
    Rectangle {
        id: islandShape
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2.5
        anchors.horizontalCenter: parent.horizontalCenter

        property bool isPlaying: root.mediaPlaying
        property bool isHovered: islandMouseArea.containsMouse
        readonly property bool osdActive: root.osdActive
        // Recording coexists with all states (not exclusive)
        readonly property bool isRecordingNow: root.isRecording
        readonly property bool isScreenSharingNow: root.isScreenSharing
        readonly property bool notificationActive: root.showNotification && !root.osdActive
        readonly property bool workspaceActive: root.showWorkspace && !root.osdActive && !root.showNotification

        // Base width for current state, expanded by recording indicator when active
        readonly property int baseWidth: islandShape.osdActive ? 220 : (islandShape.notificationActive ? islandShape.notifWidth : (islandShape.workspaceActive ? 160 : (isPlaying ? 180 : (isHovered ? 156 : 126))))
        readonly property int baseHeight: islandShape.osdActive ? 52 : (islandShape.notificationActive ? islandShape.notifHeight : (islandShape.workspaceActive ? 44 : (isPlaying ? 48 : (isHovered ? 44 : 40))))
        // Recording circle protrudes from the left — no width offset needed on the pill itself
        readonly property int recordingOffset: 0
        readonly property int recordingCircleSize: 40  // diameter of the protruding circles

        width: islandShape.baseWidth + islandShape.recordingOffset
        height: Math.max(islandShape.baseHeight, islandShape.isRecordingNow ? 44 : 0)
        radius: Math.round(islandShape.height / 2)

        // Dynamic notification dimensions (measured from content)
        readonly property int notifWidth: {
            if (!root.currentNotification) return 200;
            var sender = root.currentNotification?.summary || "";
            var body = (root.currentNotification?.body || "").replace(/<[^>]*>/g, "").replace(/\n/g, " ");
            var hasIcon = (root.currentNotification?.image || root.currentNotification?.appIcon) !== "";
            var iconSpace = hasIcon ? 46 : 16; // icon+margin or just padding
            var maxText = 0;
            // Measure sender width (~10px bold Inter: ~6px per char)
            var senderW = sender.length * 6.2 + 16;
            // Measure body width (~11px regular Inter: ~5.8px per char)
            var bodyW = body.length * 5.8 + 16;
            maxText = Math.max(senderW, bodyW);
            var total = iconSpace + maxText + 16; // right padding
            return Math.max(160, Math.min(380, Math.round(total)));
        }
        readonly property int notifHeight: {
            if (!root.currentNotification) return 50;
            var body = (root.currentNotification?.body || "").replace(/<[^>]*>/g, "").replace(/\n/g, " ");
            var hasIcon = (root.currentNotification?.image || root.currentNotification?.appIcon) !== "";
            if (hasIcon) {
                // sender (10px) + gap(1) + body(11px) + top/bottom padding(14) = ~42px min, expand for long text
                var lines = Math.ceil(body.length / 38); // ~38 chars per line at this width
                var h = 14 + 12 + 1 + 14 + (lines > 1 ? (lines - 1) * 13 : 0);
                return Math.max(44, Math.min(90, Math.round(h)));
            }
            return 50;
        }
        color: "#0b0b12"
        border.color: islandShape.osdActive ? "#6c7086" : (islandShape.notificationActive ? "#6c7086" : (isPlaying ? "#45475a" : "#313244"))
        border.width: islandShape.osdActive || islandShape.notificationActive ? 2 : 0
        scale: isHovered ? 1.025 : 1.0

        Behavior on width { NumberAnimation { duration: 520; easing.type: Easing.OutExpo } }
        Behavior on height { NumberAnimation { duration: 520; easing.type: Easing.OutExpo } }
        Behavior on radius { NumberAnimation { duration: 520; easing.type: Easing.OutExpo } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 220 } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: "#1f2233"
            opacity: 0.65
        }

        MouseArea {
            id: islandMouseArea
            anchors.fill: parent
            hoverEnabled: true
        }

        Item {
            anchors.fill: parent

            // Hour Label
            Text {
                id: hourLabel
                text: "00"
                color: "#cdd6f4"
                font.pixelSize: 17
                font.bold: true
                font.family: "Inter"
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: islandShape.isPlaying ? -55 : -18
                opacity: (islandShape.osdActive || islandShape.workspaceActive || islandShape.notificationActive || ((islandShape.isRecordingNow || islandShape.isScreenSharingNow) && islandShape.isHovered)) ? 0 : 1
                visible: !islandShape.osdActive && !islandShape.workspaceActive && !islandShape.notificationActive
                Behavior on anchors.horizontalCenterOffset {
                    NumberAnimation { duration: 500; easing.type: Easing.OutBack }
                }
            }

            // Colon
            Text {
                text: ":"
                color: "#cdd6f4"
                font.pixelSize: 17
                font.bold: true
                visible: !islandShape.isPlaying && !islandShape.osdActive && !islandShape.workspaceActive && !islandShape.notificationActive && !((islandShape.isRecordingNow || islandShape.isScreenSharingNow) && islandShape.isHovered)
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }

            // Minute Label
            Text {
                id: minuteLabel
                text: "00"
                color: "#cdd6f4"
                font.pixelSize: 17
                font.bold: true
                font.family: "Inter"
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: islandShape.isPlaying ? 55 : 18
                opacity: (islandShape.osdActive || islandShape.workspaceActive || islandShape.notificationActive || ((islandShape.isRecordingNow || islandShape.isScreenSharingNow) && islandShape.isHovered)) ? 0 : 1
                visible: !islandShape.osdActive && !islandShape.workspaceActive && !islandShape.notificationActive
                Behavior on anchors.horizontalCenterOffset {
                    NumberAnimation { duration: 500; easing.type: Easing.OutBack }
                }
            }

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    var date = new Date();
                    var h = date.getHours();
                    var m = date.getMinutes();
                    hourLabel.text = h < 10 ? "0" + h : h;
                    minuteLabel.text = m < 10 ? "0" + m : m;
                }
            }

            // --- TIDE-STYLE AUDIO-REACTIVE VISUALIZER ---
            Row {
                id: visualizer
                anchors.centerIn: parent
                spacing: 3
                visible: islandShape.isPlaying && !islandShape.osdActive && !islandShape.workspaceActive && !islandShape.notificationActive && !((islandShape.isRecordingNow || islandShape.isScreenSharingNow) && islandShape.isHovered)
                opacity: islandShape.isPlaying && !islandShape.osdActive && !islandShape.workspaceActive && !islandShape.notificationActive && !((islandShape.isRecordingNow || islandShape.isScreenSharingNow) && islandShape.isHovered) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }

                Repeater {
                    model: 8
                    delegate: Rectangle {
                        readonly property real rawLevel: root.visualizerLevels && root.visualizerLevels.length > index ? Number(root.visualizerLevels[index]) : 0
                        readonly property real clampedLevel: Math.max(0, Math.min(1, isNaN(rawLevel) ? 0 : rawLevel))

                        width: 5
                        height: 6 + (24 - 6) * clampedLevel
                        radius: width / 2
                        color: "#a6e3a1"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on height {
                            NumberAnimation {
                                duration: 90
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }
            }

            // --- iOS-STYLE WORKSPACE PICKER ---
            Item {
                id: workspaceContent
                anchors.fill: parent
                clip: true
                visible: islandShape.workspaceActive
                opacity: islandShape.workspaceActive ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

                // Scrolling workspace number row
                Row {
                    id: workspaceRow
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    x: {
                        // Center the active workspace number within the group
                        var activeIndex = root.activeWorkspaceId - (root.workspaceGroup * root.workspacesShown) - 1;
                        return (160 / 2) - (activeIndex * 22) - 11;
                    }
                    spacing: 0
                    z: 2

                    Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                    Repeater {
                        model: root.workspacesShown
                        delegate: Text {
                            property int wsId: root.workspaceGroup * root.workspacesShown + index + 1
                            property bool isActive: wsId === root.activeWorkspaceId

                            text: wsId
                            color: isActive ? "#ffffff" : "#45475a"
                            font.pixelSize: isActive ? 17 : 13
                            font.bold: isActive
                            font.family: "Inter"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter

                            width: 22
                            height: parent.height

                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on font.pixelSize { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                        }
                    }
                }
            }

            // --- TIDE-STYLE NOTIFICATION ---
            Item {
                id: notificationContent
                anchors.fill: parent
                clip: true
                visible: islandShape.notificationActive
                opacity: islandShape.notificationActive ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        // Dismiss current notification
                        if (root.currentNotification) {
                            Notifications.timeoutNotification(root.currentNotification.notificationId);
                        }
                        root.showNotification = false;
                        root.currentNotification = null;
                    }
                }

                // App icon (left) — try user image first, fall back to app icon
                StyledImage {
                    id: notifAppIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    source: {
                        var img = root.currentNotification?.image || "";
                        if (img !== "") return img;
                        return root.currentNotification?.appIcon || "";
                    }
                    visible: (root.currentNotification?.image || root.currentNotification?.appIcon) !== ""
                }

                // Sender name (top, right of icon)
                Text {
                    id: notifSender
                    anchors.left: notifAppIcon.right
                    anchors.leftMargin: 7
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    text: {
                        var summary = root.currentNotification?.summary || "";
                        return summary.length > 30 ? summary.substring(0, 27) + "..." : summary;
                    }
                    color: "#a6adc8"
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "Inter"
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    visible: (root.currentNotification?.image || root.currentNotification?.appIcon) !== ""
                }

                // Message body (under sender name)
                Text {
                    anchors.left: notifAppIcon.right
                    anchors.leftMargin: 7
                    anchors.top: notifSender.bottom
                    anchors.topMargin: 1
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 7
                    text: {
                        var body = root.currentNotification?.body || "";
                        body = body.replace(/<[^>]*>/g, "");
                        body = body.replace(/\n/g, " ");
                        return body;
                    }
                    color: "#cdd6f4"
                    font.pixelSize: 11
                    font.bold: false
                    font.family: "Inter"
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.Wrap
                    visible: (root.currentNotification?.image || root.currentNotification?.appIcon) !== "" && (root.currentNotification?.body || "") !== ""
                }

                // Fallback: no icon — show sender: message centered
                Text {
                    anchors.centerIn: parent
                    anchors.margins: 10
                    text: {
                        var summary = root.currentNotification?.summary || "";
                        var body = root.currentNotification?.body || "";
                        body = body.replace(/<[^>]*>/g, "");
                        body = body.replace(/\n/g, " ");
                        var content;
                        if (summary && body) {
                            content = summary + ": " + body;
                        } else if (body) {
                            content = body;
                        } else {
                            content = summary;
                        }
                        return content.length > 48 ? content.substring(0, 45) + "..." : content;
                    }
                    color: "#cdd6f4"
                    font.pixelSize: 11
                    font.bold: false
                    font.family: "Inter"
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    visible: (root.currentNotification?.image || root.currentNotification?.appIcon) === ""
                }
            }

            // --- TIDE-STYLE OSD INDICATOR ---
            Item {
                id: osdContent
                anchors.fill: parent
                visible: islandShape.osdActive && !islandShape.isHovered
                opacity: islandShape.osdActive && !islandShape.isHovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }

                // Left: Icon
                Text {
                    text: root.osdIcon
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 22
                    color: "#ffffff"
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Center: Percentage with pop animation
                Text {
                    id: osdPercentText
                    text: Math.round(root.osdValue * 100)
                    color: "#ffffff"
                    font.pixelSize: 17
                    font.bold: true
                    font.family: "Inter"
                    font.letterSpacing: -0.5
                    anchors.centerIn: parent

                    // Pop animation on value change
                    property real lastValue: 0
                    onTextChanged: {
                        osdPercentText.scale = 1.15;
                        popAnim.restart();
                    }

                    NumberAnimation on scale {
                        id: popAnim
                        from: 1.15
                        to: 1.0
                        duration: 250
                        easing.type: Easing.OutBack
                    }
                }

                // Right: Circular progress ring
                Item {
                    width: 30
                    height: 30
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter

                    // Background circle
                    Rectangle {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        radius: 8
                        color: "#1e1e2e"
                        border.color: "#2a2a3e"
                        border.width: 1
                    }

                    // Progress arc canvas
                    Canvas {
                        anchors.fill: parent
                        antialiasing: true
                        property real progressValue: Math.max(0, Math.min(1, root.osdValue))

                        onProgressValueChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            var size = Math.min(width, height);
                            var lineWidth = 3.5;
                            var center = size / 2;
                            var radius = (size - lineWidth) / 2 - 0.5;
                            var startAngle = -Math.PI / 2;
                            var endAngle = startAngle + (Math.PI * 2 * progressValue);

                            ctx.clearRect(0, 0, width, height);
                            ctx.lineCap = "round";
                            ctx.lineWidth = lineWidth;

                            // Background ring
                            ctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
                            ctx.beginPath();
                            ctx.arc(center, center, radius, 0, Math.PI * 2, false);
                            ctx.stroke();

                            // Progress arc
                            ctx.strokeStyle = "#ffffff";
                            ctx.beginPath();
                            ctx.arc(center, center, radius, startAngle, endAngle, false);
                            ctx.stroke();
                        }
                    }
                }
            }
        }

        // --- SCREEN RECORDING INDICATOR (Protruding Circle + Pulsing Dot) ---
        // Direct child of islandShape for clean positioning
        Item {
            id: recordingIndicator
            opacity: islandShape.isRecordingNow ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            // Position relative to islandShape — with visible gap
            x: -islandShape.recordingCircleSize - 8  // gap of 8px from island edge
            y: islandShape.height / 2 - islandShape.recordingCircleSize / 2  // vertically centered with island
            width: islandShape.recordingCircleSize
            height: islandShape.recordingCircleSize

            // The protruding circle — scales up from 0 when recording starts
            Rectangle {
                id: recordingCircle
                anchors.fill: parent
                radius: islandShape.recordingCircleSize / 2
                color: "#0b0b12"  // same as island background
                border.color: "#313244"  // same as island border
                border.width: 1

                // Scale animation: circle "grows out" from the island
                scale: islandShape.isRecordingNow ? 1 : 0
                Behavior on scale {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                }

                // Pulsing red dot inside the circle
                Rectangle {
                    id: recordingDot
                    width: 14
                    height: 14
                    radius: 7
                    color: "#ff4444"
                    anchors.centerIn: parent

                    // Opacity pulse animation — "recording now" feel
                    SequentialAnimation on opacity {
                        id: pulseAnim
                        running: islandShape.isRecordingNow
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 0.2; duration: 1000; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }

        // --- SCREEN SHARING INDICATOR (Orange Circle + Text on Hover) ---
        Item {
            id: screenShareIndicator
            opacity: (islandShape.isScreenSharingNow && !islandShape.isRecordingNow) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            // Position: left of recording indicator (or left of island if not recording)
            x: islandShape.isRecordingNow ? -(islandShape.recordingCircleSize * 2 + 16) : (-islandShape.recordingCircleSize - 8)
            y: islandShape.height / 2 - islandShape.recordingCircleSize / 2
            width: islandShape.recordingCircleSize
            height: islandShape.recordingCircleSize

            Rectangle {
                id: screenShareCircle
                anchors.fill: parent
                radius: islandShape.recordingCircleSize / 2
                color: "#0b0b12"
                border.color: "#313244"
                border.width: 1

                scale: (islandShape.isScreenSharingNow && !islandShape.isRecordingNow) ? 1 : 0
                Behavior on scale {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                }

                // Orange dot
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    color: "#ff9900"
                    anchors.centerIn: parent

                    SequentialAnimation on opacity {
                        running: islandShape.isScreenSharingNow && !islandShape.isRecordingNow
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 0.2; duration: 1000; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }

        // Screen sharing text — shows on hover
        Text {
            opacity: (islandShape.isScreenSharingNow && !islandShape.isRecordingNow && islandShape.isHovered) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

            text: "Sharing Screen"
            color: "#ffaa44"
            font.pixelSize: 13
            font.bold: true
            font.family: "Inter"
            font.letterSpacing: 0.5
            anchors.centerIn: parent
        }

        // Recording timer — shows on hover in the center
        Text {
            opacity: (islandShape.isRecordingNow && islandShape.isHovered) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

            text: root.recordingSeconds > 0 ? root.formatRecordingTime(root.recordingSeconds) : "0:00"
            color: "#ff6666"
            font.pixelSize: 16
            font.bold: true
            font.family: "Inter"
            font.letterSpacing: 0.5
            anchors.centerIn: parent
        }
        }
}
