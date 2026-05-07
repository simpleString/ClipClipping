import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtMultimedia

Basic.ApplicationWindow {
    id: root
    width: 1230
    height: 720
    minimumWidth: 1230 
    minimumHeight: 620
    visible: true
    title: "ClipClipping"
    color: "#1a1a2e"

    readonly property bool hasVideo: appController.hasVideo
    readonly property real safeDuration: Math.max(0.001, appController.duration)
    property var subtitleOptions: [{ label: "Off", index: -1 }]
    property bool syncingSubtitleSelection: false
    property bool mediaLoadedInitDone: false
    property bool timelineScrubbing: false
    property bool scrubResumePlaybackAfterRelease: false
    property real scrubTargetTime: 0
    property real scrubLastAppliedTime: -1
    readonly property color buttonBg: "#1f2b46"
    readonly property color buttonBgHover: "#26385c"
    readonly property color buttonBorder: "#3a5078"
    readonly property color buttonBorderHover: "#6fa7ff"
    readonly property color buttonText: "#d8e6ff"
    readonly property color buttonTextDisabled: "#7f90b0"
    readonly property color fieldBg: "#131d33"
    readonly property color fieldBorder: "#34507a"
    readonly property color fieldBorderFocus: "#6fa7ff"
    readonly property color panelBg: "#111a2c"

    function clamp(v, minV, maxV) {
        return Math.max(minV, Math.min(maxV, v))
    }

    function formatTime(seconds) {
        const s = Math.max(0, seconds)
        const mins = Math.floor(s / 60)
        const secs = Math.floor(s % 60)
        const cs = Math.floor((s % 1) * 100)
        return mins + ":" + (secs < 10 ? "0" : "") + secs + "." + (cs < 10 ? "0" : "") + cs
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

    function scrubTo(seconds) {
        const clamped = clamp(seconds, 0, safeDuration)
        player.position = Math.round(clamped * 1000)
        appController.currentTime = clamped
    }

    function setScrubTarget(seconds) {
        scrubTargetTime = clamp(seconds, 0, safeDuration)
        appController.currentTime = scrubTargetTime
    }

    function subtitleTrackLabel(track, idx) {
        const title = (track && track.title) ? String(track.title).trim() : ""
        const language = (track && track.language) ? String(track.language).trim() : ""
        const base = title.length > 0 ? title : ("Subtitle " + (idx + 1))
        return language.length > 0 ? (base + " (" + language + ")") : base
    }

    function rebuildSubtitleOptions() {
        syncingSubtitleSelection = true
        const options = [{ label: "Off", index: -1 }]
        const tracks = player.subtitleTracks || []
        for (let i = 0; i < tracks.length; ++i)
            options.push({ label: subtitleTrackLabel(tracks[i], i), index: i })
        subtitleOptions = options

        const active = player.activeSubtitleTrack
        appController.subtitleStreamIndex = active
        let selected = 0
        for (let i = 0; i < options.length; ++i) {
            if (options[i].index === active) {
                selected = i
                break
            }
        }
        subtitleSelect.currentIndex = selected
        syncingSubtitleSelection = false
    }

    function applyMarkIn() {
        if (!hasVideo || startInput.activeFocus || endInput.activeFocus)
            return
        const frameSec = 1.0 / Math.max(1, appController.videoFps)
        const minGap = Math.max(0.001, frameSec)
        appController.startTime = clamp(appController.currentTime, 0, appController.endTime - minGap)
    }

    function applyMarkOut() {
        if (!hasVideo || startInput.activeFocus || endInput.activeFocus)
            return
        const frameSec = 1.0 / Math.max(1, appController.videoFps)
        const minGap = Math.max(0.001, frameSec)
        appController.endTime = clamp(appController.currentTime, appController.startTime + minGap, safeDuration)
    }

    function togglePlayback() {
        if (!hasVideo)
            return
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause()
        else
            player.play()
    }

    function clearEditFocus() {
        if (startInput)
            startInput.focus = false
        if (endInput)
            endInput.focus = false
        if (cursorTimeInput)
            cursorTimeInput.focus = false
    }

    function pointInsideItem(item, sceneX, sceneY) {
        if (!item)
            return false
        const p = item.mapFromItem(root.contentItem, sceneX, sceneY)
        return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height
    }

    function clearEditFocusIfOutside(sceneX, sceneY) {
        if (pointInsideItem(startInput, sceneX, sceneY))
            return
        if (pointInsideItem(endInput, sceneX, sceneY))
            return
        if (pointInsideItem(cursorTimeInput, sceneX, sceneY))
            return
        clearEditFocus()
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: (point) => {
            clearEditFocusIfOutside(point.position.x, point.position.y)
        }
    }

    MediaPlayer {
        id: player
        source: appController.videoUrl
        videoOutput: videoSurface
        audioOutput: playerAudio
        onSourceChanged: {
            mediaLoadedInitDone = false
        }
        onPositionChanged: {
            if (timelineScrubbing)
                return
            appController.currentTime = player.position / 1000.0
        }
        onSubtitleTracksChanged: {
            rebuildSubtitleOptions()
        }
        onActiveSubtitleTrackChanged: {
            rebuildSubtitleOptions()
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && !mediaLoadedInitDone) {
                mediaLoadedInitDone = true
                player.play()
                player.pause()
                player.position = 0
                appController.currentTime = 0
                rebuildSubtitleOptions()
            }
        }
    }

    AudioOutput {
        id: playerAudio
        volume: 1.0
        muted: true
    }

    Timer {
        id: scrubUpdateTimer
        interval: 33
        repeat: true
        running: false
        onTriggered: {
            if (!timelineScrubbing)
                return
            if (Math.abs(scrubTargetTime - scrubLastAppliedTime) < 0.001)
                return
            const targetMs = Math.round(scrubTargetTime * 1000)
            scrubLastAppliedTime = scrubTargetTime
            if (Math.abs(player.position - targetMs) >= 2)
                player.position = targetMs
        }
    }

    Connections {
        target: keyState
        function onMarkInPressed() { applyMarkIn() }
        function onMarkOutPressed() { applyMarkOut() }
    }

    Shortcut {
        sequence: "Space"
        enabled: hasVideo
        onActivated: togglePlayback()
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

    Shortcut {
        sequences: ["Alt++", "Alt+=", "Alt+Up"]
        enabled: hasVideo && !startInput.activeFocus && !endInput.activeFocus
        onActivated: {
            timelinePanel.applyZoom(1.2)
        }
    }

    Shortcut {
        sequences: ["Alt+-", "Alt+_", "Alt+Down"]
        enabled: hasVideo && !startInput.activeFocus && !endInput.activeFocus
        onActivated: {
            timelinePanel.applyZoom(1.0 / 1.2)
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
                    text: "ClipClipping"
                    color: "#64b5f6"
                    font.pixelSize: 18
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        visible: !appController.converting
                        Layout.fillWidth: true
                    }
                    Basic.ProgressBar {
                        visible: appController.converting
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: appController.progress
                        background: Rectangle {
                            implicitHeight: 10
                            radius: 5
                            color: "#1b2740"
                            border.width: 1
                            border.color: "#34507a"
                        }
                        contentItem: Rectangle {
                            radius: 5
                            color: "#5c9dff"
                            width: parent.width * (parent.visualPosition || 0)
                        }
                    }
                    Basic.Label {
                        visible: appController.converting
                        text: appController.progress + "%"
                        color: "#64b5f6"
                        font.pixelSize: 12
                    }
                    Basic.Button {
                        visible: appController.converting
                        text: "Cancel"
                        onClicked: appController.cancelConversion()
                        background: Rectangle {
                            radius: 6
                            border.width: 1
                            border.color: parent.hovered ? buttonBorderHover : buttonBorder
                            color: parent.hovered ? buttonBgHover : buttonBg
                        }
                        contentItem: Text {
                            text: parent.text
                            color: buttonText
                            font.bold: true
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        implicitHeight: 28
                        leftPadding: 14
                        rightPadding: 14
                    }
                }

                Basic.Button {
                    id: helpButton
                    text: "?"
                    onClicked: helpPopup.open()
                    background: Rectangle {
                        radius: 6
                        border.width: 1
                        border.color: parent.hovered ? buttonBorderHover : buttonBorder
                        color: parent.hovered ? buttonBgHover : buttonBg
                    }
                    contentItem: Text {
                        text: parent.text
                        color: buttonText
                        font.pixelSize: 16
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    implicitWidth: 34
                    implicitHeight: 32
                    ToolTip.visible: hovered
                    ToolTip.text: "How to use"
                }

                Basic.Button {
                    visible: hasVideo
                    text: playerAudio.muted ? "Sound: Off" : "Sound: On"
                    onClicked: playerAudio.muted = !playerAudio.muted
                    background: Rectangle {
                        radius: 6
                        border.width: 1
                        border.color: parent.hovered ? buttonBorderHover : buttonBorder
                        color: parent.hovered ? buttonBgHover : buttonBg
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? buttonText : buttonTextDisabled
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    implicitHeight: 32
                    leftPadding: 12
                    rightPadding: 12
                    ToolTip.visible: hovered
                    ToolTip.text: playerAudio.muted ? "Unmute preview" : "Mute preview"
                }

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
                        border.color: parent.hovered ? buttonBorderHover : buttonBorder
                        color: parent.hovered ? buttonBgHover : buttonBg
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? buttonText : buttonTextDisabled
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    implicitHeight: 32
                    leftPadding: 12
                    rightPadding: 12
                    ToolTip.visible: hovered
                    ToolTip.text: "Return to file selection"
                }
            }

            Popup {
                id: helpPopup
                parent: Overlay.overlay
                width: Math.min(root.width - 40, 460)
                height: implicitHeight
                modal: true
                focus: true
                anchors.centerIn: parent
                padding: 14
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                background: Rectangle {
                    color: panelBg
                    border.color: "#2f466e"
                    border.width: 1
                    radius: 10
                }

                Column {
                    width: helpPopup.availableWidth
                    spacing: 8

                    Basic.Label {
                        text: "Quick Start"
                        color: "#e8f0ff"
                        font.pixelSize: 18
                        font.bold: true
                    }

                    Basic.Label { text: "1. Click Select Video or drag and drop a file."; color: "#c9d7ef"; font.pixelSize: 13 }
                    Basic.Label { text: "2. Set Start and End points on the timeline."; color: "#c9d7ef"; font.pixelSize: 13 }
                    Basic.Label { text: "3. Adjust FPS and output width."; color: "#c9d7ef"; font.pixelSize: 13 }
                    Basic.Label { text: "4. Choose subtitles (optional)."; color: "#c9d7ef"; font.pixelSize: 13 }
                    Basic.Label { text: "5. Choose export format and click Create."; color: "#c9d7ef"; font.pixelSize: 13 }

                    Rectangle { width: parent.width; height: 1; color: "#2f466e" }

                    Basic.Label {
                        text: "Keyboard Shortcuts"
                        color: "#e8f0ff"
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Basic.Label { text: "Space: Play / Pause"; color: "#c9d7ef"; font.pixelSize: 12 }
                    Basic.Label { text: "Left / Right: Previous / Next frame"; color: "#c9d7ef"; font.pixelSize: 12 }
                    Basic.Label { text: "I / O: Set Start / End marker"; color: "#c9d7ef"; font.pixelSize: 12 }
                    Basic.Label { text: "Alt + Mouse Wheel: Zoom timeline"; color: "#c9d7ef"; font.pixelSize: 12 }
                    Basic.Label { text: "Alt + + / Alt + -: Zoom in / out"; color: "#c9d7ef"; font.pixelSize: 12 }

                    Item { width: 1; height: 4 }

                    Row {
                        width: parent.width
                        Item { width: parent.width - gotItButton.implicitWidth; height: 1 }
                        Basic.Button {
                            id: gotItButton
                            text: "Got it"
                            onClicked: helpPopup.close()
                            background: Rectangle {
                                radius: 6
                                border.width: 1
                                border.color: parent.hovered ? buttonBorderHover : buttonBorder
                                color: parent.hovered ? buttonBgHover : buttonBg
                            }
                            contentItem: Text {
                                text: parent.text
                                color: buttonText
                                font.pixelSize: 14
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            implicitHeight: 34
                            leftPadding: 16
                            rightPadding: 16
                        }
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
                    clearEditFocus()
                    togglePlayback()
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: !hasVideo
                color: "#1a1a2e"

                DropArea {
                    anchors.fill: parent
                    onDropped: (drop) => {
                        if (drop.hasUrls && drop.urls.length > 0) {
                            const u = drop.urls[0]
                            if (u && typeof u.toLocalFile === "function")
                                appController.openVideo(u.toLocalFile())
                            else {
                                const raw = String(u)
                                const path = raw.indexOf("file://") === 0
                                    ? decodeURIComponent(raw.replace("file://", ""))
                                    : raw
                                appController.openVideo(path)
                            }
                        }
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
                            text: "ClipClipping for creating clip clippings"
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
                                border.width: 1
                                border.color: parent.hovered ? buttonBorderHover : buttonBorder
                                color: parent.hovered ? buttonBgHover : buttonBg
                            }
                            contentItem: Text {
                                text: parent.text
                                color: buttonText
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
                    const pxPerFrameTarget = 36.0
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

                function setZoomScale(scaleValue) {
                    const oldScale = timelinePanel.timelineScale
                    const newScale = clamp(scaleValue, timelinePanel.minScale, timelinePanel.maxScale)
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

                function sliderToScale(normValue) {
                    const t = clamp(normValue, 0, 1)
                    const ratio = Math.max(1.0001, timelinePanel.maxScale / timelinePanel.minScale)
                    return timelinePanel.minScale * Math.pow(ratio, t)
                }

                function scaleToSlider(scaleValue) {
                    const clamped = clamp(scaleValue, timelinePanel.minScale, timelinePanel.maxScale)
                    const ratio = Math.max(1.0001, timelinePanel.maxScale / timelinePanel.minScale)
                    return Math.log(clamped / timelinePanel.minScale) / Math.log(ratio)
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
                    height: 28
                    Basic.Label {
                        text: "Start"
                        color: "#8ea4c7"
                        font.pixelSize: 10
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                    }
                    Basic.TextField {
                        id: startInput
                        width: 80
                        text: formatTime(appController.startTime)
                        color: "#e0e0e0"
                        font.pixelSize: 12
                        selectByMouse: true
                        selectedTextColor: "#0d1527"
                        selectionColor: "#8bb8ff"
                        padding: 6
                        background: Rectangle {
                            radius: 4
                            color: fieldBg
                            border.width: 1
                            border.color: startInput.activeFocus ? fieldBorderFocus : fieldBorder
                        }
                        onEditingFinished: {
                            const t = parseTimeInput(text)
                            if (t >= 0)
                                appController.startTime = timelinePanel.snapToFrame(clamp(t, 0, appController.endTime - 0.1))
                            text = formatTime(appController.startTime)
                        }
                    }
                    Basic.Label {
                        text: "→"
                        color: "#55709a"
                        font.pixelSize: 13
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                    }
                    Basic.Label {
                        text: "End"
                        color: "#8ea4c7"
                        font.pixelSize: 10
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                    }
                    Basic.TextField {
                        id: endInput
                        width: 80
                        text: formatTime(appController.endTime)
                        color: "#e0e0e0"
                        font.pixelSize: 12
                        selectByMouse: true
                        selectedTextColor: "#0d1527"
                        selectionColor: "#8bb8ff"
                        padding: 6
                        background: Rectangle {
                            radius: 4
                            color: fieldBg
                            border.width: 1
                            border.color: endInput.activeFocus ? fieldBorderFocus : fieldBorder
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
                        color: fieldBg
                        border.width: 1
                        border.color: fieldBorder
                        height: 26
                        width: 74
                        Basic.Label {
                            anchors.centerIn: parent
                            text: formatTime(appController.endTime - appController.startTime)
                            color: "#c9d7ef"
                            font.pixelSize: 12
                        }
                    }

                    Basic.Label {
                        text: "Cursor"
                        color: "#8ea4c7"
                        font.pixelSize: 10
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                    }
                    Basic.TextField {
                        id: cursorTimeInput
                        width: 80
                        text: formatTime(appController.currentTime)
                        color: "#e0e0e0"
                        font.pixelSize: 12
                        selectByMouse: true
                        selectedTextColor: "#0d1527"
                        selectionColor: "#8bb8ff"
                        padding: 6
                        background: Rectangle {
                            radius: 4
                            color: fieldBg
                            border.width: 1
                            border.color: cursorTimeInput.activeFocus ? fieldBorderFocus : fieldBorder
                        }
                        onEditingFinished: {
                            const t = parseTimeInput(text)
                            if (t >= 0)
                                seekTo(clamp(t, 0, safeDuration))
                            text = formatTime(appController.currentTime)
                        }
                    }

                    Item { width: 8; height: 1 }

                    Basic.Button {
                        width: 26
                        height: 26
                        text: "-"
                        enabled: timelinePanel.timelineScale > timelinePanel.minScale
                        onClicked: timelinePanel.applyZoom(1.0 / 1.5)
                        background: Rectangle {
                            radius: 6
                            border.width: 1
                            border.color: parent.hovered ? buttonBorderHover : buttonBorder
                            color: parent.enabled ? (parent.hovered ? buttonBgHover : buttonBg) : "#1a2337"
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? buttonText : buttonTextDisabled
                            font.pixelSize: 14
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Zoom out (Alt+- / Alt+Down)"
                    }

                    Item {
                        width: 150
                        height: 26

                        Basic.Slider {
                            id: zoomSlider
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            implicitHeight: 18
                            padding: 0
                            from: 0
                            to: 1
                            value: timelinePanel.scaleToSlider(timelinePanel.timelineScale)
                            onMoved: timelinePanel.setZoomScale(timelinePanel.sliderToScale(value))
                            background: Rectangle {
                                x: 0
                                y: (parent.height - height) * 0.5
                                width: parent.width
                                height: 6
                                radius: 3
                                color: "#1b2740"
                                border.width: 1
                                border.color: "#34507a"

                                Rectangle {
                                    width: parent.width * zoomSlider.visualPosition
                                    height: parent.height
                                    radius: 3
                                    color: "#5c9dff"
                                }
                            }
                            handle: Rectangle {
                                x: zoomSlider.leftPadding + zoomSlider.visualPosition * (zoomSlider.availableWidth - width)
                                y: Math.round((parent.height - height) * 0.5)
                                implicitWidth: 14
                                implicitHeight: 14
                                radius: 7
                                color: zoomSlider.pressed ? "#9ec7ff" : "#d8e6ff"
                                border.width: 1
                                border.color: "#4c7bc2"
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: "Zoom timeline"
                        }
                    }

                    Basic.Button {
                        width: 26
                        height: 26
                        text: "+"
                        enabled: timelinePanel.timelineScale < timelinePanel.maxScale
                        onClicked: timelinePanel.applyZoom(1.5)
                        background: Rectangle {
                            radius: 6
                            border.width: 1
                            border.color: parent.hovered ? buttonBorderHover : buttonBorder
                            color: parent.enabled ? (parent.hovered ? buttonBgHover : buttonBg) : "#1a2337"
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? buttonText : buttonTextDisabled
                            font.pixelSize: 14
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Zoom in (Alt++ / Alt+Up)"
                    }

                    Basic.Button {
                        width: 36
                        height: 26
                        text: "Fit"
                        visible: timelinePanel.timelineScale > timelinePanel.minScale + 0.001
                        onClicked: timelinePanel.fitTimeline()
                        background: Rectangle {
                            radius: 6
                            border.width: 1
                            border.color: parent.hovered ? buttonBorderHover : buttonBorder
                            color: parent.hovered ? buttonBgHover : buttonBg
                        }
                        contentItem: Text {
                            text: parent.text
                            color: buttonText
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Fit timeline to window"
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
                    interactive: false
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
                                onPressed: clearEditFocus()
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
                                onPressed: clearEditFocus()
                                onPositionChanged: {
                                    const t = timelinePanel.snapToFrame(clamp((parent.x + 7) / timelineView.width * safeDuration, appController.startTime + 0.1, safeDuration))
                                    appController.endTime = t
                                    if (!endInput.activeFocus)
                                        endInput.text = formatTime(appController.endTime)
                                }
                            }
                        }

                        MouseArea {
                            id: timelineInputArea
                            anchors.fill: parent
                            z: 10
                            hoverEnabled: true
                            preventStealing: true
                            acceptedButtons: Qt.LeftButton

                            cursorShape: panMode
                                ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                : Qt.ArrowCursor

                            property real lastX: 0
                            property bool panMode: false

                            function applyZoom(deltaY, stepMultiplier) {
                                const oldScale = timelinePanel.timelineScale
                                const multiplier = stepMultiplier !== undefined ? stepMultiplier : 1.0
                                const step = 1.0 + ((1.2 - 1.0) * multiplier)
                                const factor = deltaY > 0 ? step : (1 / step)
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

                            onPressed: (mouse) => {
                                clearEditFocus()
                                panMode = (mouse.modifiers & Qt.ControlModifier) !== 0
                                lastX = mouse.x
                                if (panMode)
                                    return
                                scrubResumePlaybackAfterRelease = player.playbackState === MediaPlayer.PlayingState
                                player.pause()
                                timelineScrubbing = true
                                const t = clamp((mouse.x / timelineView.width) * safeDuration, 0, safeDuration)
                                setScrubTarget(t)
                                scrubLastAppliedTime = -1
                                scrubUpdateTimer.start()
                            }

                            onReleased: {
                                scrubUpdateTimer.stop()
                                scrubTo(scrubTargetTime)
                                if (!panMode && scrubResumePlaybackAfterRelease)
                                    player.play()
                                timelineScrubbing = false
                                panMode = false
                            }

                            onCanceled: {
                                scrubUpdateTimer.stop()
                                if (!panMode && scrubResumePlaybackAfterRelease)
                                    player.play()
                                timelineScrubbing = false
                                panMode = false
                            }

                            onPositionChanged: (mouse) => {
                                if (!pressed)
                                    return
                                if (panMode) {
                                    const dx = mouse.x - lastX
                                    const maxX = Math.max(0, timelineFlick.contentWidth - timelineFlick.width)
                                    timelineFlick.contentX = clamp(timelineFlick.contentX - dx, 0, maxX)
                                    lastX = mouse.x
                                    return
                                }
                                const t = clamp((mouse.x / timelineView.width) * safeDuration, 0, safeDuration)
                                setScrubTarget(t)
                            }

                            function wheelDeltaValue(wheel) {
                                const ay = (wheel.angleDelta && wheel.angleDelta.y !== undefined) ? wheel.angleDelta.y : 0
                                const ax = (wheel.angleDelta && wheel.angleDelta.x !== undefined) ? wheel.angleDelta.x : 0
                                const py = (wheel.pixelDelta && wheel.pixelDelta.y !== undefined) ? wheel.pixelDelta.y : 0
                                const px = (wheel.pixelDelta && wheel.pixelDelta.x !== undefined) ? wheel.pixelDelta.x : 0
                                if (ay !== 0)
                                    return ay
                                if (ax !== 0)
                                    return ax
                                if (py !== 0)
                                    return py
                                if (px !== 0)
                                    return px
                                if (wheel.rotation !== undefined && wheel.rotation !== 0)
                                    return wheel.rotation
                                return 0
                            }

                            onWheel: (wheel) => {
                                const isAltPressed = ((typeof keyState !== "undefined") && keyState.altPressed)
                                    || ((wheel.modifiers & Qt.AltModifier) !== 0)
                                    || ((Qt.application.keyboardModifiers & Qt.AltModifier) !== 0)
                                const delta = wheelDeltaValue(wheel)
                                if (!isAltPressed)
                                    return
                                if (delta === 0)
                                    return
                                wheel.accepted = true
                                applyZoom(delta)
                            }
                        }

                        WheelHandler {
                            id: timelineWheelHandler
                            target: null
                            acceptedDevices: PointerDevice.TouchPad
                            acceptedModifiers: Qt.AltModifier
                            onWheel: (event) => {
                                const ay = (event.angleDelta && event.angleDelta.y !== undefined) ? event.angleDelta.y : 0
                                const ax = (event.angleDelta && event.angleDelta.x !== undefined) ? event.angleDelta.x : 0
                                const py = (event.pixelDelta && event.pixelDelta.y !== undefined) ? event.pixelDelta.y : 0
                                const px = (event.pixelDelta && event.pixelDelta.x !== undefined) ? event.pixelDelta.x : 0
                                const rotation = (event.rotation !== undefined) ? event.rotation : 0
                                const delta = ay !== 0 ? ay : (ax !== 0 ? ax : (py !== 0 ? py : (px !== 0 ? px : rotation)))
                                if (delta === 0)
                                    return
                                event.accepted = true
                                timelineInputArea.applyZoom(delta, 0.5)
                            }
                        }
                    }
                }

    Connections {
        target: appController
        function onCurrentTimeChanged() {
            if (!cursorTimeInput.activeFocus)
                cursorTimeInput.text = formatTime(appController.currentTime)
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

                Connections {
                    target: keyState
                    function onAltWheel(delta) {
                        if (!hasVideo)
                            return
                        if (!timelineInputArea.containsMouse)
                            return
                        timelineInputArea.applyZoom(delta)
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
                    text: "Export Settings"
                    color: "#bbbbbb"
                    font.pixelSize: 14
                    font.bold: true
                }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                    Column {
                        spacing: 10

                        Column {
                            spacing: 4
                            Basic.Label { text: "FPS: " + appController.targetFps; color: "#999"; font.pixelSize: 12 }
                            Basic.Slider {
                                width: 220
                                implicitHeight: 18
                                padding: 0
                                from: 6
                                to: 30
                                value: appController.targetFps
                                background: Rectangle {
                                    x: 0
                                    y: (parent.height - height) * 0.5
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: "#1b2740"
                                    border.width: 1
                                    border.color: "#34507a"

                                    Rectangle {
                                        width: parent.width * ((parent.parent.value - parent.parent.from) / (parent.parent.to - parent.parent.from))
                                        height: parent.height
                                        radius: 3
                                        color: "#5c9dff"
                                    }
                                }
                                handle: Rectangle {
                                    x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                                    y: Math.round((parent.height - height) * 0.5)
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    radius: 7
                                    color: parent.pressed ? "#9ec7ff" : "#d8e6ff"
                                    border.width: 1
                                    border.color: "#4c7bc2"
                                }
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
                                implicitHeight: 18
                                padding: 0
                                from: 100
                                to: appController.stickerWebmMode ? 512 : 1024
                                value: appController.targetWidth
                                background: Rectangle {
                                    x: 0
                                    y: (parent.height - height) * 0.5
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: "#1b2740"
                                    border.width: 1
                                    border.color: "#34507a"

                                    Rectangle {
                                        width: parent.width * ((parent.parent.value - parent.parent.from) / (parent.parent.to - parent.parent.from))
                                        height: parent.height
                                        radius: 3
                                        color: "#5c9dff"
                                    }
                                }
                                handle: Rectangle {
                                    x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                                    y: Math.round((parent.height - height) * 0.5)
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    radius: 7
                                    color: parent.pressed ? "#9ec7ff" : "#d8e6ff"
                                    border.width: 1
                                    border.color: "#4c7bc2"
                                }
                                onValueChanged: {
                                    if (pressed)
                                        appController.targetWidth = Math.round(value)
                                }
                            }
                        }
                    }

                    Column {
                        spacing: 4
                        Basic.Label { text: "Clip duration: " + (appController.endTime - appController.startTime).toFixed(1) + "s"; color: "#999"; font.pixelSize: 12 }
                        Basic.Label { text: "Estimated size: ~" + appController.estimatedSizeMb.toFixed(1) + "MB"; color: "#999"; font.pixelSize: 12 }
                        Basic.Label {
                            text: appController.stickerWebmMode ? "(Auto-fit: <=256KB, <=3s)" : "(Auto-fit: <=10MB)"
                            color: "#666"
                            font.pixelSize: 10
                        }
                    }

                    Column {
                        spacing: 4
                        Basic.Label { text: "Subtitles"; color: "#999"; font.pixelSize: 12 }
                        Basic.ComboBox {
                            id: subtitleSelect
                            width: 220
                            implicitHeight: 34
                            model: subtitleOptions
                            textRole: "label"
                            enabled: subtitleOptions.length > 1
                            leftPadding: 10
                            rightPadding: 26
                            background: Rectangle {
                                radius: 6
                                color: fieldBg
                                border.width: 1
                                border.color: subtitleSelect.activeFocus ? fieldBorderFocus : fieldBorder
                            }
                            contentItem: Text {
                                text: subtitleSelect.displayText
                                color: subtitleSelect.enabled ? buttonText : buttonTextDisabled
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            indicator: Text {
                                x: subtitleSelect.width - width - 10
                                y: (subtitleSelect.height - height) / 2
                                text: "v"
                                color: "#8fb7ff"
                                font.pixelSize: 12
                            }
                            popup: Popup {
                                y: subtitleSelect.height + 2
                                width: subtitleSelect.width
                                padding: 2
                                background: Rectangle {
                                    radius: 6
                                    color: "#121c31"
                                    border.width: 1
                                    border.color: fieldBorder
                                }
                                contentItem: ListView {
                                    clip: true
                                    implicitHeight: contentHeight
                                    model: subtitleSelect.popup.visible ? subtitleSelect.delegateModel : null
                                }
                            }
                            delegate: ItemDelegate {
                                width: subtitleSelect.width - 4
                                contentItem: Text {
                                    text: modelData.label
                                    color: highlighted ? "#eaf3ff" : "#c9d7ef"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 4
                                    color: highlighted ? "#27406a" : "transparent"
                                }
                            }
                            onActivated: (index) => {
                                if (syncingSubtitleSelection)
                                    return
                                const option = subtitleOptions[index]
                                if (option) {
                                    player.activeSubtitleTrack = option.index
                                    appController.subtitleStreamIndex = option.index
                                }
                            }
                            onCurrentIndexChanged: {
                                if (syncingSubtitleSelection)
                                    return
                                const option = subtitleOptions[currentIndex]
                                if (option && player.activeSubtitleTrack !== option.index) {
                                    player.activeSubtitleTrack = option.index
                                    appController.subtitleStreamIndex = option.index
                                }
                            }
                        }

                        Item {
                            id: burnSubtitlesToggle
                            width: subtitleSelect.width
                            height: 22
                            enabled: subtitleOptions.length > 1 && subtitleSelect.currentIndex > 0

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 4
                                    color: appController.includeSubtitles ? "#4f86de" : "#131d33"
                                    border.width: 1
                                    border.color: appController.includeSubtitles ? "#7fb2ff" : "#34507a"

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 8
                                        radius: 2
                                        visible: appController.includeSubtitles
                                        color: "#eaf3ff"
                                    }
                                }

                                Text {
                                    text: "Burn subtitles into export"
                                    color: burnSubtitlesToggle.enabled ? "#b7c7e6" : "#6f83ab"
                                    font.pixelSize: 12
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: burnSubtitlesToggle.enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: appController.includeSubtitles = !appController.includeSubtitles
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Column {
                        spacing: 0
                        Layout.alignment: Qt.AlignTop

                        Item { width: 1; height: 20 }

                        Row {
                            spacing: 8

                            Basic.Button {
                                text: "GIF"
                                implicitWidth: 88
                                implicitHeight: 40
                                onClicked: appController.stickerWebmMode = false
                                background: Rectangle {
                                    radius: 8
                                    color: appController.stickerWebmMode ? "#1b2740" : "#35588a"
                                    border.width: 1
                                    border.color: appController.stickerWebmMode ? "#34507a" : "#6fa7ff"
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: appController.stickerWebmMode ? "#b7c7e6" : "#eaf3ff"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                leftPadding: 12
                                rightPadding: 12
                            }

                            Basic.Button {
                                text: "Sticker WEBM"
                                implicitWidth: 148
                                implicitHeight: 40
                                onClicked: appController.stickerWebmMode = true
                                background: Rectangle {
                                    radius: 8
                                    color: appController.stickerWebmMode ? "#35588a" : "#1b2740"
                                    border.width: 1
                                    border.color: appController.stickerWebmMode ? "#6fa7ff" : "#34507a"
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: appController.stickerWebmMode ? "#eaf3ff" : "#b7c7e6"
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                leftPadding: 12
                                rightPadding: 12
                            }
                        }
                    }

                    Column {
                        spacing: 0
                        Layout.alignment: Qt.AlignTop

                        Item { width: 1; height: 20 }

                        Basic.Button {
                            text: appController.converting ? "Converting..." : (appController.stickerWebmMode ? "Create Sticker WEBM" : "Create GIF")
                            implicitWidth: 220
                            implicitHeight: 40
                            enabled: !appController.converting && appController.endTime > appController.startTime
                            onClicked: appController.openSaveGifDialog()
                            background: Rectangle {
                                radius: 8
                                border.width: 1
                                border.color: parent.enabled ? (parent.hovered ? "#ffda8a" : "#dba44b") : "#5f4f2e"
                                color: parent.enabled ? (parent.hovered ? "#f6b14d" : "#e39b38") : "#7a6440"
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#1e1303"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            leftPadding: 14
                            rightPadding: 14
                        }

                        Basic.Label {
                            visible: appController.errorMessage.length > 0
                            text: appController.errorMessage
                            color: "#ef5350"
                            font.pixelSize: 12
                            font.bold: true
                            wrapMode: Text.WordWrap
                            width: 220
                        }
                        Basic.Label {
                            visible: appController.successMessage.length > 0
                            text: appController.successMessage
                            color: "#66bb6a"
                            font.pixelSize: 12
                            font.bold: true
                            wrapMode: Text.WordWrap
                            width: 220
                        }
                    }
                }


            }
        }
    }
}
