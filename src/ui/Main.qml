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
        const fps = Math.max(1, appController.videoFps)
        const snapped = Math.round(clamp(seconds, 0, safeDuration) * fps) / fps
        const clamped = clamp(snapped, 0, safeDuration)
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

    Shortcut {
        sequences: ["I", "Ш"]
        enabled: hasVideo && !startInput.activeFocus && !endInput.activeFocus
        onActivated: {
            const frameSec = 1.0 / Math.max(1, appController.videoFps)
            const minGap = Math.max(0.001, frameSec)
            appController.startTime = clamp(appController.currentTime, 0, appController.endTime - minGap)
        }
    }

    Shortcut {
        sequences: ["O", "Щ"]
        enabled: hasVideo && !startInput.activeFocus && !endInput.activeFocus
        onActivated: {
            const frameSec = 1.0 / Math.max(1, appController.videoFps)
            const minGap = Math.max(0.001, frameSec)
            appController.endTime = clamp(appController.currentTime, appController.startTime + minGap, safeDuration)
        }
    }

    Shortcut {
        sequence: "Left"
        enabled: hasVideo && !startInput.activeFocus && !endInput.activeFocus
        onActivated: {
            const frameSec = 1.0 / Math.max(1, appController.videoFps)
            seekTo(appController.currentTime - frameSec)
        }
    }

    Shortcut {
        sequence: "Right"
        enabled: hasVideo && !startInput.activeFocus && !endInput.activeFocus
        onActivated: {
            const frameSec = 1.0 / Math.max(1, appController.videoFps)
            seekTo(appController.currentTime + frameSec)
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
            Layout.preferredHeight: hasVideo ? 136 : 0
            visible: hasVideo
            color: "#16213e"
            border.color: "#2a2a4a"
            border.width: 1

            Item {
                id: timelinePanel
                anchors.fill: parent
                anchors.margins: 10

                property real timelineScale: 1.0
                readonly property real minScale: 1.0
                readonly property real maxScale: {
                    const fps = Math.max(1, appController.videoFps)
                    const duration = Math.max(0.001, safeDuration)
                    const viewWidth = Math.max(1, timelineFlick.width)
                    const pxPerFrameTarget = 14.0
                    const frameScale = (duration * fps * pxPerFrameTarget) / viewWidth
                    return Math.max(20.0, frameScale)
                }

                function snapToFrame(t) {
                    const fps = Math.max(1, appController.videoFps)
                    return clamp(Math.round(clamp(t, 0, safeDuration) * fps) / fps, 0, safeDuration)
                }

                function applyZoom(factor) {
                    const oldScale = timelinePanel.timelineScale
                    const newScale = clamp(oldScale * factor, timelinePanel.minScale, timelinePanel.maxScale)
                    if (Math.abs(newScale - oldScale) < 0.0001)
                        return

                    const oldContentWidth = timelineFlick.width * oldScale
                    const playheadOldX = (appController.currentTime / safeDuration) * oldContentWidth
                    const screenX = playheadOldX - timelineFlick.contentX
                    timelinePanel.timelineScale = newScale
                    const newContentWidth = timelineFlick.width * newScale
                    const newPlayheadX = (appController.currentTime / safeDuration) * newContentWidth
                    const maxContentX = Math.max(0, timelineFlick.contentWidth - timelineFlick.width)
                    timelineFlick.contentX = clamp(newPlayheadX - screenX, 0, maxContentX)
                    requestVisibleWindowThumbs()
                    thumbsDebounce.restart()
                }

                function fitTimeline() {
                    timelinePanel.timelineScale = 1.0
                    timelineFlick.contentX = 0
                    requestVisibleWindowThumbs()
                    thumbsDebounce.restart()
                }

                function requestAdaptiveThumbs() {
                    requestVisibleWindowThumbs()
                }

                function requestVisibleWindowThumbs() {
                    const total = Math.max(1, timelineFlick.contentWidth)
                    const from = clamp((timelineFlick.contentX / total) * safeDuration, 0, safeDuration)
                    const to = clamp(((timelineFlick.contentX + timelineFlick.width) / total) * safeDuration, 0, safeDuration)
                    appController.ensureThumbnailsForWindow(12, from, to)
                }

                function seekFromLocalX(localX) {
                    const absoluteX = clamp(timelineFlick.contentX + localX, 0, timelineFlick.contentWidth)
                    const t = clamp((absoluteX / timelineFlick.contentWidth) * safeDuration, 0, safeDuration)
                    seekTo(t)
                }

                Timer {
                    id: thumbsDebounce
                    interval: 180
                    repeat: false
                    onTriggered: timelinePanel.requestAdaptiveThumbs()
                }

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
                                appController.startTime = timelinePanel.snapToFrame(clamp(t, 0, appController.endTime - 0.1))
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
                                appController.endTime = timelinePanel.snapToFrame(clamp(t, appController.startTime + 0.1, safeDuration))
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

                    Basic.Button {
                        width: 26
                        height: 26
                        text: "-"
                        enabled: timelinePanel.timelineScale > timelinePanel.minScale
                        onClicked: timelinePanel.applyZoom(1.0 / 1.5)
                    }

                    Rectangle {
                        width: 44
                        height: 20
                        color: "transparent"
                        Basic.Label {
                            anchors.centerIn: parent
                            text: Math.round(timelinePanel.timelineScale * 100) + "%"
                            color: "#666"
                            font.pixelSize: 11
                        }
                    }

                    Basic.Button {
                        width: 26
                        height: 26
                        text: "+"
                        enabled: timelinePanel.timelineScale < timelinePanel.maxScale
                        onClicked: timelinePanel.applyZoom(1.5)
                    }

                    Basic.Button {
                        width: 36
                        height: 26
                        text: "Fit"
                        visible: timelinePanel.timelineScale > timelinePanel.minScale + 0.001
                        onClicked: timelinePanel.fitTimeline()
                    }

                    Basic.Label {
                        text: appController.thumbnailsGenerated + "/" + appController.thumbnailUrls.length
                        color: "#7f8a99"
                        font.pixelSize: 10
                    }
                }

                Flickable {
                    id: timelineFlick
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    height: 64
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width * timelinePanel.timelineScale
                    contentHeight: timelineView.height
                    onWidthChanged: thumbsDebounce.restart()
                    onContentXChanged: thumbsDebounce.restart()

                    Rectangle {
                        id: timelineView
                        x: 0
                        y: 0
                        width: timelineFlick.contentWidth
                        height: timelineFlick.height
                        radius: 4
                        color: "#0d0d1a"
                        border.color: "#2a2a4a"

                        Item {
                            anchors.fill: parent
                            clip: true

                            Item {
                                id: thumbsBand
                                x: (appController.thumbWindowFrom / safeDuration) * timelineView.width
                                width: Math.max(1, ((appController.thumbWindowTo - appController.thumbWindowFrom) / safeDuration) * timelineView.width)
                                height: timelineView.height

                                Row {
                                    anchors.fill: parent
                                    spacing: 1

                                    Repeater {
                                        model: appController ? appController.thumbnailUrls : []
                                        delegate: Rectangle {
                                            width: thumbsBand.width / Math.max(1, (appController ? appController.thumbnailUrls.length : 1))
                                            height: timelineView.height
                                            color: "#111"

                                            Image {
                                                anchors.fill: parent
                                                source: (modelData && modelData.length > 0) ? modelData : ""
                                                fillMode: Image.PreserveAspectCrop
                                                cache: false
                                                asynchronous: true
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: "#66000000"
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            x: (appController.startTime / safeDuration) * timelineView.width
                            width: ((appController.endTime - appController.startTime) / safeDuration) * timelineView.width
                            y: 0
                            height: parent.height
                            color: "#3364b5f6"
                            border.color: "#64b5f6"
                            border.width: 1
                        }

                        Rectangle {
                            x: (appController.currentTime / safeDuration) * timelineView.width - 1
                            y: -6
                            width: 3
                            height: timelineView.height + 12
                            radius: 2
                            color: "white"
                            z: 4
                        }

                        Rectangle {
                            x: (appController.startTime / safeDuration) * timelineView.width - 7
                            y: -4
                            width: 14
                            height: timelineView.height + 8
                            radius: 4
                            color: "#66bb6a"
                            z: 5

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.SizeHorCursor
                                drag.target: parent
                                drag.axis: Drag.XAxis
                                drag.minimumX: -7
                                drag.maximumX: ((appController.endTime / safeDuration) * timelineView.width) - 14
                                onPositionChanged: {
                                    const t = timelinePanel.snapToFrame(clamp((parent.x + 7) / timelineView.width * safeDuration, 0, appController.endTime - 0.1))
                                    appController.startTime = t
                                    if (!startInput.activeFocus)
                                        startInput.text = formatTime(appController.startTime)
                                }
                            }
                        }

                        Rectangle {
                            x: (appController.endTime / safeDuration) * timelineView.width - 7
                            y: -4
                            width: 14
                            height: timelineView.height + 8
                            radius: 4
                            color: "#ef5350"
                            z: 5

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.SizeHorCursor
                                drag.target: parent
                                drag.axis: Drag.XAxis
                                drag.minimumX: ((appController.startTime / safeDuration) * timelineView.width)
                                drag.maximumX: timelineView.width - 7
                                onPositionChanged: {
                                    const t = timelinePanel.snapToFrame(clamp((parent.x + 7) / timelineView.width * safeDuration, appController.startTime + 0.1, safeDuration))
                                    appController.endTime = t
                                    if (!endInput.activeFocus)
                                        endInput.text = formatTime(appController.endTime)
                                }
                            }
                        }

                        MouseArea {
                            id: timelineSeekArea
                            anchors.fill: parent
                            z: 2
                            onPressed: (mouse) => {
                                const t = clamp((mouse.x / timelineView.width) * safeDuration, 0, safeDuration)
                                seekTo(t)
                            }
                            onPositionChanged: (mouse) => {
                                if (!pressed)
                                    return
                                const t = clamp((mouse.x / timelineView.width) * safeDuration, 0, safeDuration)
                                seekTo(t)
                            }
                            onWheel: (wheel) => {
                                if (wheel.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.MetaModifier)) {
                                    wheel.accepted = true
                                    const oldScale = timelinePanel.timelineScale
                                    const factor = wheel.angleDelta.y > 0 ? 1.2 : 1 / 1.2
                                    const newScale = clamp(oldScale * factor, timelinePanel.minScale, timelinePanel.maxScale)
                                    if (Math.abs(newScale - oldScale) < 0.0001)
                                        return

                                    const oldContentWidth = timelineFlick.width * oldScale
                                    const playheadOldX = (appController.currentTime / safeDuration) * oldContentWidth
                                    const screenX = playheadOldX - timelineFlick.contentX
                                    timelinePanel.timelineScale = newScale
                                    const newContentWidth = timelineFlick.width * newScale
                                    const playheadNewX = (appController.currentTime / safeDuration) * newContentWidth
                                    timelineFlick.contentX = clamp(playheadNewX - screenX, 0, Math.max(0, timelineFlick.contentWidth - timelineFlick.width))
                                    timelinePanel.requestVisibleWindowThumbs()
                                    thumbsDebounce.restart()
                                }
                            }
                        }
                    }
                }

                Connections {
                    target: appController
                    function onCurrentTimeChanged() {
                        if (timelinePanel.timelineScale <= 1.001)
                            return
                        const playheadX = (appController.currentTime / safeDuration) * timelineView.width
                        const left = timelineFlick.contentX
                        const right = timelineFlick.contentX + timelineFlick.width
                        if (playheadX < left || playheadX > right)
                            timelineFlick.contentX = clamp(playheadX - timelineFlick.width * 0.5, 0, Math.max(0, timelineFlick.contentWidth - timelineFlick.width))
                    }
                    function onTrimChanged() {
                        if (!startInput.activeFocus)
                            startInput.text = formatTime(appController.startTime)
                        if (!endInput.activeFocus)
                            endInput.text = formatTime(appController.endTime)
                    }
                    function onVideoPathChanged() {
                        thumbsDebounce.restart()
                    }
                }

                Component.onCompleted: thumbsDebounce.restart()
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
