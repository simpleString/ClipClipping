import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtMultimedia

Basic.ApplicationWindow {
    id: root
    width: 1000
    height: 720
    minimumWidth: 860
    minimumHeight: 620
    visible: true
    title: "GIF Maker"
    color: "#1a1a2e"

    readonly property bool hasVideo: appController.hasVideo
    readonly property real safeDuration: Math.max(0.001, appController.duration)

    function clamp(v, minV, maxV) {
        return Math.max(minV, Math.min(maxV, v))
    }

    function formatTime(seconds) {
        const s = Math.max(0, seconds)
        const mins = Math.floor(s / 60)
        const secs = Math.floor(s % 60)
        const ds = Math.floor((s % 1) * 10)
        return mins + ":" + (secs < 10 ? "0" : "") + secs + "." + ds
    }

    function parseTimeInput(str) {
        const v = String(str).trim()
        if (!v.length)
            return -1
        if (v.indexOf(":") >= 0) {
            const p = v.split(":")
            if (p.length === 2) {
                const m = Number(p[0])
                const s = Number(p[1])
                if (!isNaN(m) && !isNaN(s))
                    return m * 60 + s
            }
        }
        const n = Number(v)
        return isNaN(n) ? -1 : n
    }

    function seekTo(seconds) {
        const clamped = clamp(seconds, 0, safeDuration)
        const ms = Math.round(clamped * 1000)
        player.position = ms
        appController.currentTime = clamped
    }

    MediaPlayer {
        id: player
        source: appController.videoUrl
        videoOutput: videoSurface
        onPositionChanged: appController.currentTime = player.position / 1000.0
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                appController.currentTime = 0
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#1a1a2e"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: "#16213e"
            border.color: "#2a2a4a"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20

                Basic.Label {
                    text: "GIF Maker"
                    color: "#64b5f6"
                    font.pixelSize: 18
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Basic.Button {
                    visible: hasVideo
                    text: "← Back"
                    onClicked: {
                        player.stop()
                        appController.clearVideo()
                    }
                    background: Rectangle {
                        radius: 6
                        border.width: 1
                        border.color: parent.hovered ? "#64b5f6" : "#3a3a5a"
                        color: "transparent"
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.hovered ? "#64b5f6" : "#aaaaaa"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0d0d1a"

            VideoOutput {
                id: videoSurface
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                visible: hasVideo
            }

            Basic.Label {
                visible: hasVideo && player.error !== MediaPlayer.NoError
                anchors.centerIn: parent
                text: "Video playback error: " + player.errorString
                color: "#ef5350"
                font.pixelSize: 13
            }

            MouseArea {
                anchors.fill: parent
                enabled: hasVideo
                onClicked: {
                    if (player.playbackState === MediaPlayer.PlayingState)
                        player.pause()
                    else
                        player.play()
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: !hasVideo
                color: "#1a1a2e"

                DropArea {
                    anchors.fill: parent
                    onDropped: (drop) => {
                        if (drop.hasUrls && drop.urls.length > 0)
                            appController.openVideo(drop.urls[0].toLocalFile())
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 560)
                    height: 280
                    color: "transparent"
                    border.width: 2
                    border.color: "#2a2a4a"
                    radius: 16

                    Column {
                        anchors.centerIn: parent
                        spacing: 16

                        Basic.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "GIF Maker for Telegram"
                            color: "#e0e0e0"
                            font.pixelSize: 24
                            font.bold: true
                        }

                        Basic.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Drag & drop a video file here, or click to browse"
                            color: "#888888"
                            font.pixelSize: 14
                        }

                        Basic.Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Select Video"
                            onClicked: appController.openVideoDialog()
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? "#42a5f5" : "#64b5f6"
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#1a1a2e"
                                font.bold: true
                                font.pixelSize: 15
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            padding: 12
                        }
                    }
                }
            }

            Basic.Label {
                visible: hasVideo
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: "Space: play/pause | Click: play/pause"
                color: "#66ffffff"
                font.pixelSize: 10
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hasVideo ? 118 : 0
            visible: hasVideo
            color: "#16213e"
            border.color: "#2a2a4a"
            border.width: 1

            Item {
                anchors.fill: parent
                anchors.margins: 10

                Row {
                    spacing: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    Basic.Label { text: "Start"; color: "#666"; font.pixelSize: 10 }
                    Basic.TextField {
                        id: startInput
                        width: 80
                        text: formatTime(appController.startTime)
                        color: "#e0e0e0"
                        font.pixelSize: 12
                        selectByMouse: true
                        background: Rectangle {
                            radius: 4
                            color: "#1a1a2e"
                            border.color: startInput.activeFocus ? "#64b5f6" : "#2a2a4a"
                        }
                        onEditingFinished: {
                            const t = parseTimeInput(text)
                            if (t >= 0)
                                appController.startTime = clamp(t, 0, appController.endTime - 0.1)
                            text = formatTime(appController.startTime)
                        }
                    }
                    Basic.Label { text: "→"; color: "#555"; font.pixelSize: 13 }
                    Basic.Label { text: "End"; color: "#666"; font.pixelSize: 10 }
                    Basic.TextField {
                        id: endInput
                        width: 80
                        text: formatTime(appController.endTime)
                        color: "#e0e0e0"
                        font.pixelSize: 12
                        selectByMouse: true
                        background: Rectangle {
                            radius: 4
                            color: "#1a1a2e"
                            border.color: endInput.activeFocus ? "#64b5f6" : "#2a2a4a"
                        }
                        onEditingFinished: {
                            const t = parseTimeInput(text)
                            if (t >= 0)
                                appController.endTime = clamp(t, appController.startTime + 0.1, safeDuration)
                            text = formatTime(appController.endTime)
                        }
                    }
                    Rectangle {
                        radius: 4
                        color: "#1a1a2e"
                        height: 24
                        width: 74
                        Basic.Label {
                            anchors.centerIn: parent
                            text: formatTime(appController.endTime - appController.startTime)
                            color: "#aaa"
                            font.pixelSize: 12
                        }
                    }
                    Item { width: 8; height: 1 }
                    Basic.Button { text: "-"; width: 26; height: 26; enabled: false }
                    Rectangle { width: 40; height: 20; color: "transparent"; Basic.Label { anchors.centerIn: parent; text: "100%"; color: "#666"; font.pixelSize: 11 } }
                    Basic.Button { text: "+"; width: 26; height: 26; enabled: false }
                }

                Rectangle {
                    id: timelineTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    height: 54
                    radius: 4
                    color: "#0d0d1a"
                    border.color: "#2a2a4a"

                    Row {
                        anchors.fill: parent
                        spacing: 1
                        clip: true

                        Repeater {
                            model: appController.thumbnailUrls
                            delegate: Rectangle {
                                width: timelineTrack.width / Math.max(1, appController.thumbnailUrls.length)
                                height: timelineTrack.height
                                color: "#111"

                                Image {
                                    anchors.fill: parent
                                    source: modelData
                                    fillMode: Image.PreserveAspectCrop
                                    cache: true
                                    asynchronous: true
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#66000000"
                                }
                            }
                        }
                    }

                    Rectangle {
                        x: (appController.startTime / safeDuration) * timelineTrack.width
                        width: ((appController.endTime - appController.startTime) / safeDuration) * timelineTrack.width
                        y: 0
                        height: parent.height
                        color: "#3364b5f6"
                        border.color: "#64b5f6"
                        border.width: 1
                    }

                    Rectangle {
                        x: (appController.currentTime / safeDuration) * timelineTrack.width - 1
                        y: -6
                        width: 3
                        height: timelineTrack.height + 12
                        radius: 2
                        color: "white"
                    }

                    Rectangle {
                        x: (appController.startTime / safeDuration) * timelineTrack.width - 6
                        y: -4
                        width: 12
                        height: timelineTrack.height + 8
                        radius: 4
                        color: "#66bb6a"
                        z: 3

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPositionChanged: (mouse) => {
                                if (!pressed)
                                    return
                                const xPos = parent.mapToItem(timelineTrack, mouse.x, 0).x
                                const t = clamp((xPos / timelineTrack.width) * safeDuration, 0, appController.endTime - 0.1)
                                appController.startTime = t
                                if (!startInput.activeFocus)
                                    startInput.text = formatTime(appController.startTime)
                            }
                        }
                    }

                    Rectangle {
                        x: (appController.endTime / safeDuration) * timelineTrack.width - 6
                        y: -4
                        width: 12
                        height: timelineTrack.height + 8
                        radius: 4
                        color: "#ef5350"
                        z: 3

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPositionChanged: (mouse) => {
                                if (!pressed)
                                    return
                                const xPos = parent.mapToItem(timelineTrack, mouse.x, 0).x
                                const t = clamp((xPos / timelineTrack.width) * safeDuration, appController.startTime + 0.1, safeDuration)
                                appController.endTime = t
                                if (!endInput.activeFocus)
                                    endInput.text = formatTime(appController.endTime)
                            }
                        }
                    }

                    Basic.Slider {
                        id: seekSlider
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: safeDuration
                        value: 0
                        Component.onCompleted: value = appController.currentTime
                        onValueChanged: {
                            if (!pressed)
                                return
                            seekTo(value)
                        }
                        background: Rectangle { color: "transparent" }
                        opacity: 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        z: 1
                        onPressed: (mouse) => seekTo((mouse.x / timelineTrack.width) * safeDuration)
                        onPositionChanged: (mouse) => {
                            if (pressed)
                                seekTo((mouse.x / timelineTrack.width) * safeDuration)
                        }
                    }
                }

                Connections {
                    target: appController
                    function onCurrentTimeChanged() {
                        if (!seekSlider.pressed)
                            seekSlider.value = appController.currentTime
                    }
                    function onTrimChanged() {
                        if (!startInput.activeFocus)
                            startInput.text = formatTime(appController.startTime)
                        if (!endInput.activeFocus)
                            endInput.text = formatTime(appController.endTime)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hasVideo ? 146 : 0
            visible: hasVideo
            color: "#16213e"
            border.color: "#2a2a4a"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Basic.Label {
                    text: "GIF Settings"
                    color: "#bbbbbb"
                    font.pixelSize: 14
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Column {
                        spacing: 4
                        Basic.Label { text: "FPS: " + appController.targetFps; color: "#999"; font.pixelSize: 12 }
                        Basic.Slider {
                            width: 160
                            from: 6
                            to: 30
                            value: appController.targetFps
                            onValueChanged: {
                                if (pressed)
                                    appController.targetFps = Math.round(value)
                            }
                        }
                    }

                    Column {
                        spacing: 4
                        Basic.Label { text: "Width: " + appController.targetWidth + "px"; color: "#999"; font.pixelSize: 12 }
                        Basic.Slider {
                            width: 220
                            from: 100
                            to: Math.max(100, appController.videoWidth)
                            value: appController.targetWidth
                            onValueChanged: {
                                if (pressed)
                                    appController.targetWidth = Math.round(value)
                            }
                        }
                    }

                    Column {
                        spacing: 4
                        Basic.Label { text: "Clip duration: " + (appController.endTime - appController.startTime).toFixed(1) + "s"; color: "#999"; font.pixelSize: 12 }
                        Basic.Label { text: "Estimated size: ~" + appController.estimatedSizeMb.toFixed(1) + "MB"; color: "#999"; font.pixelSize: 12 }
                        Basic.Label { text: "(Auto-optimized to fit under 10MB)"; color: "#666"; font.pixelSize: 10 }
                    }

                    Item { Layout.fillWidth: true }

                    Basic.Button {
                        text: appController.converting ? "Converting..." : "Create GIF"
                        enabled: !appController.converting && appController.endTime > appController.startTime
                        onClicked: appController.openSaveGifDialog()
                        background: Rectangle {
                            radius: 8
                            color: parent.enabled ? (parent.hovered ? "#42a5f5" : "#64b5f6") : "#446078"
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "#1a1a2e"
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        padding: 10
                    }

                    Basic.Button {
                        text: "Cancel"
                        visible: appController.converting
                        onClicked: appController.cancelConversion()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: appController.converting
                    Basic.ProgressBar {
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: appController.progress
                    }
                    Basic.Label {
                        text: appController.progress + "%"
                        color: "#64b5f6"
                        font.pixelSize: 12
                    }
                }

                Basic.Label {
                    visible: appController.errorMessage.length > 0
                    text: appController.errorMessage
                    color: "#ef5350"
                    font.pixelSize: 13
                }
                Basic.Label {
                    visible: appController.successMessage.length > 0
                    text: appController.successMessage
                    color: "#66bb6a"
                    font.pixelSize: 13
                }
            }
        }
    }
}
