import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtMultimedia

Basic.ApplicationWindow {
    id: root
    width: 1100
    height: 760
    visible: true
    title: "Telegram GIF Maker"
    color: "#11151c"

    property bool hasVideo: appController.hasVideo

    MediaPlayer {
        id: player
        source: appController.videoUrl
        videoOutput: videoSurface
        onPositionChanged: {
            if (!timelineSeek.pressed) {
                appController.currentTime = player.position / 1000.0
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#161b22" }
            GradientStop { position: 1.0; color: "#0f141a" }
        }
    }

    DropArea {
        anchors.fill: parent
        onDropped: (drop) => {
            if (drop.hasUrls && drop.urls.length > 0) {
                appController.openVideo(drop.urls[0].toLocalFile())
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Basic.Label {
                text: "Telegram GIF Maker"
                color: "#e6edf3"
                font.pixelSize: 22
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Basic.Button {
                text: "Select Video"
                onClicked: appController.openVideoDialog()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: "#0d1117"
            border.color: "#30363d"
            border.width: 1

            StackLayout {
                anchors.fill: parent
                currentIndex: hasVideo ? 1 : 0

                Item {
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Basic.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Drop a video file here"
                            color: "#c9d1d9"
                            font.pixelSize: 20
                        }
                        Basic.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "or use Select Video"
                            color: "#8b949e"
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "#010409"
                        border.color: "#30363d"

                        VideoOutput {
                            id: videoSurface
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectFit
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Basic.Button {
                            text: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                            onClicked: {
                                if (player.playbackState === MediaPlayer.PlayingState) player.pause()
                                else player.play()
                            }
                        }

                        Basic.Button {
                            text: "Reset"
                            onClicked: {
                                player.position = 0
                                appController.currentTime = 0
                            }
                        }

                        Basic.Label {
                            text: "Current: " + appController.currentTime.toFixed(2) + "s"
                            color: "#8b949e"
                        }
                    }

                    Basic.Slider {
                        id: timelineSeek
                        Layout.fillWidth: true
                        from: 0
                        to: Math.max(0.001, appController.duration)
                        value: appController.currentTime
                        onMoved: {
                            appController.currentTime = value
                            player.position = value * 1000
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Basic.Label { text: "Start"; color: "#c9d1d9" }
                        Basic.Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(0.001, appController.duration)
                            value: appController.startTime
                            onMoved: appController.startTime = Math.min(value, appController.endTime)
                        }
                        Basic.Label { text: appController.startTime.toFixed(2) + "s"; color: "#8b949e" }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Basic.Label { text: "End"; color: "#c9d1d9" }
                        Basic.Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(0.001, appController.duration)
                            value: appController.endTime
                            onMoved: appController.endTime = Math.max(value, appController.startTime)
                        }
                        Basic.Label { text: appController.endTime.toFixed(2) + "s"; color: "#8b949e" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Basic.Label { text: "FPS"; color: "#c9d1d9" }
                        Basic.SpinBox {
                            from: 6
                            to: 30
                            value: appController.targetFps
                            onValueModified: appController.targetFps = value
                        }

                        Basic.Label { text: "Width"; color: "#c9d1d9" }
                        Basic.SpinBox {
                            from: 100
                            to: Math.max(100, appController.videoWidth)
                            value: appController.targetWidth
                            onValueModified: appController.targetWidth = value
                        }

                        Basic.Label {
                            text: "Est: ~" + appController.estimatedSizeMb.toFixed(1) + " MB"
                            color: "#8b949e"
                        }

                        Item { Layout.fillWidth: true }

                        Basic.Button {
                            enabled: !appController.converting
                            text: "Create GIF"
                            onClicked: appController.openSaveGifDialog()
                        }

                        Basic.Button {
                            enabled: appController.converting
                            text: "Cancel"
                            onClicked: appController.cancelConversion()
                        }
                    }

                    Basic.ProgressBar {
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: appController.progress
                        visible: appController.converting
                    }

                    Basic.Label {
                        Layout.fillWidth: true
                        text: appController.errorMessage
                        color: "#f85149"
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                    }

                    Basic.Label {
                        Layout.fillWidth: true
                        text: appController.successMessage
                        color: "#3fb950"
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                    }
                }
            }
        }
    }
}
